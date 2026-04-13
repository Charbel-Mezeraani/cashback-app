const express            = require('express');
const db                 = require('../config/db');
const { requireAuth }    = require('../middleware/auth');
const { createPresignedUploadUrl } = require('../config/s3');
const { processReceipt } = require('../jobs/processReceipt');

const router = express.Router();

/**
 * Enqueue a receipt for async OCR processing.
 *
 * MVP: uses setImmediate (in-process, no Redis required).
 * Production: swap this function body for a Bull queue.add() call.
 */
function enqueueReceiptProcessing(receiptId) {
  setImmediate(async () => {
    try {
      await processReceipt({ receiptId });
    } catch (err) {
      console.error(`Background receipt processing failed for ${receiptId}:`, err.message);
    }
  });
}

// ── POST /receipts/upload-url ─────────────────────────────────────────────
// Step 1: Flutter requests a presigned S3 URL, uploads directly to S3, then
//         calls POST /receipts with the returned s3_key.
router.post('/upload-url', requireAuth, async (req, res) => {
  const { mime_type = 'image/jpeg' } = req.body;

  const allowed = ['image/jpeg', 'image/png', 'image/heic', 'image/webp'];
  if (!allowed.includes(mime_type)) {
    return res.status(400).json({ error: `Unsupported mime type. Allowed: ${allowed.join(', ')}` });
  }

  const { key, uploadUrl } = await createPresignedUploadUrl(req.user.id, mime_type);
  res.json({
    s3_key:     key,
    upload_url: uploadUrl,
    expires_in: parseInt(process.env.S3_PRESIGN_EXPIRY || '300'),
  });
});

// ── POST /receipts ────────────────────────────────────────────────────────
// Step 2: After the Flutter app uploads the image to S3, register the receipt
//         and kick off background OCR processing.
router.post('/', requireAuth, async (req, res) => {
  const { s3_key, image_hash } = req.body;

  if (!s3_key)     return res.status(400).json({ error: 's3_key is required' });
  if (!image_hash) return res.status(400).json({ error: 'image_hash is required' });

  // Reject duplicate image before inserting
  const { rows: [dupImage] } = await db.query(
    `SELECT id FROM receipts WHERE image_hash = $1 AND user_id = $2`,
    [image_hash, req.user.id]
  );
  if (dupImage) {
    return res.status(409).json({
      error:       'This receipt image has already been uploaded',
      existing_id: dupImage.id,
    });
  }

  // Placeholder fingerprint — replaced with real SHA-256 after OCR completes
  const placeholderFingerprint = `pending::${req.user.id}::${s3_key}`;

  const { rows: [receipt] } = await db.query(
    `INSERT INTO receipts (user_id, s3_key, fingerprint, image_hash)
     VALUES ($1, $2, $3, $4)
     RETURNING id, ocr_status, created_at`,
    [req.user.id, s3_key, placeholderFingerprint, image_hash]
  );

  enqueueReceiptProcessing(receipt.id);

  res.status(202).json({
    receipt_id: receipt.id,
    status:     receipt.ocr_status,
    message:    'Receipt queued for processing',
  });
});

// ── GET /receipts/:id ─────────────────────────────────────────────────────
// Poll for OCR status and extracted line items.
router.get('/:id', requireAuth, async (req, res) => {
  const { rows: [receipt] } = await db.query(
    `SELECT id, store_name, purchase_date, total_amount, currency,
            ocr_status, ocr_error, created_at
     FROM   receipts
     WHERE  id = $1 AND user_id = $2`,
    [req.params.id, req.user.id]
  );

  if (!receipt) return res.status(404).json({ error: 'Receipt not found' });

  let items = [];
  if (receipt.ocr_status === 'done') {
    const { rows } = await db.query(
      `SELECT ri.id, ri.description, ri.barcode, ri.quantity, ri.unit_price, ri.total_price,
              p.id   AS product_id,
              p.name AS product_name,
              p.brand
       FROM   receipt_items ri
       LEFT   JOIN products p ON p.id = ri.matched_product_id
       WHERE  ri.receipt_id = $1
       ORDER  BY ri.created_at`,
      [receipt.id]
    );
    items = rows;
  }

  res.json({ receipt, items });
});

// ── GET /receipts ─────────────────────────────────────────────────────────
router.get('/', requireAuth, async (req, res) => {
  const limit  = Math.min(parseInt(req.query.limit  || '20', 10), 100);
  const offset =           parseInt(req.query.offset || '0',  10);

  const { rows } = await db.query(
    `SELECT id, store_name, purchase_date, total_amount, currency, ocr_status, created_at
     FROM   receipts
     WHERE  user_id = $1
     ORDER  BY created_at DESC
     LIMIT  $2 OFFSET $3`,
    [req.user.id, limit, offset]
  );

  res.json({ receipts: rows, limit, offset });
});

module.exports = { router };
