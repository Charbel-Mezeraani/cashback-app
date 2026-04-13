-- Migration 009: Email OTP flow
-- Changes:
--   1. Add otp_attempts column for brute-force protection
--   2. Make phone nullable (collected after email verification now)
--   3. Make full_name nullable (collected after email verification now)

-- Brute-force: track failed OTP attempts, invalidate after 5
ALTER TABLE users ADD COLUMN IF NOT EXISTS otp_attempts INT NOT NULL DEFAULT 0;

-- Phone and full_name are now collected in the profile step after email OTP
-- They were already nullable in schema (confirmed), this is a no-op safety guard
ALTER TABLE users ALTER COLUMN phone     DROP NOT NULL;
ALTER TABLE users ALTER COLUMN full_name DROP NOT NULL;

-- Drop old unique constraint on phone (NULLs are fine — enforced at profile step)
-- PostgreSQL allows multiple NULLs in a UNIQUE index, so this is safe as-is.
-- No action needed, just documenting the intent.
