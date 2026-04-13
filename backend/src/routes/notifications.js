const express         = require('express');
const db              = require('../config/db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// GET /notifications
router.get('/', requireAuth, async (req, res) => {
  const limit  = Math.min(parseInt(req.query.limit || '30', 10), 100);
  const unread = req.query.unread === 'true';

  const { rows } = await db.query(
    `SELECT id, type, title, body, data, read, created_at
     FROM   notifications
     WHERE  user_id = $1 ${unread ? 'AND read = FALSE' : ''}
     ORDER  BY created_at DESC
     LIMIT  $2`,
    [req.user.id, limit]
  );

  const { rows: [{ count }] } = await db.query(
    `SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND read = FALSE`,
    [req.user.id]
  );

  res.json({ notifications: rows, unread_count: parseInt(count) });
});

// POST /notifications/read-all
router.post('/read-all', requireAuth, async (req, res) => {
  await db.query(
    `UPDATE notifications SET read = TRUE WHERE user_id = $1 AND read = FALSE`,
    [req.user.id]
  );
  res.json({ message: 'All notifications marked as read' });
});

// PATCH /notifications/:id/read
router.patch('/:id/read', requireAuth, async (req, res) => {
  await db.query(
    `UPDATE notifications SET read = TRUE WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user.id]
  );
  res.json({ message: 'Notification marked as read' });
});

module.exports = router;
