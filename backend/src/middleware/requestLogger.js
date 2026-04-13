const logger = require('../config/logger');

/**
 * Logs every HTTP request with method, path, status, and response time.
 * Skips /health to avoid log noise.
 */
function requestLogger(req, res, next) {
  if (req.path === '/health') return next();

  const start = Date.now();

  res.on('finish', () => {
    const ms = Date.now() - start;
    const level = res.statusCode >= 500 ? 'error'
                : res.statusCode >= 400 ? 'warn'
                : 'info';

    logger[level]('http', {
      method:  req.method,
      path:    req.path,
      status:  res.statusCode,
      ms,
      userId:  req.user?.id ?? null,
      ip:      req.ip,
    });
  });

  next();
}

module.exports = { requestLogger };
