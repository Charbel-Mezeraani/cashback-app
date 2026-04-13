const { Pool } = require('pg');

console.log('[DB] Connecting to:', process.env.DATABASE_URL?.replace(/:([^:@]+)@/, ':***@'));

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 30_000,
  ssl: { rejectUnauthorized: false },
});

pool.on('error', (err) => {
  console.error('Unexpected PostgreSQL client error:', err.message);
});

module.exports = {
  // Run a single query with automatic connection management
  query: (text, params) => pool.query(text, params),

  // Acquire a client for multi-statement transactions
  connect: () => pool.connect(),
};
