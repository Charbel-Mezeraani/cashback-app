/**
 * Minimal schema validator — avoids adding a heavy library for MVP.
 * Each rule is { field, type?, required?, minLength?, isUUID? }.
 *
 * Usage:
 *   router.post('/', validate([{ field: 'email', required: true }]), handler)
 */
function validate(rules) {
  return (req, res, next) => {
    const errors = [];
    const body   = req.body;

    for (const rule of rules) {
      const val = body[rule.field];
      const missing = val === undefined || val === null || val === '';

      if (rule.required && missing) {
        errors.push(`${rule.field} is required`);
        continue;
      }
      if (missing) continue;

      if (rule.type === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val)) {
        errors.push(`${rule.field} must be a valid email`);
      }
      if (rule.minLength && String(val).length < rule.minLength) {
        errors.push(`${rule.field} must be at least ${rule.minLength} characters`);
      }
      if (rule.isUUID && !/^[0-9a-f-]{36}$/.test(val)) {
        errors.push(`${rule.field} must be a valid UUID`);
      }
    }

    if (errors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: errors });
    }
    next();
  };
}

module.exports = { validate };
