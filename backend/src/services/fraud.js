/**
 * Fraud scoring service — production version.
 *
 * Scoring rules (additive, capped at 100):
 *
 *  Rule                              Points   Rationale
 *  ────────────────────────────────  ──────   ─────────────────────────────────
 *  Duplicate receipt fingerprint       60     Same store+date+total+items → same receipt
 *  Perceptual image duplicate          50     Same photo from different user (SQL Hamming)
 *  Repeated product claim (30 days)    40     Gaming same offer repeatedly
 *  High submission velocity (>5/24h)   30     Bot-like behavior
 *  Low OCR confidence (<50)            20     Blurry/edited image
 *  Very new account (<24h)             15     Fresh account created to claim
 *  Suspicious purchase time (future)   10     Purchase date is in the future
 *
 * Score bands (configurable via env):
 *   0–29   → auto-approve
 *   30–69  → manual review (flagged)
 *   70–100 → auto-reject
 */

const logger = require('../config/logger');
const db = require('../config/db');

const PHASH_THRESHOLD = parseInt(process.env.PHASH_THRESHOLD || '10', 10);

const RULES = {
  DUPLICATE_FINGERPRINT:    60,
  DUPLICATE_IMAGE:          50,
  REPEATED_PRODUCT_CLAIM:   40,
  HIGH_VELOCITY:            30,
  LOW_OCR_CONFIDENCE:       20,
  NEW_ACCOUNT:              15,
  SUSPICIOUS_PURCHASE_TIME: 10,
};

/**
 * Score a claim for fraud risk.
 *
 * All DB queries run within the caller's transaction client.
 * Returns { score, flags }.
 */
async function scoreFraud(client, { userId, receipt, claim }) {
  let score = 0;
  const flags = [];

  // ── Rule 1: Duplicate receipt fingerprint ─────────────────────────────────
  const { rows: dupFingerprints } = await client.query(
    `SELECT id, user_id FROM receipts
     WHERE  fingerprint = $1
       AND  id          != $2
       AND  fingerprint NOT LIKE 'pending::%'`,
    [receipt.fingerprint, receipt.id]
  );
  if (dupFingerprints.length > 0) {
    score += RULES.DUPLICATE_FINGERPRINT;
    flags.push({
      type:   'duplicate_receipt',
      detail: `Fingerprint matches ${dupFingerprints.length} other receipt(s). First: ${dupFingerprints[0].id}`,
    });
  }

  // ── Rule 2: Perceptual image hash duplicate ───────────────────────────────
  // Uses SQL Hamming distance via the hamming_distance() function (migration 007).
  // This avoids pulling hundreds of rows into JS and correctly scans all receipts.
  if (receipt.phash) {
    const { rows: [dupImage] } = await client.query(
      `SELECT id
       FROM   receipts
       WHERE  phash IS NOT NULL
         AND  id      != $1
         AND  user_id != $2
         AND  hamming_distance(phash, $3) <= $4
       LIMIT  1`,
      [receipt.id, userId, receipt.phash, PHASH_THRESHOLD]
    );
    if (dupImage) {
      score += RULES.DUPLICATE_IMAGE;
      flags.push({
        type:   'duplicate_image',
        detail: `Image perceptually matches receipt ${dupImage.id} from another user`,
      });
    }
  } else {
    // Fall back to exact image_hash comparison when pHash is unavailable
    const { rows: [dupExact] } = await client.query(
      `SELECT id FROM receipts
       WHERE  image_hash = $1
         AND  user_id   != $2
       LIMIT  1`,
      [receipt.image_hash, userId]
    );
    if (dupExact) {
      score += RULES.DUPLICATE_IMAGE;
      flags.push({
        type:   'duplicate_image',
        detail: `Exact image already submitted by another user (receipt ${dupExact.id})`,
      });
    }
  }

  // ── Rule 3: Same product claimed by this user within 30 days ─────────────
  const { rows: recentSameProduct } = await client.query(
    `SELECT id FROM claims
     WHERE  user_id    = $1
       AND  product_id = $2
       AND  status    != 'rejected'
       AND  submitted_at > NOW() - INTERVAL '30 days'
       AND  id        != $3`,
    [userId, claim.product_id, claim.id]
  );
  if (recentSameProduct.length > 0) {
    score += RULES.REPEATED_PRODUCT_CLAIM;
    flags.push({
      type:   'repeated_product_claim',
      detail: `Same product claimed ${recentSameProduct.length} time(s) within 30 days`,
    });
  }

  // ── Rule 4: High submission velocity ─────────────────────────────────────
  const { rows: [velocity] } = await client.query(
    `SELECT COUNT(*) AS cnt FROM claims
     WHERE  user_id      = $1
       AND  submitted_at > NOW() - INTERVAL '24 hours'`,
    [userId]
  );
  const claimCount = parseInt(velocity.cnt, 10);
  if (claimCount > 5) {
    score += RULES.HIGH_VELOCITY;
    flags.push({
      type:   'high_velocity',
      detail: `${claimCount} claims in the last 24 hours`,
    });
  }

  // ── Rule 5: Low OCR confidence ────────────────────────────────────────────
  if (receipt.ocr_confidence != null && parseFloat(receipt.ocr_confidence) < 50) {
    score += RULES.LOW_OCR_CONFIDENCE;
    flags.push({
      type:   'ocr_mismatch',
      detail: `Low OCR confidence: ${receipt.ocr_confidence}%`,
    });
  }

  // ── Rule 6: Account age < 24 hours ────────────────────────────────────────
  const { rows: [user] } = await client.query(
    `SELECT created_at FROM users WHERE id = $1`,
    [userId]
  );
  const accountAgeHours = (Date.now() - new Date(user.created_at).getTime()) / 3_600_000;
  if (accountAgeHours < 24) {
    score += RULES.NEW_ACCOUNT;
    flags.push({
      type:   'new_account',
      detail: `Account created ${Math.round(accountAgeHours)} hour(s) ago`,
    });
  }

  // ── Rule 7: Suspicious purchase time (future date) ────────────────────────
  if (receipt.purchase_date) {
    const purchaseDate = new Date(receipt.purchase_date);
    const now = new Date();
    // Flag if purchase_date is more than 1 day in the future (clock skew tolerance)
    if (purchaseDate > new Date(now.getTime() + 86_400_000)) {
      score += RULES.SUSPICIOUS_PURCHASE_TIME;
      flags.push({
        type:   'ocr_mismatch',
        detail: `Purchase date ${receipt.purchase_date} is in the future`,
      });
    }
  }

  const finalScore = Math.min(score, 100);

  logger.info('fraud_scored', {
    claimId:  claim.id,
    userId,
    score:    finalScore,
    flags:    flags.map((f) => f.type),
  });

  return { score: finalScore, flags };
}

/**
 * Write an audit log entry. Uses the module-level db pool (not the tx client)
 * so it succeeds even if the transaction is rolled back.
 */
async function auditLog(event, { claimId = null, userId = null, detail = {} } = {}) {
  try {
    await db.query(
      `INSERT INTO claim_audit_logs (claim_id, user_id, event, detail)
       VALUES ($1, $2, $3, $4)`,
      [claimId, userId, event, JSON.stringify(detail)]
    );
  } catch (err) {
    logger.error('audit_log_failed', { event, error: err.message });
  }
}

module.exports = { scoreFraud, auditLog };
