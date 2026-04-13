const express  = require('express');
const path     = require('path');
const helmet   = require('helmet');
const cors     = require('cors');
const { v4: uuidv4 } = require('uuid');

const { requestLogger }          = require('./middleware/requestLogger');
const { apiRateLimit }           = require('./middleware/rateLimit');
const logger                     = require('./config/logger');

// User routes
const authRouter                 = require('./routes/auth');
const productsRouter             = require('./routes/products');
const { router: receiptsRouter } = require('./routes/receipts');
const claimsRouter               = require('./routes/claims');
const walletRouter               = require('./routes/wallet');
const notificationsRouter        = require('./routes/notifications');

// Admin routes
const adminAuthRouter            = require('./routes/admin/auth');
const adminAnalyticsRouter       = require('./routes/admin/analytics');
const adminCampaignsRouter       = require('./routes/admin/campaigns');
const adminClaimsRouter          = require('./routes/admin/claims');
const adminProductsRouter        = require('./routes/admin/products');

const app = express();

// ── Security headers ──────────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc:  ["'self'", "'unsafe-inline'", "'unsafe-eval'", 'https://cdn.tailwindcss.com', 'https://unpkg.com'],
      scriptSrcElem: ["'self'", "'unsafe-inline'", "'unsafe-eval'", 'https://cdn.tailwindcss.com', 'https://unpkg.com'],
      styleSrc:   ["'self'", "'unsafe-inline'", 'https://cdn.tailwindcss.com'],
      imgSrc:     ["'self'", 'data:', 'blob:'],
      connectSrc: ["'self'"],
      fontSrc:    ["'self'", 'data:'],
    },
  },
}));

// ── CORS ──────────────────────────────────────────────────────────────────────
const allowedOrigins = (process.env.CORS_ORIGINS || '').split(',').filter(Boolean);
app.use(cors({
  origin: allowedOrigins.length > 0 ? allowedOrigins : false,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Request ID — trace any request through the logs ──────────────────────────
app.use((req, _res, next) => {
  req.id = req.headers['x-request-id'] || uuidv4();
  next();
});

// ── Body parsing ──────────────────────────────────────────────────────────────
app.use(express.json({ limit: '1mb' }));

// ── Serve admin dashboard static files ───────────────────────────────────────
app.use('/admin', express.static(path.join(__dirname, 'public/admin')));

// ── Request logging ───────────────────────────────────────────────────────────
app.use(requestLogger);

// ── Global rate limit ─────────────────────────────────────────────────────────
app.use(apiRateLimit);

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', ts: new Date().toISOString() }));

// ── User API routes ───────────────────────────────────────────────────────────
app.use('/auth',          authRouter);
app.use('/products',      productsRouter);
app.use('/receipts',      receiptsRouter);
app.use('/claims',        claimsRouter);
app.use('/wallet',        walletRouter);
app.use('/notifications', notificationsRouter);

// ── Admin API routes (/admin/...) ─────────────────────────────────────────────
app.use('/admin/auth',      adminAuthRouter);
app.use('/admin/analytics', adminAnalyticsRouter);
app.use('/admin/campaigns', adminCampaignsRouter);
app.use('/admin/claims',    adminClaimsRouter);
app.use('/admin/products',  adminProductsRouter);

// ── 404 ───────────────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// ── Global error handler ──────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  logger.error('unhandled_error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

module.exports = app;
