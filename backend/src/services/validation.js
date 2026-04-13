/**
 * Claim validation service — single place for all pre-submission checks.
 *
 * Each check returns { ok: false, status, code, message } on failure,
 * or calls the next check on success. Returns { ok: true } when all pass.
 *
 * Keeps the claims route clean: it just calls validateClaim() and handles
 * the result, with no inline business logic.
 */

const logger = require('../config/logger');

const CLAIM_WINDOW_DAYS = parseInt(process.env.CLAIM_WINDOW_DAYS || '7', 10);

/**
 * Run all validation checks for a claim submission.
 *
 * @param {object} client     - pg transaction client (with FOR UPDATE lock)
 * @param {object} params     - { userId, receipt_id, product_id }
 * @returns {{ ok, status, code, message, receipt, product, item, campaign }}
 */
async function validateClaim(client, { userId, receipt_id, product_id }) {
  // ── 1. Receipt exists and belongs to user ─────────────────────────────────
  const { rows: [receipt] } = await client.query(
    `SELECT * FROM receipts WHERE id = $1 AND user_id = $2 FOR UPDATE`,
    [receipt_id, userId]
  );
  if (!receipt) {
    return fail(404, 'RECEIPT_NOT_FOUND', 'Receipt not found');
  }

  // ── 2. OCR must be complete ────────────────────────────────────────────────
  if (receipt.ocr_status === 'pending' || receipt.ocr_status === 'processing') {
    return fail(409, 'OCR_PENDING', 'Receipt is still being processed. Try again shortly.');
  }
  if (receipt.ocr_status === 'failed') {
    return fail(422, 'OCR_FAILED', receipt.ocr_error ?? 'Receipt processing failed. Please re-upload.');
  }

  // ── 3. Purchase date must exist ────────────────────────────────────────────
  if (!receipt.purchase_date) {
    return fail(422, 'NO_PURCHASE_DATE', 'Could not extract purchase date from receipt.');
  }

  // ── 4. Claim window check ──────────────────────────────────────────────────
  const daysSince = (Date.now() - new Date(receipt.purchase_date).getTime()) / 86_400_000;
  if (daysSince > CLAIM_WINDOW_DAYS) {
    return fail(
      422,
      'CLAIM_WINDOW_EXPIRED',
      `Claims must be submitted within ${CLAIM_WINDOW_DAYS} days of purchase. This receipt is ${Math.floor(daysSince)} days old.`
    );
  }

  // ── 5. Product exists ──────────────────────────────────────────────────────
  const { rows: [product] } = await client.query(
    `SELECT * FROM products WHERE id = $1`,
    [product_id]
  );
  if (!product) {
    return fail(404, 'PRODUCT_NOT_FOUND', 'Product not found');
  }

  // ── 6. Purchase date must be after product eligibility start ───────────────
  if (new Date(receipt.purchase_date) < new Date(product.eligible_from)) {
    return fail(
      422,
      'PURCHASE_BEFORE_ELIGIBLE',
      `This product is only eligible for purchases from ${product.eligible_from} onward.`
    );
  }

  // ── 7. Duplicate claim guard (same product, same receipt) ──────────────────
  const { rows: [existing] } = await client.query(
    `SELECT id FROM claims WHERE receipt_id = $1 AND product_id = $2`,
    [receipt_id, product_id]
  );
  if (existing) {
    return fail(409, 'DUPLICATE_CLAIM', 'This product has already been claimed on this receipt.');
  }

  // ── 8. Product must appear on the receipt ─────────────────────────────────
  const { rows: [item] } = await client.query(
    `SELECT * FROM receipt_items
     WHERE  receipt_id = $1 AND matched_product_id = $2
     ORDER  BY match_confidence DESC NULLS LAST
     LIMIT  1`,
    [receipt_id, product_id]
  );
  if (!item) {
    return fail(422, 'PRODUCT_NOT_ON_RECEIPT', 'This product was not found on the uploaded receipt.');
  }

  logger.info('claim_validated', { userId, receipt_id, product_id });
  return { ok: true, receipt, product, item };
}

function fail(status, code, message) {
  logger.info('claim_validation_failed', { status, code, message });
  return { ok: false, status, code, message };
}

module.exports = { validateClaim };
