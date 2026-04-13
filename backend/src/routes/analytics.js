/**
 * Analytics API — powers the admin dashboard.
 * All endpoints require admin JWT (type: 'admin').
 *
 * Endpoints:
 *   GET /analytics/overview          — KPI cards (users, claims, cashback, revenue)
 *   GET /analytics/growth            — daily/weekly/monthly growth series
 *   GET /analytics/top-products      — top products by claims / cashback paid
 *   GET /analytics/top-brands        — top brands
 *   GET /analytics/categories        — category distribution
 *   GET /analytics/campaigns         — campaign performance (CPA, ROI, conversion)
 *   GET /analytics/users             — user metrics (LTV, frequency, retention)
 *   GET /analytics/heatmap           — purchase activity by day-of-week × hour
 *   GET /analytics/insights          — AI-style rule-based business insights
 */

const express = require('express');
const db      = require('../config/db');

const router = express.Router();

// ── Simple admin auth (checks JWT type = 'admin' OR env ADMIN_KEY header) ────
function adminAuth(req, res, next) {
  const key = req.headers['x-admin-key'];
  if (key && key === process.env.ADMIN_KEY) return next();
  // Also accept admin JWT from auth middleware if already applied upstream
  if (req.user?.type === 'admin') return next();
  return res.status(401).json({ error: 'Admin access required' });
}
router.use(adminAuth);

// ── Query helpers ─────────────────────────────────────────────────────────────

function dateFilter(alias, from, to) {
  const parts = [];
  if (from) parts.push(`${alias} >= '${from}'::date`);
  if (to)   parts.push(`${alias} <= '${to}'::date`);
  return parts.length ? 'AND ' + parts.join(' AND ') : '';
}

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/overview
// Returns: users, active users, claims, cashback paid, revenue estimate
// ═════════════════════════════════════════════════════════════════════════════
router.get('/overview', async (req, res) => {
  const { from, to } = req.query;
  const df = dateFilter('c.submitted_at', from, to);

  const [users, claims, cashback, active] = await Promise.all([
    db.query(`
      SELECT
        COUNT(*)                                          AS total_users,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_30d,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')  AS new_7d
      FROM users WHERE is_active = TRUE
    `),
    db.query(`
      SELECT
        COUNT(*)                                            AS total_claims,
        COUNT(*) FILTER (WHERE status = 'approved')        AS approved,
        COUNT(*) FILTER (WHERE status = 'pending')         AS pending,
        COUNT(*) FILTER (WHERE status = 'flagged')         AS flagged,
        COUNT(*) FILTER (WHERE status = 'rejected')        AS rejected
      FROM claims c WHERE 1=1 ${df}
    `),
    db.query(`
      SELECT
        COALESCE(SUM(cashback_amount) FILTER (WHERE status = 'approved'), 0) AS total_paid,
        COALESCE(AVG(cashback_amount) FILTER (WHERE status = 'approved'), 0) AS avg_per_claim
      FROM claims c WHERE 1=1 ${df}
    `),
    db.query(`
      SELECT
        COUNT(DISTINCT user_id) FILTER (WHERE submitted_at >= NOW() - INTERVAL '1 day')   AS dau,
        COUNT(DISTINCT user_id) FILTER (WHERE submitted_at >= NOW() - INTERVAL '7 days')  AS wau,
        COUNT(DISTINCT user_id) FILTER (WHERE submitted_at >= NOW() - INTERVAL '30 days') AS mau
      FROM claims
    `),
  ]);

  const totalCashback = parseFloat(cashback.rows[0].total_paid);
  // Platform revenue: assume 15% fee on all cashback paid by brands
  const platformRevenue = totalCashback * 0.15;

  res.json({
    users: {
      total:   parseInt(users.rows[0].total_users),
      new_30d: parseInt(users.rows[0].new_30d),
      new_7d:  parseInt(users.rows[0].new_7d),
    },
    active: {
      dau: parseInt(active.rows[0].dau),
      wau: parseInt(active.rows[0].wau),
      mau: parseInt(active.rows[0].mau),
    },
    claims: {
      total:    parseInt(claims.rows[0].total_claims),
      approved: parseInt(claims.rows[0].approved),
      pending:  parseInt(claims.rows[0].pending),
      flagged:  parseInt(claims.rows[0].flagged),
      rejected: parseInt(claims.rows[0].rejected),
    },
    cashback: {
      total_paid:    totalCashback,
      avg_per_claim: parseFloat(cashback.rows[0].avg_per_claim),
      platform_revenue: platformRevenue,
    },
  });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/growth?period=daily|weekly|monthly&from=&to=
// Returns: time-series arrays for users, claims, cashback
// ═════════════════════════════════════════════════════════════════════════════
router.get('/growth', async (req, res) => {
  const { period = 'daily', from, to } = req.query;

  const trunc = period === 'weekly' ? 'week'
              : period === 'monthly' ? 'month'
              : 'day';

  const dateWhere = from || to
    ? `WHERE date_trunc('${trunc}', gs) BETWEEN
         COALESCE('${from}'::date, NOW() - INTERVAL '90 days') AND
         COALESCE('${to}'::date, NOW())`
    : '';

  const { rows } = await db.query(`
    WITH series AS (
      SELECT generate_series(
        COALESCE('${from}'::date, NOW() - INTERVAL '90 days'),
        COALESCE('${to}'::date,   NOW()),
        '1 ${trunc}'::interval
      ) AS period
    ),
    user_counts AS (
      SELECT date_trunc('${trunc}', created_at) AS period, COUNT(*) AS new_users
      FROM users GROUP BY 1
    ),
    claim_counts AS (
      SELECT date_trunc('${trunc}', submitted_at) AS period,
             COUNT(*) AS claims,
             COALESCE(SUM(cashback_amount) FILTER (WHERE status='approved'), 0) AS cashback
      FROM claims GROUP BY 1
    )
    SELECT
      TO_CHAR(s.period, 'YYYY-MM-DD') AS date,
      COALESCE(u.new_users, 0)        AS new_users,
      COALESCE(c.claims,    0)        AS claims,
      COALESCE(c.cashback,  0)        AS cashback
    FROM series s
    LEFT JOIN user_counts  u ON u.period = s.period
    LEFT JOIN claim_counts c ON c.period = s.period
    ORDER BY s.period
  `);

  res.json({ period, series: rows });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/top-products?limit=10&from=&to=&category=
// ═════════════════════════════════════════════════════════════════════════════
router.get('/top-products', async (req, res) => {
  const { limit = 10, from, to, category } = req.query;
  const df = dateFilter('c.submitted_at', from, to);
  const catFilter = category ? `AND p.category = '${category}'` : '';

  const { rows } = await db.query(`
    SELECT
      p.id,
      p.name,
      p.brand,
      p.category,
      p.barcode,
      COUNT(c.id)                                               AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'approved')         AS approved_claims,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status = 'approved'), 0) AS cashback_paid,
      ROUND(
        COUNT(c.id) FILTER (WHERE c.status = 'approved')::numeric /
        NULLIF(COUNT(c.id), 0) * 100, 1
      )                                                         AS approval_rate
    FROM products p
    LEFT JOIN claims c ON c.product_id = p.id
    WHERE 1=1 ${df} ${catFilter}
    GROUP BY p.id, p.name, p.brand, p.category, p.barcode
    ORDER BY total_claims DESC
    LIMIT $1
  `, [parseInt(limit)]);

  res.json({ products: rows });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/top-brands?limit=10&from=&to=
// ═════════════════════════════════════════════════════════════════════════════
router.get('/top-brands', async (req, res) => {
  const { limit = 10, from, to } = req.query;
  const df = dateFilter('c.submitted_at', from, to);

  const { rows } = await db.query(`
    SELECT
      p.brand,
      COUNT(DISTINCT p.id)                                           AS product_count,
      COUNT(c.id)                                                    AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'approved')              AS approved_claims,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'), 0) AS cashback_paid,
      COUNT(DISTINCT c.user_id)                                      AS unique_buyers,
      ROUND(AVG(c.cashback_amount) FILTER (WHERE c.status='approved')::numeric, 2) AS avg_cashback
    FROM products p
    LEFT JOIN claims c ON c.product_id = p.id
    WHERE p.brand IS NOT NULL ${df}
    GROUP BY p.brand
    ORDER BY total_claims DESC
    LIMIT $1
  `, [parseInt(limit)]);

  res.json({ brands: rows });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/categories — pie chart data
// ═════════════════════════════════════════════════════════════════════════════
router.get('/categories', async (req, res) => {
  const { from, to } = req.query;
  const df = dateFilter('c.submitted_at', from, to);

  const { rows } = await db.query(`
    SELECT
      COALESCE(p.category, 'Uncategorized') AS category,
      COUNT(c.id)                            AS claims,
      COUNT(DISTINCT c.user_id)              AS unique_users,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'), 0) AS cashback_paid
    FROM claims c
    JOIN products p ON p.id = c.product_id
    WHERE 1=1 ${df}
    GROUP BY p.category
    ORDER BY claims DESC
  `);

  const total = rows.reduce((s, r) => s + parseInt(r.claims), 0);
  res.json({
    categories: rows.map(r => ({
      ...r,
      claims:      parseInt(r.claims),
      unique_users: parseInt(r.unique_users),
      cashback_paid: parseFloat(r.cashback_paid),
      percentage:  total > 0 ? Math.round(parseInt(r.claims) / total * 100) : 0,
    })),
  });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/campaigns — campaign performance
// ═════════════════════════════════════════════════════════════════════════════
router.get('/campaigns', async (req, res) => {
  const { from, to } = req.query;
  const df = dateFilter('c.submitted_at', from, to);

  const { rows } = await db.query(`
    SELECT
      camp.id,
      camp.name,
      camp.cashback_type,
      camp.cashback_value,
      camp.start_date,
      camp.end_date,
      camp.is_active,
      p.name                                                           AS product_name,
      p.brand,
      p.category,
      COUNT(c.id)                                                      AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'approved')                AS approved_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'rejected')                AS rejected_claims,
      COUNT(DISTINCT c.user_id)                                        AS unique_claimants,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'), 0) AS total_cashback_paid,
      ROUND(
        COUNT(c.id) FILTER (WHERE c.status='approved')::numeric /
        NULLIF(COUNT(c.id), 0) * 100, 1
      )                                                                AS conversion_rate,
      -- CPA: cashback paid per approved claim
      ROUND(
        COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'), 0) /
        NULLIF(COUNT(c.id) FILTER (WHERE c.status='approved'), 0), 2
      )                                                                AS cpa,
      -- Estimated sales lift (assumes each claim = 1 purchase)
      COUNT(c.id) FILTER (WHERE c.status='approved')                   AS sales_units
    FROM campaigns camp
    JOIN products p ON p.id = camp.product_id
    LEFT JOIN claims c ON c.product_id = p.id
    WHERE 1=1 ${df}
    GROUP BY camp.id, camp.name, camp.cashback_type, camp.cashback_value,
             camp.start_date, camp.end_date, camp.is_active,
             p.name, p.brand, p.category
    ORDER BY total_claims DESC
  `);

  res.json({
    campaigns: rows.map(r => ({
      ...r,
      total_claims:      parseInt(r.total_claims),
      approved_claims:   parseInt(r.approved_claims),
      rejected_claims:   parseInt(r.rejected_claims),
      unique_claimants:  parseInt(r.unique_claimants),
      total_cashback_paid: parseFloat(r.total_cashback_paid),
      conversion_rate:   parseFloat(r.conversion_rate) || 0,
      cpa:               parseFloat(r.cpa) || 0,
      // ROI estimate: assume brand revenue = $5 per unit, ROI = (revenue - cashback) / cashback
      roi: r.total_cashback_paid > 0
        ? Math.round(((parseInt(r.sales_units) * 5) - parseFloat(r.total_cashback_paid))
            / parseFloat(r.total_cashback_paid) * 100)
        : null,
    })),
  });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/users — LTV, frequency, high-value segments
// ═════════════════════════════════════════════════════════════════════════════
router.get('/users', async (req, res) => {
  const { from, to } = req.query;
  const df = dateFilter('c.submitted_at', from, to);

  const [segments, frequency, retention] = await Promise.all([
    // User value segmentation
    db.query(`
      SELECT
        CASE
          WHEN total_cashback >= 50  THEN 'High Value (>$50)'
          WHEN total_cashback >= 20  THEN 'Mid Value ($20–$50)'
          WHEN total_cashback > 0    THEN 'Low Value (<$20)'
          ELSE 'No Claims'
        END AS segment,
        COUNT(*) AS users
      FROM (
        SELECT u.id,
               COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'), 0) AS total_cashback
        FROM users u
        LEFT JOIN claims c ON c.user_id = u.id
        WHERE u.is_active = TRUE ${df}
        GROUP BY u.id
      ) t
      GROUP BY segment ORDER BY users DESC
    `),
    // Purchase frequency distribution
    db.query(`
      SELECT
        claim_count,
        COUNT(*) AS users
      FROM (
        SELECT user_id, COUNT(*) FILTER (WHERE status='approved') AS claim_count
        FROM claims c WHERE 1=1 ${df}
        GROUP BY user_id
      ) t
      GROUP BY claim_count ORDER BY claim_count
    `),
    // 30-day retention: users who made ≥2 claims with ≥30d gap
    db.query(`
      SELECT
        COUNT(DISTINCT user_id) FILTER (
          WHERE max_date - min_date >= INTERVAL '30 days'
        ) AS retained,
        COUNT(DISTINCT user_id) AS total
      FROM (
        SELECT user_id,
               MIN(submitted_at) AS min_date,
               MAX(submitted_at) AS max_date
        FROM claims WHERE status = 'approved'
        GROUP BY user_id HAVING COUNT(*) >= 2
      ) t
    `),
  ]);

  const ret = retention.rows[0];
  const retRate = ret.total > 0
    ? Math.round(parseInt(ret.retained) / parseInt(ret.total) * 100)
    : 0;

  // LTV: average total cashback earned per retained user × estimated purchase lifetime (months)
  const { rows: ltv } = await db.query(`
    SELECT
      ROUND(AVG(total_cb)::numeric, 2) AS avg_ltv,
      ROUND(AVG(claim_cnt)::numeric, 2) AS avg_frequency,
      ROUND(AVG(avg_basket)::numeric, 2) AS avg_basket
    FROM (
      SELECT
        user_id,
        SUM(cashback_amount)  AS total_cb,
        COUNT(*)              AS claim_cnt,
        AVG(cashback_amount)  AS avg_basket
      FROM claims WHERE status = 'approved'
      GROUP BY user_id
    ) t
  `);

  res.json({
    segments: segments.rows.map(r => ({
      segment: r.segment,
      users:   parseInt(r.users),
    })),
    frequency: frequency.rows.map(r => ({
      claims: parseInt(r.claim_count),
      users:  parseInt(r.users),
    })),
    retention: {
      rate:     retRate,
      retained: parseInt(ret.retained),
      total:    parseInt(ret.total),
    },
    ltv: {
      avg_ltv:       parseFloat(ltv.rows[0]?.avg_ltv || 0),
      avg_frequency: parseFloat(ltv.rows[0]?.avg_frequency || 0),
      avg_basket:    parseFloat(ltv.rows[0]?.avg_basket || 0),
    },
  });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/heatmap — claims by day-of-week (0=Sun) × hour
// ═════════════════════════════════════════════════════════════════════════════
router.get('/heatmap', async (req, res) => {
  const { from, to } = req.query;
  const df = dateFilter('submitted_at', from, to);

  const { rows } = await db.query(`
    SELECT
      EXTRACT(DOW  FROM submitted_at AT TIME ZONE 'Asia/Beirut')::int AS dow,
      EXTRACT(HOUR FROM submitted_at AT TIME ZONE 'Asia/Beirut')::int AS hour,
      COUNT(*) AS claims
    FROM claims
    WHERE status = 'approved' ${df}
    GROUP BY dow, hour
    ORDER BY dow, hour
  `);

  // Build full 7×24 matrix (fill zeroes)
  const matrix = Array.from({ length: 7 }, (_, d) =>
    Array.from({ length: 24 }, (_, h) => {
      const found = rows.find(r => r.dow === d && r.hour === h);
      return { dow: d, hour: h, claims: found ? parseInt(found.claims) : 0 };
    })
  );

  const days  = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const max   = Math.max(...rows.map(r => parseInt(r.claims)), 1);

  res.json({ matrix: matrix.flat(), days, max });
});

// ═════════════════════════════════════════════════════════════════════════════
// GET /analytics/insights — rule-based AI insights engine
// ═════════════════════════════════════════════════════════════════════════════
router.get('/insights', async (req, res) => {
  const insights = [];

  // ── Pull raw metrics for analysis ─────────────────────────────────────────
  const [campaignData, categoryData, retentionData, growthData, flaggedData] =
    await Promise.all([
      // Campaign performance
      db.query(`
        SELECT camp.name, camp.cashback_value,
          COUNT(c.id) AS claims,
          COUNT(c.id) FILTER (WHERE c.status='approved') AS approved,
          COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS paid,
          ROUND(COUNT(c.id) FILTER (WHERE c.status='approved')::numeric / NULLIF(COUNT(c.id),0)*100,1) AS conv_rate
        FROM campaigns camp
        JOIN products p ON p.id = camp.product_id
        LEFT JOIN claims c ON c.product_id = p.id AND c.submitted_at >= NOW() - INTERVAL '30 days'
        WHERE camp.is_active = TRUE
        GROUP BY camp.id, camp.name, camp.cashback_value
        ORDER BY conv_rate ASC NULLS LAST
      `),
      // Weekend vs weekday purchase split
      db.query(`
        SELECT
          SUM(CASE WHEN EXTRACT(DOW FROM submitted_at) IN (0,6) THEN 1 ELSE 0 END) AS weekend,
          SUM(CASE WHEN EXTRACT(DOW FROM submitted_at) NOT IN (0,6) THEN 1 ELSE 0 END) AS weekday,
          p.category
        FROM claims c JOIN products p ON p.id = c.product_id
        WHERE c.status = 'approved' AND c.submitted_at >= NOW() - INTERVAL '30 days'
        GROUP BY p.category ORDER BY weekend DESC LIMIT 3
      `),
      // Retention
      db.query(`
        SELECT COUNT(DISTINCT user_id) FILTER (WHERE claim_count >= 2) AS returning,
               COUNT(DISTINCT user_id) AS total
        FROM (SELECT user_id, COUNT(*) AS claim_count FROM claims
              WHERE status='approved' GROUP BY user_id) t
      `),
      // Week-over-week claim growth
      db.query(`
        SELECT
          COUNT(*) FILTER (WHERE submitted_at >= NOW() - INTERVAL '7 days')  AS this_week,
          COUNT(*) FILTER (WHERE submitted_at BETWEEN NOW()-INTERVAL '14 days' AND NOW()-INTERVAL '7 days') AS last_week
        FROM claims WHERE status = 'approved'
      `),
      // Fraud flagged rate
      db.query(`
        SELECT
          COUNT(*) FILTER (WHERE status='flagged') AS flagged,
          COUNT(*) AS total
        FROM claims WHERE submitted_at >= NOW() - INTERVAL '30 days'
      `),
    ]);

  // ── Rule 1: Low-conversion campaigns ──────────────────────────────────────
  const lowConv = campaignData.rows.filter(c => parseFloat(c.conv_rate) < 30 && parseInt(c.claims) > 5);
  if (lowConv.length > 0) {
    insights.push({
      type:     'warning',
      icon:     'trending_down',
      title:    `${lowConv.length} campaign${lowConv.length > 1 ? 's' : ''} have low conversion`,
      detail:   `"${lowConv[0].name}" has only ${lowConv[0].conv_rate}% approval rate. Consider raising cashback % or checking product eligibility.`,
      action:   'Review Campaign',
      priority: 'high',
    });
  }

  // ── Rule 2: Weekend purchase pattern ──────────────────────────────────────
  for (const row of categoryData.rows) {
    const weekend = parseInt(row.weekend);
    const weekday = parseInt(row.weekday);
    if (weekend > weekday * 0.7 && weekend > 5) {
      insights.push({
        type:     'info',
        icon:     'event',
        title:    `${row.category} peaks on weekends`,
        detail:   `${weekend} weekend vs ${weekday} weekday claims. Scheduling campaigns Friday–Sunday could boost ${row.category} conversions.`,
        action:   'Schedule Campaign',
        priority: 'medium',
      });
      break;
    }
  }

  // ── Rule 3: Retention warning ──────────────────────────────────────────────
  const retRow = retentionData.rows[0];
  const retRate = retRow.total > 0
    ? Math.round(parseInt(retRow.returning) / parseInt(retRow.total) * 100) : 0;
  if (retRate < 40 && parseInt(retRow.total) > 10) {
    insights.push({
      type:     'warning',
      icon:     'person_off',
      title:    `Retention is ${retRate}% — below target`,
      detail:   'Less than 40% of users make a second claim. Consider push notifications, loyalty rewards, or new campaign launches to re-engage them.',
      action:   'Launch Re-engagement',
      priority: 'high',
    });
  }

  // ── Rule 4: Growth momentum ────────────────────────────────────────────────
  const gRow = growthData.rows[0];
  const thisWeek = parseInt(gRow.this_week);
  const lastWeek = parseInt(gRow.last_week);
  if (lastWeek > 0) {
    const growth = Math.round((thisWeek - lastWeek) / lastWeek * 100);
    if (growth > 20) {
      insights.push({
        type:     'success',
        icon:     'rocket_launch',
        title:    `Claims up ${growth}% week-over-week`,
        detail:   `This week: ${thisWeek} approved claims vs ${lastWeek} last week. Growth is accelerating — good time to pitch brands on new campaigns.`,
        action:   'Export Report',
        priority: 'low',
      });
    } else if (growth < -20) {
      insights.push({
        type:     'danger',
        icon:     'trending_down',
        title:    `Claims dropped ${Math.abs(growth)}% this week`,
        detail:   `Only ${thisWeek} claims vs ${lastWeek} last week. Check if any campaigns expired or if there's a UX issue.`,
        action:   'Investigate',
        priority: 'high',
      });
    }
  }

  // ── Rule 5: High fraud flag rate ──────────────────────────────────────────
  const fRow = flaggedData.rows[0];
  const flagRate = fRow.total > 0
    ? Math.round(parseInt(fRow.flagged) / parseInt(fRow.total) * 100) : 0;
  if (flagRate > 10 && parseInt(fRow.flagged) > 3) {
    insights.push({
      type:     'danger',
      icon:     'security',
      title:    `${flagRate}% of claims flagged for review`,
      detail:   `${fRow.flagged} claims flagged in the last 30 days. High flag rate may indicate receipt fraud or a product eligibility issue. Review fraud rules.`,
      action:   'Review Flags',
      priority: 'high',
    });
  }

  // ── Rule 6: Top campaign recommendation ───────────────────────────────────
  const topCamp = campaignData.rows
    .filter(c => parseFloat(c.conv_rate) > 60)
    .sort((a, b) => parseInt(b.approved) - parseInt(a.approved))[0];
  if (topCamp) {
    insights.push({
      type:     'success',
      icon:     'star',
      title:    `"${topCamp.name}" is your best campaign`,
      detail:   `${topCamp.conv_rate}% conversion rate with ${topCamp.approved} approved claims. Replicate its cashback structure for other underperforming campaigns.`,
      action:   'Duplicate Campaign',
      priority: 'low',
    });
  }

  // Sort by priority
  const order = { high: 0, medium: 1, low: 2 };
  insights.sort((a, b) => order[a.priority] - order[b.priority]);

  res.json({ insights, generated_at: new Date().toISOString() });
});

module.exports = router;
