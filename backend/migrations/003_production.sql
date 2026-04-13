-- ─────────────────────────────────────────────────────────────────────────────
-- Production improvements
-- ─────────────────────────────────────────────────────────────────────────────

-- Fuzzy text matching for product name lookup
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Trigram index on product names for fast similarity search
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
  ON products USING GIN (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_products_brand_trgm
  ON products USING GIN (brand gin_trgm_ops);

-- ─────────────────────────────────────────────────────────────────────────────
-- Claim audit log — immutable record of every validation decision
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE claim_audit_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id    UUID        REFERENCES claims(id) ON DELETE SET NULL,
  user_id     UUID        REFERENCES users(id)  ON DELETE SET NULL,
  event       TEXT        NOT NULL,  -- 'validation_failed' | 'ocr_done' | 'fraud_scored' | 'approved' | 'rejected' | 'flagged'
  detail      JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_claim  ON claim_audit_logs(claim_id);
CREATE INDEX idx_audit_user   ON claim_audit_logs(user_id);
CREATE INDEX idx_audit_event  ON claim_audit_logs(event);
CREATE INDEX idx_audit_time   ON claim_audit_logs(created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- OCR provider tracking — know which provider processed each receipt
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE receipts
  ADD COLUMN IF NOT EXISTS ocr_provider TEXT,        -- 'veryfi' | 'textract'
  ADD COLUMN IF NOT EXISTS ocr_confidence NUMERIC(5,2), -- 0–100
  ADD COLUMN IF NOT EXISTS phash TEXT;               -- perceptual image hash (replaces image_hash for dupe detection)

-- ─────────────────────────────────────────────────────────────────────────────
-- Matching confidence on receipt items
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE receipt_items
  ADD COLUMN IF NOT EXISTS match_confidence NUMERIC(5,2), -- 0–100; 100 = barcode exact
  ADD COLUMN IF NOT EXISTS match_method     TEXT;         -- 'barcode' | 'trigram' | 'none'
