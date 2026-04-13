const jwt    = require('jsonwebtoken');
const logger = require('../config/logger');

/**
 * Verify admin JWT (issued by POST /admin/auth/login).
 * Attaches req.admin = { id, email, role } on success.
 */
function requireAdmin(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Admin authentication required' });
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (payload.type !== 'admin') {
      return res.status(403).json({ error: 'Not an admin token' });
    }
    req.admin = { id: payload.sub, email: payload.email, role: payload.role };
    next();
  } catch (err) {
    const message = err.name === 'TokenExpiredError' ? 'Token expired' : 'Invalid token';
    logger.warn('admin_auth_failed', { error: message, ip: req.ip });
    return res.status(401).json({ error: message });
  }
}

/**
 * Restrict an endpoint to super-admins only.
 * Must be placed after requireAdmin.
 */
function requireSuper(req, res, next) {
  if (req.admin?.role !== 'super') {
    return res.status(403).json({ error: 'Super-admin access required' });
  }
  next();
}

module.exports = { requireAdmin, requireSuper };
