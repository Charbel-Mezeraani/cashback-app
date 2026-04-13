const crypto = require('crypto');

/**
 * Build a deterministic receipt fingerprint.
 *
 * The fingerprint is a SHA-256 over the canonical string:
 *   store::YYYY-MM-DD::total::item1_desc:qty:price|item2...
 *
 * Items are sorted by description so order doesn't matter.
 */
function buildFingerprint({ store_name, purchase_date, total_amount, items = [] }) {
  const store    = (store_name || '').toLowerCase().trim();
  const date     = purchase_date  || '';
  const total    = total_amount != null ? parseFloat(total_amount).toFixed(2) : '';

  const itemStr = [...items]
    .map((i) => ({
      d: (i.description || '').toLowerCase().trim(),
      q: parseFloat(i.quantity || 1).toFixed(3),
      p: parseFloat(i.unit_price || 0).toFixed(2),
    }))
    .sort((a, b) => a.d.localeCompare(b.d))
    .map((i) => `${i.d}:${i.q}:${i.p}`)
    .join('|');

  const raw = `${store}::${date}::${total}::${itemStr}`;
  return crypto.createHash('sha256').update(raw).digest('hex');
}

/**
 * Cheap perceptual "hash" for duplicate image detection.
 * Production: use a library like 'sharp' + blockhash.
 * MVP: use SHA-256 of raw image bytes (exact duplicate detection only).
 */
function buildImageHash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

module.exports = { buildFingerprint, buildImageHash };
