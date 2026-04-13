/**
 * Image hashing service.
 *
 * Two hash types:
 *
 * 1. SHA-256 (exact)    — detects byte-identical images
 * 2. pHash / dHash      — perceptual hash using `sharp`; detects visually
 *                          similar images (same photo re-cropped, brightness
 *                          adjusted, screenshot of a photo, etc.)
 *
 * Duplicate detection strategy:
 *   - On upload: store both hashes
 *   - On fraud check: compare pHash using Hamming distance ≤ threshold
 */

const crypto = require('crypto');
const logger = require('../config/logger');

// Maximum Hamming distance between pHashes to consider images "the same".
// 0 = identical, 10 = very similar, 20+ = likely different.
const PHASH_THRESHOLD = parseInt(process.env.PHASH_THRESHOLD || '10', 10);

// ── Exact hash (SHA-256 of raw bytes) ────────────────────────────────────────

function buildExactHash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

// ── Perceptual hash (difference hash — dHash) ────────────────────────────────
/**
 * dHash algorithm:
 *   1. Resize image to 9×8 grayscale
 *   2. For each row, compare each pixel to the next pixel
 *   3. Build a 64-bit binary string; encode as 16-char hex
 *
 * Result: a 16-character hex string (64 bits).
 */
async function buildPHash(buffer) {
  try {
    const sharp = require('sharp');

    const { data } = await sharp(buffer)
      .resize(9, 8, { fit: 'fill' })
      .grayscale()
      .raw()
      .toBuffer({ resolveWithObject: true });

    let bits = '';
    for (let row = 0; row < 8; row++) {
      for (let col = 0; col < 8; col++) {
        const idx = row * 9 + col;
        bits += data[idx] < data[idx + 1] ? '1' : '0';
      }
    }

    // Convert 64-bit binary string to 16-char hex
    const hex = parseInt(bits.slice(0, 32), 2).toString(16).padStart(8, '0')
              + parseInt(bits.slice(32, 64), 2).toString(16).padStart(8, '0');

    return hex;
  } catch (err) {
    // sharp not available or image decode failed — fall back to exact hash
    logger.warn('phash_fallback', { error: err.message });
    return buildExactHash(buffer);
  }
}

/**
 * Hamming distance between two hex-encoded hashes of equal length.
 * Returns number of differing bits (0 = identical).
 */
function hammingDistance(hexA, hexB) {
  if (hexA.length !== hexB.length) return Infinity;

  let dist = 0;
  for (let i = 0; i < hexA.length; i += 2) {
    const byteA = parseInt(hexA.slice(i, i + 2), 16);
    const byteB = parseInt(hexB.slice(i, i + 2), 16);
    let xor = byteA ^ byteB;
    while (xor) {
      dist += xor & 1;
      xor >>= 1;
    }
  }
  return dist;
}

/**
 * Returns true if two pHashes are similar enough to be considered duplicates.
 */
function areSimilar(pHashA, pHashB) {
  return hammingDistance(pHashA, pHashB) <= PHASH_THRESHOLD;
}

module.exports = { buildExactHash, buildPHash, hammingDistance, areSimilar };
