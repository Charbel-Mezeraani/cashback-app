/**
 * Product matching service.
 *
 * Match strategy (in order, stops at first hit):
 *   1. Exact barcode match          → confidence 100
 *   2. Normalized barcode match     → confidence 95  (strip leading zeros etc.)
 *   3. PostgreSQL trigram similarity on product name → confidence = similarity × 100
 *      Only accepted if similarity ≥ MIN_SIMILARITY threshold.
 *
 * Requires pg_trgm extension (migration 003).
 */

const logger = require('../config/logger');

// Minimum trigram similarity (0–1) to accept a name match.
const MIN_SIMILARITY = parseFloat(process.env.MATCH_MIN_SIMILARITY || '0.4');

/**
 * Match a single OCR line item to a product in the database.
 *
 * @param {object} client  - pg transaction client
 * @param {object} item    - { barcode, description }
 * @returns {{ productId, confidence, method } | null}
 */
async function matchItem(client, item) {
  // ── 1. Exact barcode ───────────────────────────────────────────────────────
  if (item.barcode) {
    const { rows: [product] } = await client.query(
      `SELECT id FROM products WHERE barcode = $1`,
      [item.barcode]
    );
    if (product) {
      logger.debug('match_barcode_exact', { barcode: item.barcode, productId: product.id });
      return { productId: product.id, confidence: 100, method: 'barcode' };
    }

    // ── 2. Normalized barcode (strip leading zeros, whitespace) ──────────────
    const normalized = item.barcode.replace(/^0+/, '').trim();
    if (normalized !== item.barcode) {
      const { rows: [product2] } = await client.query(
        `SELECT id FROM products WHERE barcode = $1 OR barcode = $2`,
        [normalized, item.barcode.padStart(13, '0')]
      );
      if (product2) {
        logger.debug('match_barcode_normalized', { barcode: item.barcode, productId: product2.id });
        return { productId: product2.id, confidence: 95, method: 'barcode' };
      }
    }
  }

  // ── 3. Trigram similarity on name ──────────────────────────────────────────
  if (item.description) {
    const cleaned = normalizeDescription(item.description);
    if (!cleaned) return null;

    const { rows } = await client.query(
      `SELECT id, name,
              similarity(LOWER(name), LOWER($1)) AS sim
       FROM   products
       WHERE  similarity(LOWER(name), LOWER($1)) >= $2
       ORDER  BY sim DESC
       LIMIT  3`,
      [cleaned, MIN_SIMILARITY]
    );

    if (rows.length > 0) {
      const best = rows[0];
      const confidence = Math.round(parseFloat(best.sim) * 100);
      logger.debug('match_trigram', {
        description: cleaned,
        matched:     best.name,
        confidence,
        productId:   best.id,
      });
      return { productId: best.id, confidence, method: 'trigram' };
    }
  }

  logger.debug('match_none', { barcode: item.barcode, description: item.description });
  return null;
}

/**
 * Normalize an OCR description for better matching:
 *   - Lowercase
 *   - Remove quantity prefixes like "2x", "3 X"
 *   - Remove price suffixes like "$2.99"
 *   - Collapse whitespace
 */
function normalizeDescription(raw) {
  if (!raw) return null;
  return raw
    .toLowerCase()
    .replace(/\d+\s*x\s+/gi, '')          // "2x Milk" → "Milk"
    .replace(/\$[\d.,]+/g, '')             // remove prices in description
    .replace(/\b(each|ea|pk|lb|kg|oz|ml|l|g)\b/gi, '') // remove unit labels
    .replace(/[^\w\s]/g, ' ')             // remove special chars
    .replace(/\s+/g, ' ')
    .trim();
}

module.exports = { matchItem, normalizeDescription };
