-- Migration 010: Add country and date_of_birth to users table

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS country       TEXT,
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;
