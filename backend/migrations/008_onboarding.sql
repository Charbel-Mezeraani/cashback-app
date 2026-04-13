-- ─────────────────────────────────────────────────────────────────────────────
-- Onboarding & device fingerprinting
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Extend users table ────────────────────────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS full_name           TEXT,
  ADD COLUMN IF NOT EXISTS phone_verified      BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS age_range           TEXT,        -- '18-24' | '25-34' | '35-44' | '45+'
  ADD COLUMN IF NOT EXISTS city                TEXT,
  ADD COLUMN IF NOT EXISTS preferences         TEXT[],      -- ['snacks','cosmetics','beverages',...]
  ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN    NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS otp_hash            TEXT,        -- bcrypt hash of current OTP
  ADD COLUMN IF NOT EXISTS otp_expires_at      TIMESTAMPTZ;

-- ── Device sessions ───────────────────────────────────────────────────────────
-- One row per device that has ever logged into an account.
-- Used for fraud: detect same device used on multiple accounts.
CREATE TABLE IF NOT EXISTS device_sessions (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT        NOT NULL,   -- stable device identifier (androidId / IDFV / UUID stored in secure storage)
  platform      TEXT,                  -- 'android' | 'ios' | 'linux' | 'web'
  os_version    TEXT,
  app_version   TEXT,
  ip_address    TEXT,
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A device_id can only be linked to ONE user (enforces one-account-per-device).
-- To allow multiple accounts per device, remove this unique constraint.
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_sessions_device_id
  ON device_sessions(device_id);

CREATE INDEX IF NOT EXISTS idx_device_sessions_user
  ON device_sessions(user_id);

-- ── Update /auth/me to return new fields ──────────────────────────────────────
-- No schema change needed — the query in auth.js will be updated to SELECT new columns.
