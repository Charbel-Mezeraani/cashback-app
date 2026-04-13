require('dotenv').config();

const app  = require('./app');
const PORT = parseInt(process.env.PORT || '3000', 10);
const db   = require('./config/db');
const path = require('path');
const fs   = require('fs');

async function runMigrations() {
  const files = [
    '001_initial_schema.sql',
    '002_seed_data.sql',
    '003_production.sql',
    '004_admin_notifications.sql',
    '005_seed_expanded.sql',
    '006_indexes.sql',
    '007_fraud_upgrade.sql',
    '008_onboarding.sql',
    '009_email_otp.sql',
    '010_country_dob.sql',
  ];

  let client;
  try {
    client = await db.connect();
    for (const file of files) {
      const filePath = path.join(__dirname, '..', 'migrations', file);
      if (!fs.existsSync(filePath)) continue;
      const sql = fs.readFileSync(filePath, 'utf8');
      await client.query(sql);
      console.log(`Migration applied: ${file}`);
    }
  } catch (err) {
    console.error('Migration error (non-fatal):', err.message);
  } finally {
    if (client) client.release();
  }
}

async function start() {
  await runMigrations();
  app.listen(PORT, () => {
    console.log(`Cashback API running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
  });
}

start();
