// Creates and retains a NEW local test database. Never resets, drops, or reuses one.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { createHash, randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..'), backend = path.join(root, 'backend');
const fromBackend = createRequire(path.join(backend, 'package.json'));
const config = fromBackend('dotenv').parse(fs.readFileSync(path.join(root, '.env')));
const { Client } = fromBackend('pg');
let reportPath;
const report = { status: 'running', checks: [] };
function save() { if (reportPath) fs.writeFileSync(reportPath, JSON.stringify(report, null, 2)); }
function requireLocalConfig() {
  if (!process.argv.includes('--docker')) throw new Error('Use --docker with the local Compose PostgreSQL service running.');
  if ((process.env.NODE_ENV || config.NODE_ENV) === 'production') throw new Error('Production verification is refused.');
  const port = Number(process.env.HANDOFF_POSTGRES_PORT || config.POSTGRES_PUBLISHED_PORT || 5432);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid local PostgreSQL port.');
  if (!config.POSTGRES_USER || !config.POSTGRES_PASSWORD) throw new Error('Root .env needs local Compose PostgreSQL credentials.');
  return { host: '127.0.0.1', port, user: config.POSTGRES_USER, password: config.POSTGRES_PASSWORD, connectionTimeoutMillis: 5000 };
}
async function main() {
  const connection = requireLocalConfig();
  if (process.argv.includes('--check-config')) { console.log('Local configuration guards passed; no database connection made.'); return; }
  const database = 'wearly_handoff_' + Date.now() + '_' + randomUUID().slice(0, 8) + '_test';
  assert.match(database, /^wearly_handoff_[0-9]+_[a-f0-9]{8}_test$/);
  const output = path.join(root, '.tools/handoff', database);
  fs.mkdirSync(output, { recursive: true });
  reportPath = path.join(output, 'result.json');
  Object.assign(report, { database, host: connection.host, port: connection.port, startedAt: new Date().toISOString() });
  save();
  const admin = new Client({ ...connection, database: 'postgres' });
  try {
    await admin.connect();
    const existing = await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [database]);
    assert.equal(existing.rowCount, 0, 'Refusing to reuse an existing database');
    await admin.query(`CREATE DATABASE "${database}" WITH ENCODING 'UTF8' TEMPLATE template0`);
  } finally { await admin.end(); }
  report.checks.push('new empty database created, retained without reset/drop'); save();
  const url = new URL('postgresql://127.0.0.1');
  url.port = String(connection.port); url.username = connection.user; url.password = connection.password; url.pathname = '/' + database;
  const env = { ...process.env, ...config, NODE_ENV: 'test', DATABASE_URL: url.toString() };
  // Prisma's configured seed invokes tsx; mirror npm-run's local executable PATH.
  const pathKey = Object.keys(env).find(key => key.toLowerCase() === 'path') || 'PATH';
  env[pathKey] = path.join(backend, 'node_modules/.bin') + path.delimiter + (env[pathKey] || '');
  const secrets = [connection.password, url.toString(), config.JWT_ACCESS_SECRET, config.JWT_REFRESH_SECRET, config.S3_SECRET_ACCESS_KEY].filter(Boolean);
  const sanitize = value => secrets.reduce((s, secret) => s.split(secret).join('[redacted]'), value);
  async function prisma(label, args) {
    report.currentStep = label; save();
    const log = fs.createWriteStream(path.join(output, label + '.log'));
    const child = spawn(process.execPath, [path.join(backend, 'node_modules/prisma/build/index.js'), ...args], { cwd: backend, env, windowsHide: true });
    let captured = '';
    child.stdout.on('data', chunk => { captured += chunk.toString(); });
    child.stderr.on('data', chunk => { captured += chunk.toString(); });
    const timeout = setTimeout(() => child.kill(), 120000);
    const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); }).finally(() => clearTimeout(timeout));
    await new Promise(resolve => log.end(sanitize(captured), resolve));
    assert.equal(code, 0, `${label} failed; inspect ${path.relative(root, output)}/${label}.log`);
    report.checks.push(label); save(); console.log('PASS ' + label);
  }
  await prisma('validate', ['validate']);
  await prisma('generate', ['generate']);
  await prisma('deploy', ['migrate', 'deploy']);
  await prisma('migration-status', ['migrate', 'status']);
  await prisma('schema-diff', ['migrate', 'diff', '--from-config-datasource', '--to-schema', 'prisma/schema.prisma', '--exit-code']);
  const db = new Client({ ...connection, database });
  await db.connect();
  try {
    const migrations = (await db.query('SELECT migration_name FROM "_prisma_migrations" WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL ORDER BY migration_name')).rows.map(r => r.migration_name);
    const expected = fs.readdirSync(path.join(backend, 'prisma/migrations'), { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name).sort();
    assert.deepEqual(migrations, expected);
    report.migrations = migrations;
    await prisma('seed-first', ['db', 'seed']);
    const count = async table => Number((await db.query(`SELECT COUNT(*) AS count FROM "${table}"`)).rows[0].count);
    report.seedCounts = {};
    for (const [table, expectedCount] of Object.entries({ Product: 32, ProductVariant: 256, Inventory: 256, InventoryMovement: 256, ProductImage: 32, Category: 4, Brand: 1, User: 0 })) {
      const actual = await count(table); assert.equal(actual, expectedCount, table); report.seedCounts[table] = actual;
    }
    // Explicit edits only in the freshly created database, never in development data.
    async function editOne(sql, values) {
      assert.equal((await db.query(sql, values)).rowCount, 1, 'Seed fixture edit must affect exactly one row');
    }
    await editOne('UPDATE "ProductVariant" SET price=123456 WHERE sku=$1', ['WRL-1-MAIN-M']);
    await editOne('UPDATE "Inventory" SET quantity=7, version=version+1 WHERE "variantId"=(SELECT id FROM "ProductVariant" WHERE sku=$1)', ['WRL-1-MAIN-M']);
    await editOne('UPDATE "Product" SET name=$1 WHERE slug=$2', ['Handoff edited product', 'nep-1']);
    await editOne('UPDATE "Category" SET name=$1 WHERE slug=$2', ['Handoff edited category', 'ao']);
    await editOne('UPDATE "Brand" SET name=$1 WHERE slug=$2', ['Handoff edited brand', 'wearly']);
    await editOne('UPDATE "ProductImage" SET alt=$1 WHERE "productId"=(SELECT id FROM "Product" WHERE slug=$2)', ['Handoff edited image', 'nep-1']);
    const passwordHash = await fromBackend('argon2').hash(randomUUID());
    await db.query('INSERT INTO "User" (id,email,"passwordHash",name,"updatedAt") VALUES ($1,$2,$3,$4,NOW())', [randomUUID(), database + '@example.test', passwordHash, 'Handoff synthetic customer']);
    const tables = (await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name <> '_prisma_migrations' ORDER BY table_name")).rows.map(r => r.table_name);
    async function snapshot() {
      const result = {};
      for (const table of tables) {
        assert.match(table, /^[A-Za-z][A-Za-z0-9_]*$/);
        const data = (await db.query(`SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), '[]'::jsonb)::text AS data FROM "${table}" t`)).rows[0].data;
        result[table] = { count: await count(table), sha256: createHash('sha256').update(data).digest('hex') };
      }
      return result;
    }
    const before = await snapshot();
    await prisma('seed-second', ['db', 'seed']);
    const after = await snapshot();
    assert.deepEqual(after, before, 'Repeated seed changed existing records or created duplicates');
    report.preservedTables = after;
    report.checks.push('second seed preserved edited catalog, stock, user and all business table snapshots');
    report.status = 'passed'; report.finishedAt = new Date().toISOString(); save();
    console.log('PASS isolated migration/schema/seed verification. Evidence and database retained: ' + path.relative(root, output));
  } finally { await db.end(); }
}
main().catch(error => {
  report.status = 'failed'; report.error = error.code || error.name || 'Error'; save();
  // Connection errors can contain credentials; print only the error class/code.
  console.error('Bootstrap verification failed (' + report.error + ').' + (reportPath ? ' Inspect ' + path.relative(root, reportPath) : ' Check local-only arguments/configuration.'));
  process.exitCode = 1;
});
