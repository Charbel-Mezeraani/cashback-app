const express              = require('express');
const db                   = require('../../config/db');
const logger               = require('../../config/logger');
const { requireAdmin }     = require('../../middleware/adminAuth');
const { creditWallet }     = require('../../services/wallet');
const { auditLog }         = require('../../services/fraud');
const { createNotification } = require('../../services/notifications');

const router = express.Router();

// GET /admin/claims — all claims with filters
router.get('/', requireAdmin, async (req, res) => {
  const limit   = Math.min(parseInt(req.query.limit  || '50', 10), 200);
  const offset  =           parseInt(req.query.offset || '0',  10);
  const status  = req.query.status;  // filter: flagged | pending | approved | rejected
  const minScore = req.query.min_score;

  const params = [limit, offset];
  const where  = [];
  if (status)   { params.push(status);    where.push(`c.status = $${params.length}::claim_status`); }
  if (minScore) { params.push(minScore);  where.push(`c.fraud_score >= $${params.length}`); }

  const whereStr = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const { rows } = await db.query(
    `SELECT
       c.id, c.status, c.cashback_amount, c.fraud_score,
       c.submitted_at, c.resolved_at, c.rejection_reason,
       u.id AS user_id, u.email AS user_email,
       p.name AS product_name, p.barcode,
       r.store_name, r.purchase_date, r.total_amount, r.ocr_confidence,
       camp.name AS campaign_name
     FROM claims c
     JOIN users    u    ON u.id    = c.user_id
     JOIN products p    ON p.id    = c.product_id
     JOIN receipts r    ON r.id    = c.receipt_id
     JOIN campaigns camp ON camp.id = c.campaign_id
     ${whereStr}
     ORDER BY c.submitted_at DESC
     LIMIT $1 OFFSET $2`,
    params
  );

  res.json({ claims: rows, limit, offset });
});

// GET /admin/claims/:id — full claim detail with fraud flags + audit log
router.get('/:id', requireAdmin, async (req, res) => {
  const { rows: [claim] } = await db.query(
    `SELECT
       c.*,
       u.email AS user_email, u.created_at AS user_created_at,
       p.name AS product_name, p.barcode, p.brand,
       r.store_name, r.purchase_date, r.total_amount, r.s3_key,
       r.ocr_confidence, r.ocr_provider, r.fingerprint,
       camp.name AS campaign_name, camp.cashback_type, camp.cashback_value
     FROM claims c
     JOIN users     u    ON u.id    = c.user_id
     JOIN products  p    ON p.id    = c.product_id
     JOIN receipts  r    ON r.id    = c.receipt_id
     JOIN campaigns camp ON camp.id = c.campaign_id
     WHERE c.id = $1`,
    [req.params.id]
  );

  if (!claim) return res.status(404).json({ error: 'Claim not found' });

  const [flags, auditLogs, userHistory] = await Promise.all([
    db.query(
      `SELECT flag_type, detail, created_at FROM fraud_flags WHERE claim_id = $1`,
      [claim.id]
    ),
    db.query(
      `SELECT event, detail, created_at FROM claim_audit_logs
       WHERE claim_id = $1 ORDER BY created_at ASC`,
      [claim.id]
    ),
    db.query(
      `SELECT id, status, cashback_amount, fraud_score, submitted_at
       FROM claims WHERE user_id = $1 AND id != $2
       ORDER BY submitted_at DESC LIMIT 10`,
      [claim.user_id, claim.id]
    ),
  ]);

  res.json({
    claim,
    flags:        flags.rows,
    audit_log:    auditLogs.rows,
    user_history: userHistory.rows,
  });
});

// POST /admin/claims/:id/approve — manually approve a flagged claim
router.post('/:id/approve', requireAdmin, async (req, res) => {
  const { note } = req.body;
  const client = await db.connect();

  try {
    await client.query('BEGIN');

    const { rows: [claim] } = await client.query(
      `SELECT * FROM claims WHERE id = $1 FOR UPDATE`,
      [req.params.id]
    );

    if (!claim) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Claim not found' });
    }
    if (claim.status === 'approved') {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Claim is already approved' });
    }

    await creditWallet(client, claim.user_id, claim.cashback_amount, claim.id);
    await client.query(
      `UPDATE claims
       SET status = 'approved', resolved_at = NOW(), rejection_reason = NULL
       WHERE id = $1`,
      [claim.id]
    );
    await client.query(
      `UPDATE campaigns SET claim_count = claim_count + 1 WHERE id = $1`,
      [claim.campaign_id]
    );

    await client.query('COMMIT');

    await Promise.all([
      auditLog('approved', {
        claimId: claim.id,
        userId:  claim.user_id,
        detail:  { manual: true, adminId: req.admin.id, note },
      }),
      createNotification(claim.user_id, 'claim_approved', {
        title: 'Cashback Approved!',
        body:  `Your cashback of $${parseFloat(claim.cashback_amount).toFixed(2)} has been approved.`,
        data:  { claim_id: claim.id, amount: claim.cashback_amount },
      }),
    ]);

    logger.info('claim_manually_approved', {
      claimId: claim.id, adminId: req.admin.id, amount: claim.cashback_amount,
    });

    res.json({ message: 'Claim approved', claim_id: claim.id });
  } catch (err) {
    await client.query('ROLLBACK');
    logger.error('admin_approve_error', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// POST /admin/claims/:id/reject — manually reject a flagged claim
router.post('/:id/reject', requireAdmin, async (req, res) => {
  const { reason = 'Rejected after manual review' } = req.body;

  const { rows: [claim] } = await db.query(
    `UPDATE claims
     SET status = 'rejected', rejection_reason = $1, resolved_at = NOW()
     WHERE id = $2 AND status != 'approved'
     RETURNING *`,
    [reason, req.params.id]
  );

  if (!claim) {
    return res.status(404).json({ error: 'Claim not found or already approved' });
  }

  await Promise.all([
    auditLog('rejected', {
      claimId: claim.id,
      userId:  claim.user_id,
      detail:  { manual: true, adminId: req.admin.id, reason },
    }),
    createNotification(claim.user_id, 'claim_rejected', {
      title: 'Claim Not Approved',
      body:  `Your cashback claim was not approved. Reason: ${reason}`,
      data:  { claim_id: claim.id },
    }),
  ]);

  logger.info('claim_manually_rejected', { claimId: claim.id, adminId: req.admin.id, reason });
  res.json({ message: 'Claim rejected', claim_id: claim.id });
});

module.exports = router;
