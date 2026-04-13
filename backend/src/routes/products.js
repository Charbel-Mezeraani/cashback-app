const express      = require('express');
const db           = require('../config/db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// ── GET /products/:barcode ─────────────────────────────────────────────────
// Look up a product by its barcode. Used right after the Flutter barcode scan.
router.get('/:barcode', requireAuth, async (req, res) => {
  const { barcode } = req.params;

  const { rows: [product] } = await db.query(
    `SELECT
       p.id, p.barcode, p.name, p.brand, p.category, p.image_url, p.eligible_from,
       -- Include active campaign if available
       c.id              AS campaign_id,
       c.name            AS campaign_name,
       c.cashback_type,
       c.cashback_value,
       c.max_cashback,
       c.ends_at         AS campaign_ends_at
     FROM products p
     LEFT JOIN LATERAL (
       SELECT * FROM campaigns
       WHERE product_id = p.id
         AND active     = TRUE
         AND starts_at <= NOW()
         AND ends_at   >= NOW()
         AND (max_claims IS NULL OR claim_count < max_claims)
       ORDER BY cashback_value DESC
       LIMIT 1
     ) c ON TRUE
     WHERE p.barcode = $1`,
    [barcode]
  );

  if (!product) {
    return res.status(404).json({ error: 'Product not found' });
  }

  res.json({ product });
});

// ── GET /products/campaigns/active ────────────────────────────────────────────
// Returns all currently active campaigns with their product info.
// Used by the Flutter home screen to render the offers list.
router.get('/campaigns/active', requireAuth, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT
         c.id              AS campaign_id,
         c.name            AS campaign_name,
         c.cashback_type,
         c.cashback_value,
         c.max_cashback,
         c.ends_at         AS campaign_ends_at,
         p.id              AS product_id,
         p.name            AS product_name,
         p.brand,
         p.category,
         p.barcode,
         p.image_url
       FROM campaigns c
       JOIN products p ON p.id = c.product_id
       WHERE c.active    = TRUE
         AND c.starts_at <= NOW()
         AND c.ends_at   >= NOW()
         AND (c.max_claims IS NULL OR c.claim_count < c.max_claims)
       ORDER BY c.cashback_value DESC
       LIMIT 50`,
    );
    res.json({ campaigns: rows });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
