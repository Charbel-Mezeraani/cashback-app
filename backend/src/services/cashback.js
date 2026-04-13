/**
 * Finds the best active campaign for a product on a given purchase date,
 * then computes the exact cashback amount.
 *
 * Returns null if no eligible campaign exists.
 * Returns { campaign, cashbackAmount } on success.
 */
async function findCampaign(client, productId, purchaseDate) {
  // Purchase date must fall within the campaign window
  const { rows: [campaign] } = await client.query(
    `SELECT * FROM campaigns
     WHERE product_id = $1
       AND active     = TRUE
       AND starts_at <= $2::timestamptz
       AND ends_at   >= $2::timestamptz
       AND (max_claims IS NULL OR claim_count < max_claims)
     ORDER BY cashback_value DESC
     LIMIT 1`,
    [productId, purchaseDate]
  );

  return campaign || null;
}

/**
 * Compute actual cashback from a campaign + item price.
 */
function computeCashback(campaign, unitPrice) {
  if (campaign.cashback_type === 'fixed') {
    return parseFloat(campaign.cashback_value);
  }

  // percent
  const raw = (parseFloat(unitPrice) * parseFloat(campaign.cashback_value)) / 100;
  const capped = campaign.max_cashback
    ? Math.min(raw, parseFloat(campaign.max_cashback))
    : raw;

  return parseFloat(capped.toFixed(2));
}

module.exports = { findCampaign, computeCashback };
