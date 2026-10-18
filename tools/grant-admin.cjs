// Local operator tool. Never creates an account or a default password.
const path = require('node:path');
const { createRequire } = require('node:module');
const backend = path.resolve(__dirname, '../backend');
const fromBackend = createRequire(path.join(backend, 'package.json'));
fromBackend('dotenv').config({ path: path.join(backend, '.env'), quiet: true });
const { Client } = fromBackend('pg');
const email = (process.argv[2] || '').trim().toLowerCase();
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
  console.error('Usage: node tools/grant-admin.cjs existing-account@example.com');
  process.exit(1);
}
async function main() {
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  try {
    await db.query('BEGIN');
    const { rows } = await db.query('SELECT id, role, active FROM "User" WHERE email = $1 FOR UPDATE', [email]);
    if (!rows[0]) throw new Error('Account does not exist. Register in WEARLY first, then run this command again.');
    if (!rows[0].active) throw new Error('Account is disabled. No changes made.');
    if (rows[0].role !== 'ADMIN') {
      await db.query('UPDATE "User" SET role = $1, "updatedAt" = NOW() WHERE id = $2', ['ADMIN', rows[0].id]);
      await db.query('UPDATE "RefreshToken" SET "revokedAt" = NOW(), "updatedAt" = NOW() WHERE "userId" = $1 AND "revokedAt" IS NULL', [rows[0].id]);
    }
    await db.query('COMMIT');
    console.log('ADMIN ready for ' + email + '. Sign in again in WEARLY.');
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  } finally { await db.end(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
