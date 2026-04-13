/**
 * Background job: process a receipt after S3 upload.
 *
 * Pipeline:
 *   1. Mark receipt as 'processing'
 *   2. Call OCR API → extract store, date, items, total
 *   3. Build receipt fingerprint (SHA-256 over normalized fields)
 *   4. Build pHash (perceptual hash for duplicate image detection)
 *   5. Match each line item to a known product (barcode → trigram)
 *   6. Mark receipt as 'done'
 */

const db                       = require('../config/db');
const logger                   = require('../config/logger');
const { getObjectBuffer }      = require('../config/s3');
const { extractReceipt }       = require('../services/ocr');
const { buildFingerprint }     = require('../services/fingerprint');
const { buildPHash }           = require('../services/imaging');
const { matchItem }            = require('../services/matching');
const { auditLog }             = require('../services/fraud');

async function processReceipt({ receiptId }) {
  logger.info('receipt_job_start', { receiptId });

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    // Lock row and check current status
    const { rows: [receipt] } = await client.query(
      `SELECT * FROM receipts WHERE id = $1 FOR UPDATE`,
      [receiptId]
    );

    if (!receipt) throw new Error(`Receipt ${receiptId} not found`);

    if (receipt.ocr_status === 'done') {
      await client.query('ROLLBACK');
      logger.info('receipt_already_processed', { receiptId });
      return;
    }

    await client.query(
      `UPDATE receipts SET ocr_status = 'processing' WHERE id = $1`,
      [receiptId]
    );
    await client.query('COMMIT');

    // ── OCR (outside transaction to avoid long lock) ─────────────────────────
    let extracted;
    try {
      extracted = await extractReceipt(receipt.s3_key);
    } catch (ocrErr) {
      await db.query(
        `UPDATE receipts
         SET ocr_status = 'failed', ocr_error = $1
         WHERE id = $2`,
        [ocrErr.message, receiptId]
      );
      await auditLog('ocr_failed', {
        detail: { receiptId, error: ocrErr.message },
      });
      logger.error('receipt_ocr_failed', { receiptId, error: ocrErr.message });
      return;
    }

    // ── Fingerprint & pHash ──────────────────────────────────────────────────
    const fingerprint = buildFingerprint({
      store_name:    extracted.store_name,
      purchase_date: extracted.purchase_date,
      total_amount:  extracted.total_amount,
      items:         extracted.items,
    });

    // pHash: fetch image bytes from S3 to compute perceptual hash
    let pHash = null;
    try {
      const imageBytes = await getObjectBuffer(receipt.s3_key);
      pHash = await buildPHash(imageBytes);
    } catch (hashErr) {
      logger.warn('phash_skipped', { receiptId, error: hashErr.message });
    }

    // ── Write OCR results ────────────────────────────────────────────────────
    await client.query('BEGIN');

    await client.query(
      `UPDATE receipts
       SET store_name       = $1,
           purchase_date    = $2,
           total_amount     = $3,
           currency         = $4,
           ocr_raw          = $5,
           ocr_status       = 'done',
           ocr_provider     = $6,
           ocr_confidence   = $7,
           fingerprint      = $8,
           phash            = $9
       WHERE id = $10`,
      [
        extracted.store_name,
        extracted.purchase_date,
        extracted.total_amount,
        extracted.currency,
        JSON.stringify(extracted),
        extracted.provider,
        extracted.confidence,
        fingerprint,
        pHash,
        receiptId,
      ]
    );

    // ── Match line items ─────────────────────────────────────────────────────
    let matchedCount = 0;

    for (const item of extracted.items) {
      const match = await matchItem(client, item);

      await client.query(
        `INSERT INTO receipt_items
           (receipt_id, barcode, description, quantity, unit_price, total_price,
            matched_product_id, match_confidence, match_method)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          receiptId,
          item.barcode,
          item.description,
          item.quantity,
          item.unit_price,
          item.total_price,
          match?.productId   ?? null,
          match?.confidence  ?? null,
          match?.method      ?? 'none',
        ]
      );

      if (match) matchedCount++;
    }

    await client.query('COMMIT');

    await auditLog('ocr_done', {
      detail: {
        receiptId,
        provider:    extracted.provider,
        confidence:  extracted.confidence,
        items:       extracted.items.length,
        matched:     matchedCount,
        store:       extracted.store_name,
        date:        extracted.purchase_date,
      },
    });

    logger.info('receipt_job_done', {
      receiptId,
      provider:   extracted.provider,
      items:      extracted.items.length,
      matched:    matchedCount,
    });

  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    await db.query(
      `UPDATE receipts SET ocr_status = 'failed', ocr_error = $1 WHERE id = $2`,
      [err.message, receiptId]
    );
    logger.error('receipt_job_error', { receiptId, error: err.message, stack: err.stack });
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { processReceipt };
