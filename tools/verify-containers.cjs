// Verify already-built local API/worker images against a retained bootstrap DB.
// Stops only containers created here; never removes containers, volumes or rows.
const fs = require('node:fs'), path = require('node:path');
const { promisify } = require('node:util');
const { execFile } = require('node:child_process');
const { createRequire } = require('node:module');
const { randomUUID, randomBytes } = require('node:crypto');
const assert = require('node:assert/strict');
const run = promisify(execFile), root = path.resolve(__dirname, '..');
const requireBackend = createRequire(path.join(root, 'backend/package.json'));
const config = requireBackend('dotenv').parse(fs.readFileSync(path.join(root, '.env')));
const started = [], report = { status: 'running', checks: [] };
let output;
function checkpoint() {
  if (output) fs.writeFileSync(path.join(output, 'containers.json'), JSON.stringify({ ...report, containersRetained: [...started] }, null, 2));
}
async function docker(args, env = process.env) { return (await run('docker', args, { env, windowsHide: true, timeout: 60000, maxBuffer: 2 * 1024 * 1024 })).stdout.trim(); }
async function main() {
  const database = process.argv[2];
  assert.match(database || '', /^wearly_handoff_[0-9]+_[a-f0-9]{8}_test$/);
  assert.notEqual(process.env.NODE_ENV || config.NODE_ENV, 'production');
  output = path.join(root, '.tools/handoff', database);
  const bootstrap = JSON.parse(fs.readFileSync(path.join(output, 'result.json'), 'utf8'));
  assert.equal(bootstrap.status, 'passed'); assert.equal(bootstrap.database, database);
  assert.equal(bootstrap.host, '127.0.0.1');
  const suffix = randomUUID().slice(0, 8), prefix = 'wearly-handoff-' + suffix;
  const dbUrl = new URL('postgresql://postgres:5432/' + database);
  dbUrl.username = config.POSTGRES_USER; dbUrl.password = config.POSTGRES_PASSWORD;
  const env = { ...process.env, ...config, NODE_ENV: 'test', PORT: '3000', DATABASE_URL: dbUrl.toString(), REDIS_HOST: 'redis', REDIS_PORT: '6379', AI_QUEUE_PREFIX: prefix, JWT_ACCESS_SECRET: randomBytes(32).toString('hex'), JWT_REFRESH_SECRET: randomBytes(32).toString('hex'), SWAGGER_ENABLED: 'true', S3_ENDPOINT: 'http://host.docker.internal:9000' };
  const names = ['NODE_ENV', 'PORT', 'DATABASE_URL', 'REDIS_HOST', 'REDIS_PORT', 'AI_QUEUE_PREFIX', 'JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET', 'JWT_ACCESS_EXPIRES_IN', 'JWT_REFRESH_EXPIRES_IN', 'CORS_ORIGINS', 'SWAGGER_ENABLED', 'S3_ENDPOINT', 'S3_PUBLIC_ENDPOINT', 'S3_REGION', 'S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY'];
  const flags = names.filter(key => env[key] !== undefined).flatMap(key => ['--env', key]);
  const secrets = [env.DATABASE_URL, config.POSTGRES_PASSWORD, env.JWT_ACCESS_SECRET, env.JWT_REFRESH_SECRET, config.S3_SECRET_ACCESS_KEY].filter(Boolean);
  const sanitize = s => secrets.reduce((text, secret) => text.split(secret).join('[redacted]'), s);
  report.database = database; report.queuePrefix = prefix;
  report.containerNames = [prefix + '-migration', prefix + '-api', prefix + '-worker'];
  report.startedAt = new Date().toISOString();
  checkpoint();
  let interrupted;
  const onInterrupt = () => { interrupted = 'SIGINT'; };
  const onTerminate = () => { interrupted = 'SIGTERM'; };
  function checkInterruption() {
    if (interrupted) throw Object.assign(new Error('Verification interrupted'), { code: 'HANDOFF_INTERRUPTED' });
  }
  process.on('SIGINT', onInterrupt);
  process.on('SIGTERM', onTerminate);
  try {
    const migrationId = await docker(['run', '-d', '--name', prefix + '-migration', '--label', 'wearly.verification=' + suffix, '--network', 'wearly_default', ...flags, 'wearly-handoff-migration:local'], env);
    started.push(migrationId);
    checkpoint(); checkInterruption();
    assert.equal(await docker(['wait', migrationId]), '0', 'Migration container failed');
    report.checks.push('separate migration container completed successfully');
    checkInterruption();
    const apiId = await docker(['run', '-d', '--name', prefix + '-api', '--label', 'wearly.verification=' + suffix, '--network', 'wearly_default', '-p', '127.0.0.1:3001:3000', ...flags, 'wearly-handoff-api:local'], env);
    started.push(apiId);
    checkpoint(); checkInterruption();
    const workerId = await docker(['run', '-d', '--name', prefix + '-worker', '--label', 'wearly.verification=' + suffix, '--network', 'wearly_default', ...flags, 'wearly-handoff-worker:local'], env);
    started.push(workerId);
    checkpoint(); checkInterruption();
    const inspectRuntime = "const fs=require('node:fs'),a=require('node:assert/strict');a.notEqual(process.getuid(),0);for(const p of ['jest','typescript','prisma','@nestjs/cli'])a.equal(fs.existsSync('node_modules/'+p),false,p+' in runtime');for(const p of ['src','test','.env'])a.equal(fs.existsSync(p),false,p+' in runtime');require('./dist/generated/prisma/client');";
    for (const id of [apiId, workerId]) {
      await docker(['exec', id, 'node', '-e', inspectRuntime]);
      checkInterruption();
    }
    report.checks.push('non-root API/worker; no test/compiler/Prisma CLI/source/secrets in runtime');
    let ready = false;
    for (let i = 0; i < 30; i++) {
      checkInterruption();
      assert.equal(await docker(['inspect', '--format', '{{.State.Running}}', apiId]), 'true', 'API container exited');
      try { const r = await fetch('http://127.0.0.1:3001/api/v1/health/ready', { signal: AbortSignal.timeout(1500) }); ready = r.ok; } catch { /* bounded startup polling */ }
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert(ready, 'Container API readiness timed out'); report.checks.push('API PostgreSQL/Redis readiness');
    checkInterruption();
    const spec = await (await fetch('http://127.0.0.1:3001/api/docs-json', { signal: AbortSignal.timeout(10000) })).json();
    assert(spec.paths['/api/v1/users/me/style']?.put); assert(spec.paths['/api/v1/admin/products']?.post);
    report.openapiPaths = Object.keys(spec.paths).length;
    async function api(method, endpoint, body, token, key, expected = 200) {
      checkInterruption();
      const response = await fetch('http://127.0.0.1:3001/api/v1/' + endpoint, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(key ? { 'Idempotency-Key': key } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000) });
      assert.equal(response.status, expected, method + ' ' + endpoint);
      return response.json();
    }
    await api('GET', 'cart', null, null, null, 401);
    const customer = await api('POST', 'auth/register', { email: prefix + '@example.test', name: 'Handoff container customer', password: randomBytes(24).toString('hex') }, null, null, 201);
    const token = customer.accessToken;
    assert.equal(customer.user.role, 'CUSTOMER'); assert.equal(customer.user.passwordHash, undefined);
    await api('GET', 'admin/products', null, token, null, 403);
    const addressBody = { recipient: 'Handoff customer', phone: '0901234567', address: '12 Test Street', label: 'Test', isDefault: true }, addressKey = randomUUID();
    const address = await api('POST', 'users/me/addresses', addressBody, token, addressKey, 201);
    assert.equal((await api('POST', 'users/me/addresses', addressBody, token, addressKey, 201)).id, address.id);
    await api('POST', 'cart/items', { sku: 'WRL-1-MAIN-M', quantity: 1 }, token, null, 201);
    const cart = await api('GET', 'cart', null, token);
    const orderKey = randomUUID(), orderBody = { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: cart.subtotal, cartVersion: cart.version };
    const order = await api('POST', 'orders', orderBody, token, orderKey, 201);
    assert.equal((await api('POST', 'orders', orderBody, token, orderKey, 201)).id, order.id);
    assert.equal(order.status, 'PENDING');
    report.checks.push('container auth/RBAC, address replay, real cart/COD order and order replay');
    const { Client } = requireBackend('pg');
    checkInterruption();
    const db = new Client({ host: '127.0.0.1', port: bootstrap.port, user: config.POSTGRES_USER, password: config.POSTGRES_PASSWORD, database, connectionTimeoutMillis: 5000, query_timeout: 10000 });
    await db.connect();
    try {
      assert.equal((await db.query('SELECT status FROM "Payment" WHERE "orderId"=$1', [order.id])).rows[0].status, 'PENDING');
      // Promote only this verifier's synthetic account in its retained test DB.
      assert.equal((await db.query('UPDATE "User" SET role=$1 WHERE id=$2', ['ADMIN', customer.user.id])).rowCount, 1);
      const category = await api('POST', 'admin/categories', { name: 'Container activity fixture', slug: prefix }, token, null, 201);
      const history = await api('GET', 'admin/audit?limit=1', null, token);
      assert.equal(history.items[0].actorId, customer.user.id);
      assert.equal(history.items[0].action, 'CATEGORY_CREATED');
      assert.equal(history.items[0].targetId, category.id);
      assert.equal(Number((await db.query('SELECT count(*) FROM "AdminAuditEvent" WHERE "actorId"=$1 AND "targetId"=$2', [customer.user.id, category.id])).rows[0].count), 1);
      report.checks.push('container admin write and authenticated activity event persisted atomically');
      const imageId = randomUUID(), jobId = randomUUID();
      await db.query('BEGIN');
      await db.query('INSERT INTO "ImageAsset" (id,"userId","objectKey","mimeType",size,"verifiedAt","expiresAt","updatedAt") VALUES ($1,$2,$3,$4,1,NOW(),NOW()+interval \'1 hour\',NOW())', [imageId, customer.user.id, prefix + '/synthetic.png', 'image/png']);
      await db.query('INSERT INTO "AIJob" (id,"userId","variantId","imageId","consentAt","updatedAt") VALUES ($1,$2,(SELECT id FROM "ProductVariant" WHERE sku=$3),$4,NOW(),NOW())', [jobId, customer.user.id, 'WRL-1-MAIN-M', imageId]);
      await db.query('INSERT INTO "OutboxEvent" (id,"jobId") VALUES ($1,$2)', [randomUUID(), jobId]);
      await db.query('COMMIT');
      let row;
      for (let i = 0; i < 40; i++) {
        checkInterruption();
        row = (await db.query('SELECT status,"errorCode",attempts FROM "AIJob" WHERE id=$1', [jobId])).rows[0];
        if (row.status === 'FAILED') break;
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      assert.equal(row.status, 'FAILED'); assert.equal(row.errorCode, 'AI_PROVIDER_NOT_CONFIGURED'); assert.equal(row.attempts, 1);
      assert.equal(Number((await db.query('SELECT count(*) FROM "TryOnResult" WHERE "jobId"=$1', [jobId])).rows[0].count), 0);
      assert((await db.query('SELECT "publishedAt" FROM "OutboxEvent" WHERE "jobId"=$1', [jobId])).rows[0].publishedAt);
      assert.equal(await docker(['inspect', '--format', '{{.State.Running}}', workerId]), 'true');
      report.checks.push('separate worker consumed outbox via Redis, Disabled provider failed without fake result');
    } finally { await db.end(); }
    checkInterruption();
    report.status = 'stopping';
  } catch (error) {
    report.status = 'failed'; report.error = error.code || error.name || 'Error';
    throw error;
  } finally {
    report.cleanup = [];
    checkpoint();
    try {
      for (const [index, id] of started.entries()) {
        const outcome = { id, stopped: false };
        report.cleanup.push(outcome);
        try { const logs = await run('docker', ['logs', id], { windowsHide: true, timeout: 10000, maxBuffer: 2 * 1024 * 1024 }); fs.writeFileSync(path.join(output, `container-${index}.log`), sanitize(logs.stdout + logs.stderr)); } catch { outcome.logCaptureError = true; }
        try { await docker(['stop', '--time', '15', id]); outcome.stopped = true; }
        catch (error) { outcome.stopError = error.code || error.name || 'Error'; report.status = 'failed'; report.error ||= 'CLEANUP_FAILED'; }
        checkpoint();
      }
      if (interrupted) { report.status = 'failed'; report.signal = interrupted; report.error ||= 'HANDOFF_INTERRUPTED'; }
      if (report.status !== 'failed') report.status = 'passed';
      report.finishedAt = new Date().toISOString();
      checkpoint();
    } finally {
      process.removeListener('SIGINT', onInterrupt);
      process.removeListener('SIGTERM', onTerminate);
    }
  }
  if (report.status !== 'passed') throw Object.assign(new Error('Verification cleanup failed'), { code: report.error });
  console.log('PASS container API, persisted COD, replay protection and separate worker; created containers stopped.');
}
main().catch(error => { report.status = 'failed'; report.error ||= error.code || error.name || 'Error'; checkpoint(); console.error('Container verification failed (' + report.error + '); inspect retained local logs.'); process.exitCode = 1; });
