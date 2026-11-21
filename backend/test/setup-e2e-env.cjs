// Set the database BEFORE AppModule/ConfigModule imports can capture .env.
// Per-suite beforeAll hooks are too late to guarantee that isolation.
const fs = require('node:fs');
const path = require('node:path');
const dotenv = require('dotenv');
const base = path.resolve(__dirname, '..');
const read = file => fs.existsSync(file) ? dotenv.parse(fs.readFileSync(file)) : {};
const normal = read(path.join(base, '.env'));
const isolated = read(path.join(base, '.env.test'));
const target = process.env.TEST_DATABASE_URL || isolated.TEST_DATABASE_URL;
if (!target) throw Error('A dedicated TEST_DATABASE_URL is required before E2E imports.');
const url = new URL(target);
const business = normal.DATABASE_URL ? new URL(normal.DATABASE_URL) : null;
if (!['postgres:', 'postgresql:'].includes(url.protocol) || !/^\/[a-zA-Z0-9_]+_test$/.test(url.pathname) ||
    (business && url.hostname === business.hostname && (url.port || '5432') === (business.port || '5432') && url.pathname === business.pathname)) {
  throw Error('E2E tests require an isolated *_test database, distinct from backend/.env.');
}
process.env.TEST_DATABASE_URL = target;
process.env.DATABASE_URL = target;
process.env.NODE_ENV = 'test';
process.env.PASSWORD_RECOVERY_ENABLED = 'false';
process.env.LOCAL_MAIL_ENABLED = 'false';
process.env.MAIL_DELIVERY_ENABLED = 'false';
process.env.VNPAY_ENABLED = 'false';
process.env.MOMO_ENABLED = 'false';
process.env.ZALOPAY_ENABLED = 'false';
process.env.GEMINI_API_KEY = ' ';
// Local SMTP fixtures must never inherit the configured Gmail transport/secret.
process.env.SMTP_HOST = '127.0.0.1';
process.env.SMTP_PORT = '1025';
process.env.SMTP_SECURE = 'false';
process.env.SMTP_ALLOW_INSECURE_LOCAL = 'true';
process.env.SMTP_FROM = 'store@example.test';
process.env.SMTP_USER = '';
process.env.SMTP_PASSWORD = '';
