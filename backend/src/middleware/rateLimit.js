const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const logger                        = require('../config/logger');

/**
 * Build a rate limiter store.
 * Uses Redis (via rate-limit-redis + ioredis) when REDIS_URL is set,
 * falls back to in-memory so the server still starts without Redis.
 *
 * In-memory: fine for single-instance / dev.
 * Redis: required for multi-instance / load-balanced production.
 */
function buildStore(prefix) {
  if (!process.env.REDIS_URL) return undefined; // express-rate-limit default (in-memory)

  try {
    const { RedisStore } = require('rate-limit-redis');
    const Redis           = require('ioredis');
    const client = new Redis(process.env.REDIS_URL, { lazyConnect: true, maxRetriesPerRequest: 1 });
    client.on('error', (err) => logger.warn('redis_ratelimit_error', { error: err.message }));
    return new RedisStore({ sendCommand: (...args) => client.call(...args), prefix });
  } catch (err) {
    logger.warn('redis_ratelimit_unavailable', { error: err.message });
    return undefined;
  }
}

/**
 * Per-user rate limiter for claim submission.
 * Falls back to IP if user is not yet authenticated.
 */
const claimRateLimit = rateLimit({
  windowMs:        15 * 60 * 1000,  // 15 minutes
  max:             10,               // max 10 claims per window
  keyGenerator:    (req) => `claim:${req.user?.id ?? ipKeyGenerator(req)}`,
  store:           buildStore('rl:claim:'),
  standardHeaders: true,
  legacyHeaders:   false,
  handler: (req, res) => {
    logger.warn('rate_limit_hit', {
      userId: req.user?.id,
      ip:     req.ip,
      path:   req.path,
    });
    res.status(429).json({
      error: 'Too many claim submissions. Please wait before trying again.',
    });
  },
});

/**
 * General API rate limit — protects all routes.
 */
const apiRateLimit = rateLimit({
  windowMs:        1 * 60 * 1000,   // 1 minute
  max:             120,              // 2 req/sec sustained
  keyGenerator:    (req) => `api:${req.user?.id ?? ipKeyGenerator(req)}`,
  store:           buildStore('rl:api:'),
  standardHeaders: true,
  legacyHeaders:   false,
  handler: (_req, res) => {
    res.status(429).json({ error: 'Too many requests. Slow down.' });
  },
});

module.exports = { claimRateLimit, apiRateLimit };
