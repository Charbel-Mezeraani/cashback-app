const express  = require('express');
const multer   = require('multer');
const db       = require('../../config/db');
const logger   = require('../../config/logger');
const { requireAdmin } = require('../../middleware/adminAuth');

const router  = express.Router();
const upload  = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

// GET /admin/products — list all products
router.get('/', requireAdmin, async (req, res) => {
  const { rows } = await db.query(`
    SELECT p.id, p.barcode, p.name, p.brand, p.category, p.image_url,
           p.eligible_from, p.created_at,
           c.id AS campaign_id, c.name AS campaign_name,
           c.cashback_type, c.cashback_value, c.max_claims, c.claim_count,
           c.starts_at, c.ends_at, c.active
    FROM products p
    LEFT JOIN campaigns c ON c.product_id = p.id
    ORDER BY p.created_at DESC
  `);
  res.json({ products: rows });
});

// POST /admin/products — create product + campaign
router.post('/', requireAdmin, upload.single('image'), async (req, res) => {
  const { name, brand, category, barcode, cashback_type, cashback_value, max_claims } = req.body;

  if (!name || !barcode) {
    return res.status(400).json({ error: 'name and barcode are required' });
  }
  if (!cashback_value || isNaN(Number(cashback_value))) {
    return res.status(400).json({ error: 'cashback_value is required' });
  }

  // Convert uploaded image to base64 data URL
  let image_url = null;
  if (req.file) {
    const b64 = req.file.buffer.toString('base64');
    image_url = `data:${req.file.mimetype};base64,${b64}`;
  }

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const { rows: [product] } = await client.query(
      `INSERT INTO products (barcode, name, brand, category, image_url, eligible_from)
       VALUES ($1, $2, $3, $4, $5, NOW())
       RETURNING id, barcode, name, brand, category, image_url`,
      [barcode.trim(), name.trim(), brand?.trim() || null, category?.trim() || null, image_url]
    );

    const { rows: [campaign] } = await client.query(
      `INSERT INTO campaigns (product_id, name, cashback_type, cashback_value, max_claims, starts_at, ends_at)
       VALUES ($1, $2, $3, $4, $5, NOW(), NOW() + INTERVAL '90 days')
       RETURNING id, name, cashback_type, cashback_value, max_claims`,
      [
        product.id,
        `${name.trim()} Cashback`,
        cashback_type || 'fixed',
        Number(cashback_value),
        max_claims ? Number(max_claims) : 1000,
      ]
    );

    await client.query('COMMIT');
    logger.info('admin_product_created', { productId: product.id, barcode });
    return res.status(201).json({ product, campaign });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Barcode already exists' });
    }
    logger.error('admin_product_create_error', { error: err.message });
    return res.status(500).json({ error: 'Failed to create product' });
  } finally {
    client.release();
  }
});

module.exports = router;
