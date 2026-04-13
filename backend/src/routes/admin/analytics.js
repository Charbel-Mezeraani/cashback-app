const express            = require('express');
const db                 = require('../../config/db');
const { requireAdmin }   = require('../../middleware/adminAuth');

const router = express.Router();

// GET /admin/analytics — dashboard summary
router.get('/', requireAdmin, async (req, res) => {
  const [
    claimStats,
    walletStats,
    campaignStats,
    dailyTrend,
    topProducts,
    fraudStats,
  ] = await Promise.all([

    // Claim counts by status
    db.query(`
      SELECT
        COUNT(*)                                        AS total_claims,
        COUNT(*) FILTER (WHERE status = 'approved')    AS approved,
        COUNT(*) FILTER (WHERE status = 'rejected')    AS rejected,
        COUNT(*) FILTER (WHERE status = 'flagged')     AS flagged,
        COUNT(*) FILTER (WHERE status = 'pending')     AS pending,
        COUNT(*) FILTER (WHERE submitted_at > NOW() - INTERVAL '24 hours') AS last_24h,
        COUNT(*) FILTER (WHERE submitted_at > NOW() - INTERVAL '7 days')   AS last_7d
      FROM claims
    `),

    // Total cashback paid out + avg per claim
    db.query(`
      SELECT
        COALESCE(SUM(amount),  0)    AS total_cashback_paid,
        COALESCE(AVG(amount),  0)    AS avg_cashback,
        COUNT(*)                     AS total_transactions
      FROM wallet_transactions
      WHERE type = 'cashback'
    `),

    // Active campaigns summary
    db.query(`
      SELECT
        COUNT(*)                              AS total_campaigns,
        COUNT(*) FILTER (WHERE active = TRUE
          AND starts_at <= NOW()
          AND ends_at   >= NOW())             AS active_campaigns,
        SUM(claim_count)                      AS total_campaign_claims,
        SUM(cashback_value * claim_count)
          FILTER (WHERE cashback_type = 'fixed') AS estimated_cost
      FROM campaigns
    `),

    // Daily claim trend — last 14 days
    db.query(`
      SELECT
        DATE(submitted_at)               AS day,
        COUNT(*)                         AS claims,
        COUNT(*) FILTER (WHERE status = 'approved') AS approved,
        COALESCE(SUM(cashback_amount) FILTER (WHERE status = 'approved'), 0) AS cashback
      FROM claims
      WHERE submitted_at > NOW() - INTERVAL '14 days'
      GROUP BY DATE(submitted_at)
      ORDER BY day ASC
    `),

    // Top 5 products by approved claims
    db.query(`
      SELECT
        p.name, p.barcode, p.brand,
        COUNT(c.id)                     AS claim_count,
        SUM(c.cashback_amount)          AS total_cashback,
        ROUND(AVG(c.cashback_amount),2) AS avg_cashback
      FROM claims c
      JOIN products p ON p.id = c.product_id
      WHERE c.status = 'approved'
      GROUP BY p.id, p.name, p.barcode, p.brand
      ORDER BY claim_count DESC
      LIMIT 5
    `),

    // Fraud summary
    db.query(`
      SELECT
        COUNT(DISTINCT claim_id)          AS flagged_claims,
        flag_type,
        COUNT(*)                          AS occurrences
      FROM fraud_flags
      GROUP BY flag_type
      ORDER BY occurrences DESC
    `),
  ]);

  const claims   = claimStats.rows[0];
  const wallet   = walletStats.rows[0];
  const campaigns = campaignStats.rows[0];

  // Cost per acquisition = total cashback / approved claims
  const cpa = claims.approved > 0
    ? (parseFloat(wallet.total_cashback_paid) / parseInt(claims.approved)).toFixed(2)
    : '0.00';

  res.json({
    summary: {
      total_claims:         parseInt(claims.total_claims),
      approved:             parseInt(claims.approved),
      rejected:             parseInt(claims.rejected),
      flagged:              parseInt(claims.flagged),
      pending:              parseInt(claims.pending),
      last_24h:             parseInt(claims.last_24h),
      last_7d:              parseInt(claims.last_7d),
      total_cashback_paid:  parseFloat(wallet.total_cashback_paid).toFixed(2),
      avg_cashback:         parseFloat(wallet.avg_cashback).toFixed(2),
      active_campaigns:     parseInt(campaigns.active_campaigns),
      cost_per_acquisition: cpa,
    },
    daily_trend:  dailyTrend.rows,
    top_products: topProducts.rows,
    fraud_flags:  fraudStats.rows,
  });
});

// GET /admin/analytics/users — user-level breakdown
router.get('/users', requireAdmin, async (req, res) => {
  const { rows } = await db.query(`
    SELECT
      u.id, u.email, u.created_at,
      COUNT(c.id)                                       AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'approved')  AS approved_claims,
      COUNT(c.id) FILTER (WHERE c.status = 'rejected')  AS rejected_claims,
      COALESCE(SUM(c.cashback_amount)
        FILTER (WHERE c.status = 'approved'), 0)        AS total_earned,
      MAX(c.fraud_score)                                AS max_fraud_score,
      w.balance
    FROM users u
    LEFT JOIN claims c  ON c.user_id  = u.id
    LEFT JOIN wallets w ON w.user_id  = u.id
    GROUP BY u.id, u.email, u.created_at, w.balance
    ORDER BY total_claims DESC
    LIMIT 100
  `);

  res.json({ users: rows });
});

// ════════════════════════════════════════════════════════════════════════════
// GET /admin/analytics/overview  — rich KPI overview with date filters
// ════════════════════════════════════════════════════════════════════════════
router.get('/overview', requireAdmin, async (req, res) => {
  const { from, to } = req.query;
  const fromClause = from ? `AND c.submitted_at >= '${from}'::date` : '';
  const toClause   = to   ? `AND c.submitted_at <= '${to}'::date`   : '';

  const [users, claims, cashback, active] = await Promise.all([
    db.query(`SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE created_at >= NOW()-INTERVAL '30 days') AS new_30d, COUNT(*) FILTER (WHERE created_at >= NOW()-INTERVAL '7 days') AS new_7d FROM users WHERE is_active=TRUE`),
    db.query(`SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE status='approved') AS approved, COUNT(*) FILTER (WHERE status='pending') AS pending, COUNT(*) FILTER (WHERE status='flagged') AS flagged, COUNT(*) FILTER (WHERE status='rejected') AS rejected FROM claims c WHERE 1=1 ${fromClause} ${toClause}`),
    db.query(`SELECT COALESCE(SUM(cashback_amount) FILTER (WHERE status='approved'),0) AS total_paid, COALESCE(AVG(cashback_amount) FILTER (WHERE status='approved'),0) AS avg_per_claim FROM claims c WHERE 1=1 ${fromClause} ${toClause}`),
    db.query(`SELECT COUNT(DISTINCT user_id) FILTER (WHERE submitted_at>=NOW()-INTERVAL '1 day') AS dau, COUNT(DISTINCT user_id) FILTER (WHERE submitted_at>=NOW()-INTERVAL '7 days') AS wau, COUNT(DISTINCT user_id) FILTER (WHERE submitted_at>=NOW()-INTERVAL '30 days') AS mau FROM claims`),
  ]);

  const paid = parseFloat(cashback.rows[0].total_paid);
  res.json({
    users: { total: +users.rows[0].total, new_30d: +users.rows[0].new_30d, new_7d: +users.rows[0].new_7d },
    active: { dau: +active.rows[0].dau, wau: +active.rows[0].wau, mau: +active.rows[0].mau },
    claims: { total: +claims.rows[0].total, approved: +claims.rows[0].approved, pending: +claims.rows[0].pending, flagged: +claims.rows[0].flagged, rejected: +claims.rows[0].rejected },
    cashback: { total_paid: paid, avg_per_claim: parseFloat(cashback.rows[0].avg_per_claim), platform_revenue: +(paid * 0.15).toFixed(2) },
  });
});

// GET /admin/analytics/growth?period=daily|weekly|monthly&from=&to=
router.get('/growth', requireAdmin, async (req, res) => {
  const { period = 'daily', from, to } = req.query;
  const trunc = period === 'weekly' ? 'week' : period === 'monthly' ? 'month' : 'day';
  const start = from || 'NOW() - INTERVAL \'90 days\'';
  const end   = to   || 'NOW()';

  const { rows } = await db.query(`
    WITH series AS (
      SELECT generate_series('${from || ''}' ::date, '${to || ''}'::date, '1 ${trunc}'::interval) AS period
    ),
    uc AS (SELECT date_trunc('${trunc}', created_at) p, COUNT(*) n FROM users GROUP BY 1),
    cc AS (SELECT date_trunc('${trunc}', submitted_at) p, COUNT(*) claims,
                  COALESCE(SUM(cashback_amount) FILTER (WHERE status='approved'),0) cashback
           FROM claims GROUP BY 1)
    SELECT TO_CHAR(s.period,'YYYY-MM-DD') AS date,
           COALESCE(u.n,0) AS new_users, COALESCE(c.claims,0) AS claims, COALESCE(c.cashback,0) AS cashback
    FROM generate_series(
      COALESCE('${from}'::date, NOW()-INTERVAL '90 days'),
      COALESCE('${to}'::date, NOW()),
      ('1 '||'${trunc}')::interval
    ) s(period)
    LEFT JOIN uc u ON u.p = s.period
    LEFT JOIN cc c ON c.p = s.period
    ORDER BY s.period
  `);
  res.json({ period, series: rows });
});

// GET /admin/analytics/top-products?limit=10&from=&to=&category=
router.get('/top-products', requireAdmin, async (req, res) => {
  const { limit = 10, from, to, category } = req.query;
  const where = [
    from      ? `AND c.submitted_at >= '${from}'::date` : '',
    to        ? `AND c.submitted_at <= '${to}'::date`   : '',
    category  ? `AND p.category = '${category}'`        : '',
  ].join(' ');

  const { rows } = await db.query(`
    SELECT p.id, p.name, p.brand, p.category, p.barcode,
      COUNT(c.id) AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status='approved') AS approved_claims,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS cashback_paid,
      ROUND(COUNT(c.id) FILTER (WHERE c.status='approved')::numeric / NULLIF(COUNT(c.id),0)*100,1) AS approval_rate
    FROM products p LEFT JOIN claims c ON c.product_id=p.id WHERE 1=1 ${where}
    GROUP BY p.id ORDER BY total_claims DESC LIMIT $1
  `, [+limit]);
  res.json({ products: rows });
});

// GET /admin/analytics/top-brands
router.get('/top-brands', requireAdmin, async (req, res) => {
  const { limit = 10, from, to } = req.query;
  const where = [from ? `AND c.submitted_at >= '${from}'::date` : '', to ? `AND c.submitted_at <= '${to}'::date` : ''].join(' ');
  const { rows } = await db.query(`
    SELECT p.brand, COUNT(DISTINCT p.id) AS product_count, COUNT(c.id) AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status='approved') AS approved_claims,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS cashback_paid,
      COUNT(DISTINCT c.user_id) AS unique_buyers,
      ROUND(AVG(c.cashback_amount) FILTER (WHERE c.status='approved')::numeric,2) AS avg_cashback
    FROM products p LEFT JOIN claims c ON c.product_id=p.id
    WHERE p.brand IS NOT NULL ${where}
    GROUP BY p.brand ORDER BY total_claims DESC LIMIT $1
  `, [+limit]);
  res.json({ brands: rows });
});

// GET /admin/analytics/categories
router.get('/categories', requireAdmin, async (req, res) => {
  const { from, to } = req.query;
  const where = [from ? `AND c.submitted_at >= '${from}'::date` : '', to ? `AND c.submitted_at <= '${to}'::date` : ''].join(' ');
  const { rows } = await db.query(`
    SELECT COALESCE(p.category,'Uncategorized') AS category,
      COUNT(c.id) AS claims, COUNT(DISTINCT c.user_id) AS unique_users,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS cashback_paid
    FROM claims c JOIN products p ON p.id=c.product_id WHERE 1=1 ${where}
    GROUP BY p.category ORDER BY claims DESC
  `);
  const total = rows.reduce((s,r) => s + +r.claims, 0);
  res.json({ categories: rows.map(r => ({ ...r, claims: +r.claims, unique_users: +r.unique_users, cashback_paid: +r.cashback_paid, percentage: total > 0 ? Math.round(+r.claims/total*100) : 0 })) });
});

// GET /admin/analytics/campaigns-performance
router.get('/campaigns-performance', requireAdmin, async (req, res) => {
  const { from, to } = req.query;
  const where = [from ? `AND c.submitted_at >= '${from}'::date` : '', to ? `AND c.submitted_at <= '${to}'::date` : ''].join(' ');
  const { rows } = await db.query(`
    SELECT camp.id, camp.name, camp.cashback_type, camp.cashback_value,
      camp.starts_at, camp.ends_at, camp.active,
      p.name AS product_name, p.brand, p.category,
      COUNT(c.id) AS total_claims,
      COUNT(c.id) FILTER (WHERE c.status='approved') AS approved_claims,
      COUNT(c.id) FILTER (WHERE c.status='rejected') AS rejected_claims,
      COUNT(DISTINCT c.user_id) AS unique_claimants,
      COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS total_cashback_paid,
      ROUND(COUNT(c.id) FILTER (WHERE c.status='approved')::numeric / NULLIF(COUNT(c.id),0)*100,1) AS conversion_rate,
      ROUND(COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) / NULLIF(COUNT(c.id) FILTER (WHERE c.status='approved'),0),2) AS cpa
    FROM campaigns camp JOIN products p ON p.id=camp.product_id
    LEFT JOIN claims c ON c.product_id=p.id ${where.replace(/AND/g,'WHERE').replace('WHERE','AND').length > 0 ? 'WHERE 1=1 '+where : ''}
    GROUP BY camp.id, p.name, p.brand, p.category ORDER BY total_claims DESC
  `);
  res.json({ campaigns: rows.map(r => ({ ...r, total_claims: +r.total_claims, approved_claims: +r.approved_claims, unique_claimants: +r.unique_claimants, total_cashback_paid: +r.total_cashback_paid, conversion_rate: +r.conversion_rate||0, cpa: +r.cpa||0 })) });
});

// GET /admin/analytics/heatmap
router.get('/heatmap', requireAdmin, async (req, res) => {
  const { from, to } = req.query;
  const where = [from ? `AND submitted_at >= '${from}'::date` : '', to ? `AND submitted_at <= '${to}'::date` : ''].join(' ');
  const { rows } = await db.query(`
    SELECT EXTRACT(DOW FROM submitted_at)::int AS dow, EXTRACT(HOUR FROM submitted_at)::int AS hour, COUNT(*) AS claims
    FROM claims WHERE status='approved' ${where} GROUP BY dow, hour ORDER BY dow, hour
  `);
  const matrix = Array.from({length:7},(_,d) => Array.from({length:24},(_,h) => {
    const f = rows.find(r => r.dow===d && r.hour===h);
    return { dow:d, hour:h, claims: f ? +f.claims : 0 };
  }));
  res.json({ matrix: matrix.flat(), days: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'], max: Math.max(...rows.map(r=>+r.claims),1) });
});

// GET /admin/analytics/user-segments
router.get('/user-segments', requireAdmin, async (req, res) => {
  const [segments, ltv, retention] = await Promise.all([
    db.query(`
      SELECT CASE WHEN total_cashback>=50 THEN 'High Value' WHEN total_cashback>=20 THEN 'Mid Value' WHEN total_cashback>0 THEN 'Low Value' ELSE 'No Claims' END AS segment, COUNT(*) AS users
      FROM (SELECT u.id, COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS total_cashback FROM users u LEFT JOIN claims c ON c.user_id=u.id WHERE u.is_active=TRUE GROUP BY u.id) t
      GROUP BY segment ORDER BY users DESC
    `),
    db.query(`SELECT ROUND(AVG(total_cb)::numeric,2) AS avg_ltv, ROUND(AVG(claim_cnt)::numeric,1) AS avg_frequency, ROUND(AVG(avg_basket)::numeric,2) AS avg_basket FROM (SELECT user_id, SUM(cashback_amount) AS total_cb, COUNT(*) AS claim_cnt, AVG(cashback_amount) AS avg_basket FROM claims WHERE status='approved' GROUP BY user_id) t`),
    db.query(`SELECT COUNT(DISTINCT user_id) FILTER (WHERE max_date-min_date>=INTERVAL '30 days') AS retained, COUNT(DISTINCT user_id) AS total FROM (SELECT user_id, MIN(submitted_at) AS min_date, MAX(submitted_at) AS max_date FROM claims WHERE status='approved' GROUP BY user_id HAVING COUNT(*)>=2) t`),
  ]);
  const ret = retention.rows[0];
  res.json({
    segments: segments.rows.map(r => ({ segment: r.segment, users: +r.users })),
    ltv: { avg_ltv: +ltv.rows[0]?.avg_ltv||0, avg_frequency: +ltv.rows[0]?.avg_frequency||0, avg_basket: +ltv.rows[0]?.avg_basket||0 },
    retention: { rate: ret.total>0 ? Math.round(+ret.retained/+ret.total*100):0, retained: +ret.retained, total: +ret.total },
  });
});

// GET /admin/analytics/insights — rule-based AI business insights
router.get('/insights', requireAdmin, async (req, res) => {
  const insights = [];
  const [campData, catData, retData, growthData, fraudData] = await Promise.all([
    db.query(`SELECT camp.name, COUNT(c.id) AS claims, COUNT(c.id) FILTER (WHERE c.status='approved') AS approved, COALESCE(SUM(c.cashback_amount) FILTER (WHERE c.status='approved'),0) AS paid, ROUND(COUNT(c.id) FILTER (WHERE c.status='approved')::numeric/NULLIF(COUNT(c.id),0)*100,1) AS conv_rate FROM campaigns camp JOIN products p ON p.id=camp.product_id LEFT JOIN claims c ON c.product_id=p.id AND c.submitted_at>=NOW()-INTERVAL '30 days' WHERE camp.active=TRUE GROUP BY camp.id,camp.name ORDER BY conv_rate ASC NULLS LAST`),
    db.query(`SELECT p.category, SUM(CASE WHEN EXTRACT(DOW FROM c.submitted_at) IN (0,6) THEN 1 ELSE 0 END) AS weekend, SUM(CASE WHEN EXTRACT(DOW FROM c.submitted_at) NOT IN (0,6) THEN 1 ELSE 0 END) AS weekday FROM claims c JOIN products p ON p.id=c.product_id WHERE c.status='approved' AND c.submitted_at>=NOW()-INTERVAL '30 days' GROUP BY p.category ORDER BY weekend DESC LIMIT 3`),
    db.query(`SELECT COUNT(DISTINCT user_id) FILTER (WHERE claim_count>=2) AS returning, COUNT(DISTINCT user_id) AS total FROM (SELECT user_id, COUNT(*) AS claim_count FROM claims WHERE status='approved' GROUP BY user_id) t`),
    db.query(`SELECT COUNT(*) FILTER (WHERE submitted_at>=NOW()-INTERVAL '7 days') AS this_week, COUNT(*) FILTER (WHERE submitted_at BETWEEN NOW()-INTERVAL '14 days' AND NOW()-INTERVAL '7 days') AS last_week FROM claims WHERE status='approved'`),
    db.query(`SELECT COUNT(*) FILTER (WHERE status='flagged') AS flagged, COUNT(*) AS total FROM claims WHERE submitted_at>=NOW()-INTERVAL '30 days'`),
  ]);

  const lowConv = campData.rows.filter(c => parseFloat(c.conv_rate) < 30 && parseInt(c.claims) > 5);
  if (lowConv.length) insights.push({ type:'warning', icon:'trending_down', title:`${lowConv.length} campaigns have low conversion`, detail:`"${lowConv[0].name}" has only ${lowConv[0].conv_rate}% approval rate. Consider raising cashback % or checking product eligibility.`, action:'Review Campaign', priority:'high' });

  for (const row of catData.rows) {
    if (+row.weekend > +row.weekday * 0.7 && +row.weekend > 5) {
      insights.push({ type:'info', icon:'event', title:`${row.category} peaks on weekends`, detail:`${row.weekend} weekend vs ${row.weekday} weekday claims. Schedule campaigns Friday–Sunday for ${row.category}.`, action:'Schedule Campaign', priority:'medium' });
      break;
    }
  }

  const ret = retData.rows[0];
  const retRate = ret.total > 0 ? Math.round(+ret.returning / +ret.total * 100) : 0;
  if (retRate < 40 && +ret.total > 10) insights.push({ type:'warning', icon:'person_off', title:`Retention is ${retRate}% — below target`, detail:'Less than 40% of users make a second claim. Launch re-engagement campaigns or add loyalty rewards.', action:'Launch Re-engagement', priority:'high' });

  const g = growthData.rows[0];
  if (+g.last_week > 0) {
    const growth = Math.round((+g.this_week - +g.last_week) / +g.last_week * 100);
    if (growth > 20) insights.push({ type:'success', icon:'rocket_launch', title:`Claims up ${growth}% week-over-week`, detail:`${g.this_week} claims this week vs ${g.last_week} last week. Good time to pitch new brand campaigns.`, action:'Export Report', priority:'low' });
    else if (growth < -20) insights.push({ type:'danger', icon:'trending_down', title:`Claims dropped ${Math.abs(growth)}% this week`, detail:`Only ${g.this_week} vs ${g.last_week} last week. Check for expired campaigns or UX issues.`, action:'Investigate', priority:'high' });
  }

  const f = fraudData.rows[0];
  const flagRate = f.total > 0 ? Math.round(+f.flagged / +f.total * 100) : 0;
  if (flagRate > 10 && +f.flagged > 3) insights.push({ type:'danger', icon:'security', title:`${flagRate}% of claims flagged for review`, detail:`${f.flagged} flagged claims in 30 days. Review fraud rules and receipt validation.`, action:'Review Flags', priority:'high' });

  const topCamp = campData.rows.filter(c => parseFloat(c.conv_rate) > 60).sort((a,b) => +b.approved - +a.approved)[0];
  if (topCamp) insights.push({ type:'success', icon:'star', title:`"${topCamp.name}" is your best campaign`, detail:`${topCamp.conv_rate}% conversion with ${topCamp.approved} approved claims. Replicate this structure.`, action:'Duplicate Campaign', priority:'low' });

  insights.sort((a,b) => ({high:0,medium:1,low:2}[a.priority] - {high:0,medium:1,low:2}[b.priority]));
  res.json({ insights, generated_at: new Date().toISOString() });
});

module.exports = router;
