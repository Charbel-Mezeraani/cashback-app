const express          = require('express');
const db               = require('../../config/db');
const logger           = require('../../config/logger');
const { requireAdmin } = require('../../middleware/adminAuth');

const router = express.Router();

// GET /admin/campaigns
router.get('/', requireAdmin, async (req, res) => {
  const { rows } = await db.query(`
    SELECT
      c.id, c.name, c.cashback_type, c.cashback_value, c.max_cashback,
      c.max_claims, c.claim_count, c.starts_at, c.ends_at, c.active,
      p.id AS product_id, p.name AS product_name, p.barcode, p.brand,
      ROUND(c.claim_count::numeric
        / NULLIF(c.max_claims, 0) * 100, 1)   AS fill_pct,
      COALESCE(SUM(cl.cashback_amount)
        FILTER (WHERE cl.status = 'approved'), 0) AS total_paid
    FROM campaigns c
    JOIN products p ON p.id = c.product_id
    LEFT JOIN claims cl ON cl.campaign_id = c.id
    GROUP BY c.id, p.id, p.name, p.barcode, p.brand
    ORDER BY c.created_at DESC
  `);

  res.json({ campaigns: rows });
});

// POST /admin/campaigns — create a new campaign
router.post('/', requireAdmin, async (req, res) => {
  const {
    product_id,
    name,
    cashback_type,
    cashback_value,
    max_cashback,
    max_claims,
    starts_at,
    ends_at,
  } = req.body;

  const required = ['product_id', 'name', 'cashback_type', 'cashback_value', 'starts_at', 'ends_at'];
  const missing  = required.filter((f) => !req.body[f]);
  if (missing.length) {
    return res.status(400).json({ error: `Missing fields: ${missing.join(', ')}` });
  }
  if (!['fixed', 'percent'].includes(cashback_type)) {
    return res.status(400).json({ error: 'cashback_type must be fixed or percent' });
  }
  if (new Date(ends_at) <= new Date(starts_at)) {
    return res.status(400).json({ error: 'ends_at must be after starts_at' });
  }

  const { rows: [campaign] } = await db.query(
    `INSERT INTO campaigns
       (product_id, name, cashback_type, cashback_value, max_cashback, max_claims, starts_at, ends_at)
     VALUES ($1, $2, $3::cashback_type, $4, $5, $6, $7, $8)
     RETURNING *`,
    [product_id, name, cashback_type, cashback_value, max_cashback || null, max_claims || null, starts_at, ends_at]
  );

  logger.info('campaign_created', { campaignId: campaign.id, adminId: req.admin.id, name });
  res.status(201).json({ campaign });
});

// PATCH /admin/campaigns/:id — update active flag or end date
router.patch('/:id', requireAdmin, async (req, res) => {
  const { active, ends_at, max_claims } = req.body;
  const updates = [];
  const params  = [];

  if (active !== undefined) { params.push(active);    updates.push(`active = $${params.length}`); }
  if (ends_at)              { params.push(ends_at);   updates.push(`ends_at = $${params.length}`); }
  if (max_claims)           { params.push(max_claims); updates.push(`max_claims = $${params.length}`); }

  if (!updates.length) return res.status(400).json({ error: 'Nothing to update' });

  params.push(req.params.id);
  const { rows: [campaign] } = await db.query(
    `UPDATE campaigns SET ${updates.join(', ')} WHERE id = $${params.length} RETURNING *`,
    params
  );

  if (!campaign) return res.status(404).json({ error: 'Campaign not found' });

  logger.info('campaign_updated', { campaignId: campaign.id, adminId: req.admin.id });
  res.json({ campaign });
});

// GET /admin/campaigns/:id/claims — all claims for a campaign
router.get('/:id/claims', requireAdmin, async (req, res) => {
  const limit  = Math.min(parseInt(req.query.limit  || '50', 10), 200);
  const offset =           parseInt(req.query.offset || '0',  10);

  const { rows } = await db.query(
    `SELECT
       c.id, c.status, c.cashback_amount, c.fraud_score, c.submitted_at,
       u.email AS user_email,
       r.store_name, r.purchase_date
     FROM claims c
     JOIN users    u ON u.id = c.user_id
     JOIN receipts r ON r.id = c.receipt_id
     WHERE c.campaign_id = $1
     ORDER BY c.submitted_at DESC
     LIMIT $2 OFFSET $3`,
    [req.params.id, limit, offset]
  );

  res.json({ claims: rows, limit, offset });
});

module.exports = router;
