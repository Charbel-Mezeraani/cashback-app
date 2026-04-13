-- ─────────────────────────────────────────────────────────────────────────────
-- Production index additions
-- Run once on an existing database.
-- ─────────────────────────────────────────────────────────────────────────────

-- Compound index for fraud Rule 4 (velocity check):
--   SELECT COUNT(*) FROM claims WHERE user_id = $1 AND submitted_at > NOW() - INTERVAL '24h'
CREATE INDEX IF NOT EXISTS idx_claims_user_submitted
  ON claims(user_id, submitted_at DESC);

-- Compound index for fraud Rule 3 (repeated product claim):
--   WHERE user_id = $1 AND product_id = $2 AND status != 'rejected' AND submitted_at > ...
CREATE INDEX IF NOT EXISTS idx_claims_user_product_status
  ON claims(user_id, product_id, status, submitted_at DESC);

-- Index for pHash fraud lookup (Rule 2):
--   WHERE phash IS NOT NULL AND id != $1 AND user_id != $2
CREATE INDEX IF NOT EXISTS idx_receipts_phash
  ON receipts(phash)
  WHERE phash IS NOT NULL;

-- Index for fingerprint duplicate lookup (Rule 1):
--   WHERE fingerprint = $1 AND fingerprint NOT LIKE 'pending::%'
CREATE INDEX IF NOT EXISTS idx_receipts_fingerprint_real
  ON receipts(fingerprint)
  WHERE fingerprint NOT LIKE 'pending::%';

-- Index for admin claims list filtered by status + score:
--   WHERE status = $1 ORDER BY submitted_at DESC
CREATE INDEX IF NOT EXISTS idx_claims_status_submitted
  ON claims(status, submitted_at DESC);

-- Unread notification count:
--   WHERE user_id = $1 AND read = false
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications(user_id, read)
  WHERE read = false;

-- Wallet transaction lookups:
--   WHERE wallet_id = $1 ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet_time
  ON wallet_transactions(wallet_id, created_at DESC);
