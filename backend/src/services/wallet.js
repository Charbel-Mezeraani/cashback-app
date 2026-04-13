/**
 * Wallet service — all functions must be called inside an open DB transaction.
 */

/**
 * Credit a user's wallet and append a ledger entry.
 * Throws if the wallet row is not found (should never happen after registration).
 */
async function creditWallet(client, userId, amount, claimId) {
  const { rows: [wallet] } = await client.query(
    `UPDATE wallets
     SET    balance    = balance + $1,
            updated_at = NOW()
     WHERE  user_id    = $2
     RETURNING id`,
    [amount, userId]
  );

  if (!wallet) throw new Error(`Wallet not found for user ${userId}`);

  await client.query(
    `INSERT INTO wallet_transactions (wallet_id, amount, type, reference_id)
     VALUES ($1, $2, 'cashback', $3)`,
    [wallet.id, amount, claimId]
  );
}

/**
 * Returns current balance + last 50 transactions for a user.
 */
async function getWalletSummary(db, userId) {
  const { rows: [wallet] } = await db.query(
    `SELECT id, balance, updated_at FROM wallets WHERE user_id = $1`,
    [userId]
  );
  if (!wallet) return null;

  const { rows: transactions } = await db.query(
    `SELECT id, amount, type, reference_id, note, created_at
     FROM   wallet_transactions
     WHERE  wallet_id = $1
     ORDER  BY created_at DESC
     LIMIT  50`,
    [wallet.id]
  );

  return { balance: parseFloat(wallet.balance), updated_at: wallet.updated_at, transactions };
}

module.exports = { creditWallet, getWalletSummary };
