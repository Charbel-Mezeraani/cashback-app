const jwt = require('jsonwebtoken');

function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or malformed Authorization header' });
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);

    // Reject admin tokens on user endpoints — they carry type: 'admin'
    if (payload.type === 'admin') {
      return res.status(403).json({ error: 'Admin tokens cannot be used on user endpoints' });
    }

    req.user = { id: payload.sub, email: payload.email };
    next();
  } catch (err) {
    const message = err.name === 'TokenExpiredError' ? 'Token expired' : 'Invalid token';
    return res.status(401).json({ error: message });
  }
}

module.exports = { requireAuth };
