const express  = require('express');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const db       = require('../config/db');
const logger   = require('../config/logger');
const { validate }                           = require('../middleware/validate');
const { requireAuth }                        = require('../middleware/auth');
const { createOtp, verifyOtp, sendEmail, validatePassword } = require('../services/otp');

const router = express.Router();

// ── POST /auth/register ───────────────────────────────────────────────────────
// Step 1: email + password only.
// Creates an unverified account, sends OTP to email, returns JWT.
// Profile (name + phone) collected after email is verified.
router.post(
  '/register',
  validate([
    { field: 'email',    required: true, type: 'email' },
    { field: 'password', required: true, minLength: 8  },
  ]),
  async (req, res) => {
    const { email, password, device } = req.body;

    // ── Strict password validation ─────────────────────────────────────────
    const pwErrors = validatePassword(password);
    if (pwErrors.length > 0) {
      return res.status(400).json({
        error: `Password must contain: ${pwErrors.join(', ')}`,
        code:  'WEAK_PASSWORD',
        rules: pwErrors,
      });
    }

    // ── Duplicate email check ──────────────────────────────────────────────
    const { rows: [dup] } = await db.query(
      `SELECT id FROM users WHERE email = $1`, [email.toLowerCase()]
    );
    if (dup) return res.status(409).json({ error: 'Email already registered', code: 'EMAIL_TAKEN' });

    // ── Device: one account per device ────────────────────────────────────
    if (device?.device_id && process.env.ONE_ACCOUNT_PER_DEVICE !== 'false') {
      const { rows: [dupDevice] } = await db.query(
        `SELECT user_id FROM device_sessions WHERE device_id = $1`, [device.device_id]
      );
      if (dupDevice) {
        return res.status(409).json({ error: 'An account already exists on this device', code: 'DEVICE_TAKEN' });
      }
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Create user (name + phone collected later)
      const { rows: [user] } = await client.query(
        `INSERT INTO users (email, password_hash)
         VALUES ($1, $2)
         RETURNING id, email`,
        [email.toLowerCase(), passwordHash]
      );

      await client.query(`INSERT INTO wallets (user_id) VALUES ($1)`, [user.id]);

      if (device?.device_id) {
        await client.query(
          `INSERT INTO device_sessions (user_id, device_id, platform, os_version, app_version, ip_address)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (device_id) DO UPDATE
             SET user_id = EXCLUDED.user_id, last_seen_at = NOW()`,
          [user.id, device.device_id, device.platform, device.os_version, device.app_version, req.ip]
        );
      }

      // Mark user as verified immediately (no OTP required)
      await client.query(
        `UPDATE users SET phone_verified = TRUE WHERE id = $1`, [user.id]
      );
      await client.query('COMMIT');

      logger.info('user_registered', { userId: user.id, email });

      const tokens = issueTokens(user);
      return res.status(201).json({
        user:                 { id: user.id, email: user.email },
        phone_verified:       true,
        onboarding_completed: false,
        ...tokens,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      logger.error('register_error', { error: err.message });
      return res.status(500).json({ error: 'Registration failed' });
    } finally {
      client.release();
    }
  }
);

// ── POST /auth/verify-email ───────────────────────────────────────────────────
// Step 2: verify the 6-digit OTP sent to email.
// Brute-force protected (5 attempts max, then OTP locked).
router.post('/verify-email', requireAuth, async (req, res) => {
  const { otp } = req.body;
  if (!otp) return res.status(400).json({ error: 'OTP is required' });

  const client = await db.connect();
  try {
    const result = await verifyOtp(client, req.user.id, otp);
    switch (result) {
      case 'ok':
        return res.json({ email_verified: true, phone_verified: true });
      case 'expired':
        return res.status(400).json({ error: 'Verification code has expired. Request a new one.', code: 'OTP_EXPIRED' });
      case 'locked':
        return res.status(429).json({ error: 'Too many incorrect attempts. Request a new code.', code: 'OTP_LOCKED' });
      default:
        return res.status(400).json({ error: 'Incorrect code. Please try again.', code: 'OTP_INVALID' });
    }
  } finally {
    client.release();
  }
});

// ── POST /auth/resend-otp ─────────────────────────────────────────────────────
// Rate-limited by the global API limiter. Resends OTP to the user's email.
router.post('/resend-otp', requireAuth, async (req, res) => {
  const { rows: [user] } = await db.query(
    `SELECT email, phone_verified FROM users WHERE id = $1`, [req.user.id]
  );
  if (!user)             return res.status(404).json({ error: 'User not found' });
  if (user.phone_verified) return res.status(400).json({ error: 'Email already verified' });

  const client = await db.connect();
  try {
    const otp         = await createOtp(client, req.user.id);
    const emailResult = await sendEmail(user.email, otp);
    return res.json({
      message: 'Verification code resent',
      ...(emailResult.devOtp ? { _dev_otp: emailResult.devOtp } : {}),
    });
  } finally {
    client.release();
  }
});

// ── PATCH /auth/profile ───────────────────────────────────────────────────────
// Step 3: save full name and phone number (requires email verified).
router.patch('/profile', requireAuth, async (req, res) => {
  const { rows: [user] } = await db.query(
    `SELECT phone_verified FROM users WHERE id = $1`, [req.user.id]
  );
  if (!user)               return res.status(404).json({ error: 'User not found' });
  if (!user.phone_verified) return res.status(403).json({ error: 'Email not verified', code: 'EMAIL_NOT_VERIFIED' });

  const { full_name, phone } = req.body;
  if (!full_name || full_name.trim().length < 2)
    return res.status(400).json({ error: 'Full name is required' });
  if (!phone || phone.trim().length < 7)
    return res.status(400).json({ error: 'Valid phone number is required' });

  // Phone uniqueness check (excluding self)
  const { rows: [dupPhone] } = await db.query(
    `SELECT id FROM users WHERE phone = $1 AND id != $2`, [phone.trim(), req.user.id]
  );
  if (dupPhone) return res.status(409).json({ error: 'Phone number already registered', code: 'PHONE_TAKEN' });

  await db.query(
    `UPDATE users SET full_name = $1, phone = $2 WHERE id = $3`,
    [full_name.trim(), phone.trim(), req.user.id]
  );

  logger.info('profile_updated', { userId: req.user.id });
  return res.json({ success: true });
});

// ── PATCH /auth/onboarding ────────────────────────────────────────────────────
// Final step: city, age range, category preferences, country, date_of_birth.
router.patch('/onboarding', requireAuth, async (req, res) => {
  const { city, age_range, preferences, country, date_of_birth } = req.body;

  const validAgeRanges = ['under-18', '18-24', '25-34', '35-44', '45+'];
  if (age_range && !validAgeRanges.includes(age_range)) {
    return res.status(400).json({ error: 'Invalid age_range' });
  }

  // Validate date_of_birth format if provided
  let dob = null;
  if (date_of_birth) {
    const parsed = new Date(date_of_birth);
    if (isNaN(parsed.getTime())) {
      return res.status(400).json({ error: 'Invalid date_of_birth format. Use YYYY-MM-DD.' });
    }
    dob = date_of_birth;
  }

  const validCategories = ['snacks', 'beverages', 'dairy', 'cosmetics', 'personal_care', 'pantry', 'produce', 'household'];
  const cleanPrefs = Array.isArray(preferences)
    ? preferences.filter((p) => validCategories.includes(p))
    : [];

  await db.query(
    `UPDATE users
     SET city = $1, age_range = $2, preferences = $3, country = $4, date_of_birth = $5,
         onboarding_completed = TRUE
     WHERE id = $6`,
    [city?.trim() || null, age_range || null, cleanPrefs, country?.trim() || null, dob, req.user.id]
  );

  logger.info('onboarding_completed', { userId: req.user.id });
  return res.json({ onboarding_completed: true });
});

// ── POST /auth/login ──────────────────────────────────────────────────────────
router.post(
  '/login',
  validate([
    { field: 'email',    required: true },
    { field: 'password', required: true },
  ]),
  async (req, res) => {
    const { email, password, device } = req.body;

    const { rows: [user] } = await db.query(
      `SELECT id, email, full_name, password_hash, is_active, phone_verified, onboarding_completed
       FROM users WHERE email = $1`,
      [email.toLowerCase()]
    );

    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }
    if (!user.is_active) {
      return res.status(403).json({ error: 'Account disabled' });
    }

    if (device?.device_id) {
      await db.query(
        `INSERT INTO device_sessions (user_id, device_id, platform, os_version, app_version, ip_address)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (device_id) DO UPDATE
           SET last_seen_at = NOW(), ip_address = EXCLUDED.ip_address`,
        [user.id, device.device_id, device.platform, device.os_version, device.app_version, req.ip]
      );
    }

    const tokens = issueTokens(user);
    return res.json({
      user:                 { id: user.id, email: user.email, full_name: user.full_name },
      phone_verified:       user.phone_verified,
      onboarding_completed: user.onboarding_completed,
      ...tokens,
    });
  }
);

// ── POST /auth/refresh ────────────────────────────────────────────────────────
router.post('/refresh', async (req, res) => {
  const { refresh_token } = req.body;
  if (!refresh_token) return res.status(400).json({ error: 'refresh_token required' });

  try {
    const payload = jwt.verify(refresh_token, process.env.JWT_SECRET);
    if (payload.type !== 'refresh') return res.status(401).json({ error: 'Invalid token type' });

    const { rows: [user] } = await db.query(
      `SELECT id, email, full_name, is_active, phone_verified, onboarding_completed
       FROM users WHERE id = $1`,
      [payload.sub]
    );
    if (!user || !user.is_active) return res.status(401).json({ error: 'User not found or disabled' });

    return res.json(issueTokens(user));
  } catch {
    return res.status(401).json({ error: 'Invalid or expired refresh token' });
  }
});

// ── GET /auth/me ──────────────────────────────────────────────────────────────
router.get('/me', requireAuth, async (req, res) => {
  try {
    const { rows: [user] } = await db.query(
      `SELECT id, email, full_name, phone, phone_verified, city, age_range,
              preferences, country, date_of_birth, onboarding_completed, created_at
       FROM users WHERE id = $1 AND is_active = TRUE`,
      [req.user.id]
    );
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ user });
  } catch (err) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
function issueTokens(user) {
  const base = { sub: user.id, email: user.email };

  const access_token = jwt.sign(
    { ...base, type: 'access' },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '15m' }
  );

  const refresh_token = jwt.sign(
    { ...base, type: 'refresh' },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d' }
  );

  return { access_token, refresh_token };
}

module.exports = router;
