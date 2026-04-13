/**
 * OTP service — generates, stores, and verifies 6-digit email OTPs.
 *
 * Storage  : bcrypt hash of OTP stored on users row (otp_hash, otp_expires_at).
 * Security : brute-force protection via otp_attempts column (max 5 tries).
 *
 * Delivery :
 *   Development  — OTP returned in API response body (_dev_otp), printed to logs.
 *   Production   — sent via SMTP using nodemailer (configure SMTP_* env vars).
 */

const bcrypt     = require('bcryptjs');
const nodemailer = require('nodemailer');
const logger     = require('../config/logger');

const OTP_TTL_MINUTES = parseInt(process.env.OTP_TTL_MINUTES || '10', 10);
const OTP_LENGTH      = 6;
const MAX_ATTEMPTS    = 5;

// ── OTP generation ────────────────────────────────────────────────────────────

function generateOtp() {
  // crypto.randomInt is available in Node 15+; fall back to Math.random for older.
  try {
    const { randomInt } = require('crypto');
    return String(randomInt(100_000, 999_999));
  } catch {
    const max = Math.pow(10, OTP_LENGTH);
    const min = Math.pow(10, OTP_LENGTH - 1);
    return String(Math.floor(min + Math.random() * (max - min)));
  }
}

// ── Password validation ───────────────────────────────────────────────────────

/**
 * Returns array of rule violations. Empty array = password is valid.
 */
function validatePassword(password) {
  if (typeof password !== 'string') return ['Password is required'];
  const errors = [];
  if (password.length < 8)         errors.push('at least 8 characters');
  if (!/[A-Z]/.test(password))     errors.push('at least 1 uppercase letter');
  if (!/[a-z]/.test(password))     errors.push('at least 1 lowercase letter');
  if (!/[0-9]/.test(password))     errors.push('at least 1 number');
  return errors;
}

// ── Create & store OTP ────────────────────────────────────────────────────────

/**
 * Generate a new OTP for userId, store its hash, reset attempt counter.
 * Returns the plain OTP string.
 */
async function createOtp(client, userId) {
  const otp     = generateOtp();
  const hash    = await bcrypt.hash(otp, 8);
  const expires = new Date(Date.now() + OTP_TTL_MINUTES * 60_000);

  await client.query(
    `UPDATE users
     SET otp_hash = $1, otp_expires_at = $2, otp_attempts = 0
     WHERE id = $3`,
    [hash, expires, userId]
  );

  return otp;
}

// ── Verify OTP ────────────────────────────────────────────────────────────────

/**
 * Verify submitted OTP.
 * Returns 'ok' | 'invalid' | 'expired' | 'locked'.
 * Clears OTP and marks phone_verified on success.
 */
async function verifyOtp(client, userId, submittedOtp) {
  const { rows: [user] } = await client.query(
    `SELECT otp_hash, otp_expires_at, otp_attempts FROM users WHERE id = $1`,
    [userId]
  );

  if (!user?.otp_hash)                           return 'invalid';
  if (user.otp_attempts >= MAX_ATTEMPTS)         return 'locked';
  if (new Date() > new Date(user.otp_expires_at)) return 'expired';

  // Increment attempt counter first (prevents race-condition brute force)
  await client.query(
    `UPDATE users SET otp_attempts = otp_attempts + 1 WHERE id = $1`,
    [userId]
  );

  const valid = await bcrypt.compare(submittedOtp, user.otp_hash);
  if (!valid) return 'invalid';

  // Success — clear OTP, mark verified
  await client.query(
    `UPDATE users
     SET otp_hash = NULL, otp_expires_at = NULL, otp_attempts = 0,
         phone_verified = TRUE
     WHERE id = $1`,
    [userId]
  );

  return 'ok';
}

// ── Email delivery ────────────────────────────────────────────────────────────

let _transporter = null;

function _getTransporter() {
  if (_transporter) return _transporter;

  if (process.env.NODE_ENV !== 'production') {
    // Ethereal (fake SMTP) — captured in nodemailer test account, never actually sent
    _transporter = nodemailer.createTransport({
      host: 'smtp.ethereal.email',
      port: 587,
      auth: {
        user: process.env.SMTP_USER || 'dev@example.com',
        pass: process.env.SMTP_PASS || 'devpass',
      },
    });
  } else {
    _transporter = nodemailer.createTransport({
      host:   process.env.SMTP_HOST,
      port:   parseInt(process.env.SMTP_PORT || '587', 10),
      secure: process.env.SMTP_SECURE === 'true',
      auth:   {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });
  }

  return _transporter;
}

/**
 * Send OTP via email.
 * Dev mode: logs OTP to console and returns { devOtp } — never sent externally.
 * Production: sends real email via SMTP.
 */
async function sendEmail(email, otp) {
  if (process.env.NODE_ENV !== 'production') {
    logger.info('otp_dev_mode', { email, otp });
    return { devOtp: otp };
  }

  const transporter = _getTransporter();

  await transporter.sendMail({
    from:    `"Cashback App" <${process.env.SMTP_FROM || 'noreply@cashbackapp.com'}>`,
    to:      email,
    subject: 'Your verification code',
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#059669">Verify your email</h2>
        <p>Enter this code in the app to activate your account:</p>
        <div style="font-size:40px;font-weight:800;letter-spacing:12px;
                    color:#111827;padding:24px 0">${otp}</div>
        <p style="color:#6B7280;font-size:13px">
          This code expires in ${OTP_TTL_MINUTES} minutes.<br>
          If you didn't request this, you can safely ignore this email.
        </p>
      </div>
    `,
  });

  return {};
}

module.exports = { createOtp, verifyOtp, sendEmail, validatePassword };
