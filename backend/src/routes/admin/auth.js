const express = require('express');
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const db      = require('../../config/db');
const logger  = require('../../config/logger');

const router = express.Router();

// POST /admin/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  const { rows: [admin] } = await db.query(
    `SELECT id, email, password_hash, name, role, is_active
     FROM admin_users WHERE email = $1`,
    [email.toLowerCase()]
  );

  if (!admin || !(await bcrypt.compare(password, admin.password_hash))) {
    logger.warn('admin_login_failed', { email, ip: req.ip });
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  if (!admin.is_active) {
    return res.status(403).json({ error: 'Account disabled' });
  }

  const token = jwt.sign(
    { sub: admin.id, email: admin.email, role: admin.role, type: 'admin' },
    process.env.JWT_SECRET,
    { expiresIn: '8h' }
  );

  logger.info('admin_login', { adminId: admin.id, email: admin.email });
  res.json({ token, admin: { id: admin.id, email: admin.email, name: admin.name, role: admin.role } });
});

module.exports = router;
