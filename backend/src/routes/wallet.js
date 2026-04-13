const express              = require('express');
const db                   = require('../config/db');
const logger               = require('../config/logger');
const { requireAuth }      = require('../middleware/auth');
const { getWalletSummary } = require('../services/wallet');
const { createNotification } = require('../services/notifications');

const router = express.Router();

const MIN_PAYOUT = parseFloat(process.env.MIN_PAYOUT_AMOUNT || '5.00');

// GET /wallet
router.get('/', requireAuth, async (req, res) => {
  const summary = await getWalletSummary(db, req.user.id);
  if (!summary) return res.status(404).json({ error: 'Wallet not found' });
  res.json(summary);
});

// GET /wallet/transactions
router.get('/transactions', requireAuth, async (req, res) => {
  const limit  = Math.min(parseInt(req.query.limit  || '50', 10), 200);
  const offset =           parseInt(req.query.offset || '0',  10);

  const { rows: [wallet] } = await db.query(
    `SELECT id FROM wallets WHERE user_id = $1`,
    [req.user.id]
  );
  if (!wallet) return res.status(404).json({ error: 'Wallet not found' });

  const { rows } = await db.query(
    `SELECT id, amount, type, reference_id, note, created_at
     FROM   wallet_transactions
     WHERE  wallet_id = $1
     ORDER  BY created_at DESC
     LIMIT  $2 OFFSET $3`,
    [wallet.id, limit, offset]
  );

  res.json({ transactions: rows, limit, offset });
});

// POST /wallet/payout — request a payout (simulated for MVP)
router.post('/payout', requireAuth, async (req, res) => {
  const { amount } = req.body;
  const requested = parseFloat(amount);

  if (!amount || isNaN(requested) || requested <= 0) {
    return res.status(400).json({ error: 'Valid amount is required' });
  }
  if (requested < MIN_PAYOUT) {
    return res.status(422).json({
      error: `Minimum payout is $${MIN_PAYOUT.toFixed(2)}`,
    });
  }

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    // Lock wallet and check balance
    const { rows: [wallet] } = await client.query(
      `SELECT id, balance FROM wallets WHERE user_id = $1 FOR UPDATE`,
      [req.user.id]
    );

    if (!wallet) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Wallet not found' });
    }
    if (parseFloat(wallet.balance) < requested) {
      await client.query('ROLLBACK');
      return res.status(422).json({
        error: `Insufficient balance. Available: $${parseFloat(wallet.balance).toFixed(2)}`,
      });
    }

    // Deduct from wallet
    await client.query(
      `UPDATE wallets SET balance = balance - $1, updated_at = NOW() WHERE id = $2`,
      [requested, wallet.id]
    );
    await client.query(
      `INSERT INTO wallet_transactions (wallet_id, amount, type, note)
       VALUES ($1, $2, 'withdrawal', 'Payout requested')`,
      [wallet.id, -requested]
    );

    // Create payout record (simulated — auto-completes)
    const { rows: [payout] } = await client.query(
      `INSERT INTO payouts
         (user_id, wallet_id, amount, status, method, external_ref, processed_at)
       VALUES ($1, $2, $3, 'completed', 'simulated', $4, NOW())
       RETURNING id`,
      [req.user.id, wallet.id, requested, `SIM-${Date.now()}`]
    );

    await client.query('COMMIT');

    await createNotification(req.user.id, 'payout_processed', {
      title: 'Payout Processed',
      body:  `Your payout of $${requested.toFixed(2)} has been processed.`,
      data:  { payout_id: payout.id, amount: requested },
    });

    logger.info('payout_processed', { userId: req.user.id, amount: requested, payoutId: payout.id });
    res.status(201).json({
      message:   'Payout processed successfully',
      payout_id: payout.id,
      amount:    requested,
      status:    'completed',
    });

  } catch (err) {
    await client.query('ROLLBACK');
    logger.error('payout_error', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

module.exports = router;
