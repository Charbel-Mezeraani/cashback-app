const db     = require('../config/db');
const logger = require('../config/logger');

/**
 * Create a notification for a user.
 *
 * @param {string} userId
 * @param {string} type   - notification_type enum value
 * @param {object} opts   - { title, body, data }
 */
async function createNotification(userId, type, { title, body, data = {} } = {}) {
  try {
    await db.query(
      `INSERT INTO notifications (user_id, type, title, body, data)
       VALUES ($1, $2::notification_type, $3, $4, $5)`,
      [userId, type, title, body, JSON.stringify(data)]
    );
    logger.debug('notification_created', { userId, type });
  } catch (err) {
    // Notifications are non-critical — log but don't throw
    logger.error('notification_failed', { userId, type, error: err.message });
  }
}

module.exports = { createNotification };
