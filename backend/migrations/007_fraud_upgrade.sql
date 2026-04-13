-- ─────────────────────────────────────────────────────────────────────────────
-- Fraud system upgrades
-- 1. Add 'new_account' to the fraud_flag_type enum (was missing — Rule 6 used
--    'high_velocity' as a workaround, which mis-categorized flags in the admin UI)
-- 2. Add a SQL hamming_distance() function so pHash comparison happens entirely
--    in PostgreSQL rather than pulling up to 200 rows into Node.js
-- ─────────────────────────────────────────────────────────────────────────────

-- Add new_account enum value (safe to run even if it already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'new_account'
      AND enumtypid = 'fraud_flag_type'::regtype
  ) THEN
    ALTER TYPE fraud_flag_type ADD VALUE 'new_account';
  END IF;
END
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- hamming_distance(a TEXT, b TEXT) → INT
--
-- Computes the Hamming distance between two hex-encoded bit strings of equal
-- length (our 16-char dHash values represent 64 bits).
--
-- Algorithm:
--   1. XOR each pair of hex nibbles → count of differing bits = popcount(XOR)
--   2. Sum across all nibbles
--
-- This runs entirely in SQL so fraud.js can use a WHERE clause instead of
-- fetching rows and looping in JavaScript.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION hamming_distance(a TEXT, b TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE STRICT
AS $$
  SELECT
    SUM(
      bit_count(
        (('x' || lpad(substring(a, i, 1), 2, '0'))::bit(8)) #
        (('x' || lpad(substring(b, i, 1), 2, '0'))::bit(8))
      )
    )::INT
  FROM generate_series(1, length(a)) AS i
$$;
