-- ─────────────────────────────────────────────────────────────────────────────
-- Admin users (separate from regular users — different auth, different table)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE admin_users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT        UNIQUE NOT NULL,
  password_hash TEXT        NOT NULL,
  name          TEXT        NOT NULL,
  role          TEXT        NOT NULL DEFAULT 'brand',  -- 'super' | 'brand'
  brand_id      UUID,                                  -- scope to a brand (future)
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- User notifications
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TYPE notification_type AS ENUM (
  'claim_approved',
  'claim_rejected',
  'claim_flagged',
  'new_offer',
  'wallet_credited',
  'payout_processed'
);

CREATE TABLE notifications (
  id          UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        notification_type NOT NULL,
  title       TEXT              NOT NULL,
  body        TEXT              NOT NULL,
  data        JSONB,                       -- extra payload (claim_id, amount, etc.)
  read        BOOLEAN           NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user    ON notifications(user_id, read, created_at DESC);
CREATE INDEX idx_notifications_unread  ON notifications(user_id) WHERE read = FALSE;

-- ─────────────────────────────────────────────────────────────────────────────
-- Payouts (simulated for MVP)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TYPE payout_status AS ENUM ('pending', 'processing', 'completed', 'failed');

CREATE TABLE payouts (
  id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID          NOT NULL REFERENCES users(id),
  wallet_id      UUID          NOT NULL REFERENCES wallets(id),
  amount         NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  status         payout_status NOT NULL DEFAULT 'pending',
  method         TEXT          NOT NULL DEFAULT 'simulated',  -- 'stripe' | 'paypal' | 'simulated'
  external_ref   TEXT,                  -- payment provider reference
  failure_reason TEXT,
  requested_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  processed_at   TIMESTAMPTZ
);

CREATE INDEX idx_payouts_user   ON payouts(user_id);
CREATE INDEX idx_payouts_status ON payouts(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed one super-admin (password: admin123456)
-- Hash generated with bcrypt rounds=12 of 'admin123456'
-- Change immediately after first login!
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO admin_users (email, password_hash, name, role) VALUES
  ('admin@cashback.app',
   '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQyCkJ1A1A5Z1bKbDI1Q1b1Gy',
   'Super Admin',
   'super');
