-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────
CREATE TABLE users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT        UNIQUE NOT NULL,
  phone         TEXT        UNIQUE,
  password_hash TEXT        NOT NULL,
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- WALLETS  (one-to-one with users)
-- ─────────────────────────────────────────────
CREATE TABLE wallets (
  id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID           UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  balance    NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- WALLET TRANSACTIONS  (append-only ledger)
-- ─────────────────────────────────────────────
CREATE TYPE wallet_tx_type AS ENUM ('cashback', 'withdrawal', 'adjustment');

CREATE TABLE wallet_transactions (
  id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id    UUID           NOT NULL REFERENCES wallets(id),
  amount       NUMERIC(10, 2) NOT NULL,          -- positive = credit, negative = debit
  type         wallet_tx_type NOT NULL,
  reference_id UUID,                             -- claim_id or withdrawal_id
  note         TEXT,
  created_at   TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallet_tx_wallet ON wallet_transactions(wallet_id);

-- ─────────────────────────────────────────────
-- PRODUCTS
-- ─────────────────────────────────────────────
CREATE TABLE products (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode        TEXT        UNIQUE NOT NULL,
  name           TEXT        NOT NULL,
  brand          TEXT,
  category       TEXT,
  eligible_from  DATE        NOT NULL,  -- purchase must be on or after this date
  image_url      TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_barcode ON products(barcode);

-- ─────────────────────────────────────────────
-- CAMPAIGNS
-- ─────────────────────────────────────────────
CREATE TYPE cashback_type AS ENUM ('fixed', 'percent');

CREATE TABLE campaigns (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id      UUID          NOT NULL REFERENCES products(id),
  name            TEXT          NOT NULL,
  cashback_type   cashback_type NOT NULL,
  cashback_value  NUMERIC(10,2) NOT NULL,   -- amount in $ or percentage (0–100)
  max_cashback    NUMERIC(10,2),            -- cap for percent type; NULL = no cap
  max_claims      INT,                      -- NULL = unlimited
  claim_count     INT           NOT NULL DEFAULT 0,
  starts_at       TIMESTAMPTZ   NOT NULL,
  ends_at         TIMESTAMPTZ   NOT NULL,
  active          BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  CONSTRAINT campaigns_dates_check CHECK (ends_at > starts_at),
  CONSTRAINT campaigns_value_check  CHECK (cashback_value > 0)
);

CREATE INDEX idx_campaigns_product ON campaigns(product_id, active);
CREATE INDEX idx_campaigns_dates   ON campaigns(starts_at, ends_at);

-- ─────────────────────────────────────────────
-- RECEIPTS
-- ─────────────────────────────────────────────
CREATE TYPE ocr_status AS ENUM ('pending', 'processing', 'done', 'failed');

CREATE TABLE receipts (
  id            UUID       PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID       NOT NULL REFERENCES users(id),
  s3_key        TEXT       NOT NULL,
  fingerprint   TEXT       UNIQUE NOT NULL,  -- SHA-256(store+date+total+sorted_items)
  image_hash    TEXT       NOT NULL,         -- perceptual hash for duplicate image detection
  store_name    TEXT,
  purchase_date DATE,
  total_amount  NUMERIC(10,2),
  currency      TEXT       DEFAULT 'USD',
  ocr_raw       JSONB,                       -- full OCR response stored as-is
  ocr_status    ocr_status NOT NULL DEFAULT 'pending',
  ocr_error     TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_receipts_user        ON receipts(user_id);
CREATE INDEX idx_receipts_fingerprint ON receipts(fingerprint);
CREATE INDEX idx_receipts_image_hash  ON receipts(image_hash);
CREATE INDEX idx_receipts_ocr_status  ON receipts(ocr_status) WHERE ocr_status IN ('pending', 'processing');

-- ─────────────────────────────────────────────
-- RECEIPT LINE ITEMS
-- ─────────────────────────────────────────────
CREATE TABLE receipt_items (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id         UUID          NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
  barcode            TEXT,
  description        TEXT,
  quantity           NUMERIC(8, 3) NOT NULL DEFAULT 1,
  unit_price         NUMERIC(10,2),
  total_price        NUMERIC(10,2),
  matched_product_id UUID          REFERENCES products(id),  -- NULL if no match found
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_receipt_items_receipt  ON receipt_items(receipt_id);
CREATE INDEX idx_receipt_items_product  ON receipt_items(matched_product_id);

-- ─────────────────────────────────────────────
-- CLAIMS
-- ─────────────────────────────────────────────
CREATE TYPE claim_status AS ENUM ('pending', 'approved', 'rejected', 'flagged');

CREATE TABLE claims (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID         NOT NULL REFERENCES users(id),
  receipt_id       UUID         NOT NULL REFERENCES receipts(id),
  receipt_item_id  UUID         NOT NULL REFERENCES receipt_items(id),
  product_id       UUID         NOT NULL REFERENCES products(id),
  campaign_id      UUID         NOT NULL REFERENCES campaigns(id),
  cashback_amount  NUMERIC(10,2) NOT NULL,
  status           claim_status NOT NULL DEFAULT 'pending',
  rejection_reason TEXT,
  fraud_score      INT          NOT NULL DEFAULT 0 CHECK (fraud_score BETWEEN 0 AND 100),
  submitted_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  resolved_at      TIMESTAMPTZ,

  -- Core uniqueness constraint: one claim per product per receipt
  UNIQUE (receipt_id, product_id)
);

CREATE INDEX idx_claims_user       ON claims(user_id);
CREATE INDEX idx_claims_receipt    ON claims(receipt_id);
CREATE INDEX idx_claims_product    ON claims(product_id);
CREATE INDEX idx_claims_status     ON claims(status);
CREATE INDEX idx_claims_submitted  ON claims(submitted_at);

-- ─────────────────────────────────────────────
-- FRAUD FLAGS
-- ─────────────────────────────────────────────
CREATE TYPE fraud_flag_type AS ENUM (
  'duplicate_receipt',
  'duplicate_image',
  'repeated_product_claim',
  'high_velocity',
  'expired_claim_window',
  'purchase_before_eligible',
  'ocr_mismatch'
);

CREATE TABLE fraud_flags (
  id         UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id   UUID            NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
  flag_type  fraud_flag_type NOT NULL,
  detail     TEXT,
  created_at TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fraud_flags_claim ON fraud_flags(claim_id);

-- ─────────────────────────────────────────────
-- TRIGGER: auto-update updated_at on users
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_wallets_updated_at
  BEFORE UPDATE ON wallets
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
