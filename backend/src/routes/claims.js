const express              = require('express');
const db                   = require('../config/db');
const logger               = require('../config/logger');
const { requireAuth }      = require('../middleware/auth');
const { claimRateLimit }   = require('../middleware/rateLimit');
const { validate }         = require('../middleware/validate');
const { validateClaim }    = require('../services/validation');
const { findCampaign, computeCashback } = require('../services/cashback');
const { scoreFraud, auditLog }          = require('../services/fraud');
const { creditWallet }       = require('../services/wallet');
const { createNotification } = require('../services/notifications');

const router = express.Router();

const AUTO_APPROVE_MAX = parseInt(process.env.FRAUD_AUTO_APPROVE_MAX || '29', 10);
const AUTO_REJECT_MIN  = parseInt(process.env.FRAUD_AUTO_REJECT_MIN  || '70', 10);

// ── POST /claims ──────────────────────────────────────────────────────────────
router.post(
  '/',
  requireAuth,
  claimRateLimit,
  validate([
    { field: 'receipt_id', required: true, isUUID: true },
    { field: 'product_id', required: true, isUUID: true },
  ]),
  async (req, res) => {
    const userId = req.user.id;
    const { receipt_id, product_id } = req.body;

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // ── Validate ────────────────────────────────────────────────────────────
      const validation = await validateClaim(client, { userId, receipt_id, product_id });

      if (!validation.ok) {
        await client.query('ROLLBACK');
        await auditLog('validation_failed', {
          userId,
          detail: { code: validation.code, message: validation.message, receipt_id, product_id },
        });
        return res.status(validation.status).json({
          error: validation.message,
          code:  validation.code,
        });
      }

      const { receipt, product, item } = validation;

      // ── Find active campaign ────────────────────────────────────────────────
      const campaign = await findCampaign(client, product_id, receipt.purchase_date);
      if (!campaign) {
        await client.query('ROLLBACK');
        return res.status(422).json({
          error: 'No active cashback campaign for this product.',
          code:  'NO_CAMPAIGN',
        });
      }

      const cashbackAmount = computeCashback(campaign, item.unit_price || 0);

      // ── Insert claim (pending) ──────────────────────────────────────────────
      const { rows: [claim] } = await client.query(
        `INSERT INTO claims
           (user_id, receipt_id, receipt_item_id, product_id, campaign_id, cashback_amount)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [userId, receipt_id, item.id, product_id, campaign.id, cashbackAmount]
      );

      // ── Fraud scoring ───────────────────────────────────────────────────────
      const { score, flags } = await scoreFraud(client, { userId, receipt, claim });

      await client.query(
        `UPDATE claims SET fraud_score = $1 WHERE id = $2`,
        [score, claim.id]
      );

      if (flags.length > 0) {
        await Promise.all(
          flags.map((f) =>
            client.query(
              `INSERT INTO fraud_flags (claim_id, flag_type, detail)
               VALUES ($1, $2::fraud_flag_type, $3)`,
              [claim.id, f.type, f.detail]
            )
          )
        );
      }

      // ── Auto-resolve ────────────────────────────────────────────────────────
      let finalStatus;

      if (score <= AUTO_APPROVE_MAX) {
        finalStatus = 'approved';
        await creditWallet(client, userId, cashbackAmount, claim.id);
        await client.query(
          `UPDATE claims
           SET status = 'approved', resolved_at = NOW()
           WHERE id = $1`,
          [claim.id]
        );
        await client.query(
          `UPDATE campaigns SET claim_count = claim_count + 1 WHERE id = $1`,
          [campaign.id]
        );

      } else if (score >= AUTO_REJECT_MIN) {
        finalStatus = 'rejected';
        await client.query(
          `UPDATE claims
           SET status = 'rejected',
               rejection_reason = 'Fraud score too high',
               resolved_at = NOW()
           WHERE id = $1`,
          [claim.id]
        );

      } else {
        finalStatus = 'flagged';
        await client.query(
          `UPDATE claims SET status = 'flagged' WHERE id = $1`,
          [claim.id]
        );
      }

      await client.query('COMMIT');

      // Notify user of auto-resolution
      const notifType = finalStatus === 'approved' ? 'claim_approved'
                      : finalStatus === 'rejected' ? 'claim_rejected'
                      : 'claim_flagged';
      const notifBody = finalStatus === 'approved'
        ? `Your $${cashbackAmount.toFixed(2)} cashback has been credited to your wallet.`
        : finalStatus === 'rejected'
        ? 'Your claim was not approved due to our fraud prevention policy.'
        : 'Your claim is under review. We\'ll notify you within 24–48 hours.';

      await createNotification(userId, notifType, {
        title: finalStatus === 'approved' ? 'Cashback Approved!' : finalStatus === 'rejected' ? 'Claim Not Approved' : 'Claim Under Review',
        body:  notifBody,
        data:  { claim_id: claim.id, amount: cashbackAmount },
      });

      await auditLog(finalStatus, {
        claimId: claim.id,
        userId,
        detail: {
          product_id,
          receipt_id,
          cashback:     cashbackAmount,
          fraud_score:  score,
          flags:        flags.map((f) => f.type),
          campaign_id:  campaign.id,
        },
      });

      logger.info('claim_submitted', {
        claimId:  claim.id,
        userId,
        status:   finalStatus,
        score,
        cashback: cashbackAmount,
      });

      return res.status(201).json({
        claim_id:        claim.id,
        status:          finalStatus,
        cashback_amount: cashbackAmount,
        fraud_score:     score,
        flags:           flags.map((f) => f.type),
      });

    } catch (err) {
      await client.query('ROLLBACK');
      logger.error('claim_error', { userId, error: err.message, stack: err.stack });
      return res.status(500).json({ error: 'Internal server error' });
    } finally {
      client.release();
    }
  }
);

// ── GET /claims ───────────────────────────────────────────────────────────────
router.get('/', requireAuth, async (req, res) => {
  const limit  = Math.min(parseInt(req.query.limit  || '20', 10), 100);
  const offset =           parseInt(req.query.offset || '0',  10);
  const status = req.query.status;

  try {
    const params = [req.user.id, limit, offset];
    const statusFilter = status
      ? `AND c.status = $${params.push(status)}::claim_status`
      : '';

    const { rows } = await db.query(
      `SELECT
         c.id, c.status, c.cashback_amount, c.fraud_score,
         c.submitted_at, c.resolved_at, c.rejection_reason,
         p.name   AS product_name, p.barcode,
         r.store_name, r.purchase_date
       FROM   claims c
       JOIN   products p ON p.id = c.product_id
       JOIN   receipts r ON r.id = c.receipt_id
       WHERE  c.user_id = $1 ${statusFilter}
       ORDER  BY c.submitted_at DESC
       LIMIT  $2 OFFSET $3`,
      params
    );

    res.json({ claims: rows, limit, offset });
  } catch (err) {
    logger.error('claims_list_error', { userId: req.user.id, error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── GET /claims/:id ───────────────────────────────────────────────────────────
router.get('/:id', requireAuth, async (req, res) => {
  try {
    const { rows: [claim] } = await db.query(
      `SELECT
         c.*,
         p.name  AS product_name, p.barcode, p.brand,
         r.store_name, r.purchase_date, r.total_amount,
         camp.name AS campaign_name, camp.cashback_type, camp.cashback_value
       FROM claims c
       JOIN products  p    ON p.id    = c.product_id
       JOIN receipts  r    ON r.id    = c.receipt_id
       JOIN campaigns camp ON camp.id = c.campaign_id
       WHERE c.id = $1 AND c.user_id = $2`,
      [req.params.id, req.user.id]
    );

    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    const { rows: flags } = await db.query(
      `SELECT flag_type, detail, created_at FROM fraud_flags WHERE claim_id = $1`,
      [claim.id]
    );

    res.json({ claim, flags });
  } catch (err) {
    logger.error('claim_detail_error', { userId: req.user.id, claimId: req.params.id, error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
