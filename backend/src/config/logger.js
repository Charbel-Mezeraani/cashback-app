const { createLogger, format, transports } = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');
const path = require('path');

const { combine, timestamp, errors, json, colorize, printf } = format;

const isDev = process.env.NODE_ENV !== 'production';

// ── Console format (dev only) ────────────────────────────────────────────────
const devFormat = combine(
  colorize(),
  timestamp({ format: 'HH:mm:ss' }),
  errors({ stack: true }),
  printf(({ level, message, timestamp: ts, ...meta }) => {
    const extra = Object.keys(meta).length ? ' ' + JSON.stringify(meta) : '';
    return `${ts} ${level}: ${message}${extra}`;
  })
);

// ── JSON format (production) ─────────────────────────────────────────────────
const prodFormat = combine(
  timestamp(),
  errors({ stack: true }),
  json()
);

const logger = createLogger({
  level: process.env.LOG_LEVEL || (isDev ? 'debug' : 'info'),
  format: isDev ? devFormat : prodFormat,
  transports: [
    new transports.Console(),
  ],
});

// File transports in production
if (!isDev) {
  const logDir = path.join(__dirname, '../../logs');

  logger.add(new DailyRotateFile({
    dirname:       logDir,
    filename:      'app-%DATE%.log',
    datePattern:   'YYYY-MM-DD',
    maxFiles:      '14d',
    maxSize:       '50m',
    level:         'info',
  }));

  logger.add(new DailyRotateFile({
    dirname:       logDir,
    filename:      'error-%DATE%.log',
    datePattern:   'YYYY-MM-DD',
    maxFiles:      '30d',
    level:         'error',
  }));
}

module.exports = logger;
