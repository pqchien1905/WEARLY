// Restore a backup of a synthetic bootstrap DB into a NEW retained local DB.
// Never accepts business databases or restores over an existing database.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const run = promisify(execFile);
const root = path.resolve(__dirname, '..');
const sourcePattern = /^wearly_handoff_[0-9]+_[a-f0-9]{8}_test$/;

function validateRecovery(database, evidence, mode, port) {
  assert.match(database || '', sourcePattern);
  assert.notEqual(mode, 'production', 'Production recovery is not authorized');
  assert.equal(evidence.status, 'passed');
  assert.equal(evidence.database, database);
  assert.equal(evidence.host, '127.0.0.1');
  assert.equal(evidence.port, port);
  assert(Number.isInteger(port) && port > 0 && port <= 65535);
}
module.exports = { validateRecovery };

async function snapshot(db) {
  const result = {};
  const tables = (await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name")).rows;
  for (const { table_name: table } of tables) {
    assert.match(table, /^[A-Za-z_][A-Za-z0-9_]*$/);
    const { rows } = await db.query(`SELECT COUNT(*)::int AS count, COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb)::text AS data FROM "${table}" t`);
    result[table] = { count: rows[0].count, sha256: createHash('sha256').update(rows[0].data).digest('hex') };
  }
  return {
    tables: result,
    columns: (await db.query("SELECT table_name,column_name,ordinal_position,data_type,udt_name,is_nullable,column_default,numeric_precision,numeric_scale,character_maximum_length FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position")).rows,
    enums: (await db.query("SELECT t.typname,e.enumlabel,e.enumsortorder FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='public' ORDER BY t.typname,e.enumsortorder")).rows,
    // Pretty deparse normalizes equivalent AND grouping changed by dump/parse.
    constraints: (await db.query("SELECT c.relname AS table_name,co.conname,pg_get_constraintdef(co.oid,true) AS definition FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY c.relname,co.conname")).rows,
    indexes: (await db.query("SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname")).rows,
  };
}

async function main() {
  const database = process.argv[2];
  assert.match(database || '', sourcePattern);
  const requireBackend = createRequire(path.join(root, 'backend/package.json'));
  const config = requireBackend('dotenv').parse(fs.readFileSync(path.join(root, '.env')));
  const output = path.join(root, '.tools/handoff', database);
  const evidence = JSON.parse(fs.readFileSync(path.join(output, 'result.json'), 'utf8'));
  const port = Number(process.env.HANDOFF_POSTGRES_PORT || config.POSTGRES_PUBLISHED_PORT || 5432);
  validateRecovery(database, evidence, process.env.NODE_ENV || config.NODE_ENV, port);
  const target = 'wearly_restore_' + Date.now() + '_' + randomUUID().slice(0, 8) + '_test';
  const containerArchive = '/tmp/' + target + '.dump';
  const archive = path.join(output, target + '.dump');
  const reportFile = path.join(output, target + '.json');
  const report = { status: 'running', database, target, startedAt: new Date().toISOString(), checks: [] };
  const save = () => fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
  const { Client } = requireBackend('pg');
  const connection = { host: '127.0.0.1', port, user: config.POSTGRES_USER, password: config.POSTGRES_PASSWORD, connectionTimeoutMillis: 5000, query_timeout: 15000 };
  const env = { ...process.env, PGPASSWORD: config.POSTGRES_PASSWORD };
  const docker = async args => (await run('docker', args, { env, windowsHide: true, timeout: 60000, maxBuffer: 1024 * 1024 })).stdout.trim();
  const compose = ['compose', '-f', path.join(root, 'docker-compose.yml'), '--env-file', path.join(root, '.env')];
  let admin, source, restored;
  save();
  try {
    const container = await docker([...compose, 'ps', '-q', 'postgres']);
    assert.match(container, /^[a-f0-9]{12,64}$/);
    // Confirm the host snapshot and Docker dump refer to the same server.
    const published = await docker(['port', container, '5432/tcp']);
    assert(published.split(/\r?\n/).includes('127.0.0.1:' + port));
    source = new Client({ ...connection, database });
    await source.connect();
    const before = await snapshot(source);
    await docker(['exec', '-e', 'PGPASSWORD', container, 'pg_dump', '-h', '127.0.0.1', '-U', config.POSTGRES_USER, '-d', database, '-Fc', '-f', containerArchive]);
    await docker(['cp', container + ':' + containerArchive, archive]);
    report.archiveSha256 = createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
    report.checks.push('custom-format archive copied to local evidence');
    save();
    const restoreArchive = '/tmp/' + target + '-restore.dump';
    await docker(['cp', archive, container + ':' + restoreArchive]);
    admin = new Client({ ...connection, database: 'postgres' });
    await admin.connect();
    assert.equal((await admin.query('SELECT 1 FROM pg_database WHERE datname=$1', [target])).rowCount, 0);
    assert.match(target, /^wearly_restore_[0-9]+_[a-f0-9]{8}_test$/);
    await admin.query(`CREATE DATABASE "${target}" WITH ENCODING 'UTF8' TEMPLATE template0`);
    // No --clean / --create: restoration can never drop existing objects.
    await docker(['exec', '-e', 'PGPASSWORD', container, 'pg_restore', '-h', '127.0.0.1', '-U', config.POSTGRES_USER, '-d', target, '--exit-on-error', '--single-transaction', '--no-owner', '--no-privileges', restoreArchive]);
    restored = new Client({ ...connection, database: target });
    await restored.connect();
    const after = await snapshot(restored);
    report.mismatchedSections = Object.keys(before).filter(key =>
      JSON.stringify(before[key]) !== JSON.stringify(after[key]));
    assert.deepEqual(after, before, 'Restored data/schema differ from source');
    assert.deepEqual(await snapshot(source), before, 'Source changed during recovery verification');
    report.tables = before.tables;
    report.checks.push('all public table data, columns, enums, constraints and indexes match', 'source database unchanged');
    report.status = 'passed';
  } catch (error) {
    report.status = 'failed';
    report.error = error.code || error.name || 'Error';
    throw error;
  } finally {
    const closed = await Promise.allSettled([source?.end(), restored?.end(), admin?.end()]);
    if (closed.some(result => result.status === 'rejected')) {
      report.status = 'failed';
      report.error ||= 'CLEANUP_FAILED';
    }
    report.finishedAt = new Date().toISOString();
    save();
  }
  assert.equal(report.status, 'passed', 'Recovery connection cleanup failed');
  console.log('PASS backup/restore; source, new restore DB and archive retained: ' + target);
}
if (require.main === module) {
  main().catch(error => {
    // Never print SQL connection strings, raw pg/docker errors or credentials.
    console.error('Recovery verification failed (' + (error.code || error.name || 'Error') + '); inspect local evidence.');
    process.exitCode = 1;
  });
}
