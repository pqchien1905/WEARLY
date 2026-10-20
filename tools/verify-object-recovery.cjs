// Local synthetic catalog recovery only. Retains source, archive, new bucket and
// restored DB. Never deletes objects, changes bucket policy or restores in place.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { validateRecovery } = require('./verify-recovery.cjs');
const root = path.resolve(__dirname, '..');
const sourcePattern = /^wearly_handoff_[0-9]+_[a-f0-9]{8}_test$/;
const targetPattern = /^wearly_restore_[0-9]+_[a-f0-9]{8}_test$/;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

function validateEvidence(database, bootstrap, recovery, containers, config) {
  validateRecovery(database, bootstrap, config.mode, config.port);
  assert.equal(recovery.status, 'passed');
  assert.equal(recovery.database, database);
  assert.match(recovery.target, targetPattern);
  assert.deepEqual(recovery.mismatchedSections, []);
  assert.equal(containers.status, 'passed');
  assert.equal(containers.database, database);
  assert.match(containers.catalogAsset?.id || '', uuid);
  assert.match(containers.catalogAsset.bucket, /^[a-z0-9][a-z0-9-]{1,57}-test$/);
  assert.notEqual(containers.catalogAsset.bucket, config.businessBucket);
  const endpoint = new URL(config.endpoint);
  assert(['http:', 'https:'].includes(endpoint.protocol));
  assert(['127.0.0.1', 'localhost', '[::1]'].includes(endpoint.hostname));
  assert(!endpoint.username && !endpoint.password && !endpoint.search && !endpoint.hash);
  assert.equal(endpoint.pathname, '/');
}
function validateAsset(asset) {
  assert.match(asset.id, uuid);
  assert(['image/png', 'image/jpeg'].includes(asset.mimeType));
  assert.equal(asset.objectKey, `catalog/${asset.id}${asset.mimeType === 'image/png' ? '.png' : '.jpg'}`);
  assert(Number.isInteger(asset.size) && asset.size > 0 && asset.size <= 8 * 1024 * 1024);
  assert.match(asset.sha256, /^[a-f0-9]{64}$/);
}
function verifyBytes(asset, bytes) {
  validateAsset(asset);
  assert.equal(bytes.length, asset.size, 'Object size differs from database');
  assert.equal(digest(bytes), asset.sha256, 'Object hash differs from database');
}
async function recordVerification(report, save, operation, cleanup) {
  try {
    await operation();
  } catch (error) {
    report.status = 'failed'; report.error = error.code || error.name || 'Error';
    throw error;
  } finally {
    try { await cleanup(); }
    catch { report.status = 'failed'; report.error ||= 'CLEANUP_FAILED'; }
    report.finishedAt = new Date().toISOString(); save();
  }
}
const createRecoveryApp = (factory, module) =>
  factory.create(module, { logger: false, abortOnError: false });
module.exports = { validateEvidence, validateAsset, verifyBytes, recordVerification, createRecoveryApp };

async function main() {
  const [database, restoredDatabase] = process.argv.slice(2);
  assert.match(database || '', sourcePattern);
  assert.match(restoredDatabase || '', targetPattern);
  const requireBackend = createRequire(path.join(root, 'backend/package.json'));
  const dotenv = requireBackend('dotenv');
  const config = dotenv.parse(fs.readFileSync(path.join(root, '.env')));
  const backendConfig = dotenv.parse(fs.readFileSync(path.join(root, 'backend/.env')));
  // Read and validate all evidence before making any network connection.
  const directory = path.join(root, '.tools/handoff', database);
  const read = file => JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
  const bootstrap = read('result.json'), containers = read('containers.json');
  const recovery = read(restoredDatabase + '.json');
  const port = Number(config.POSTGRES_PUBLISHED_PORT || 5432);
  for (const mode of [process.env.NODE_ENV, config.NODE_ENV, backendConfig.NODE_ENV]) assert.notEqual(mode, 'production');
  validateEvidence(database, bootstrap, recovery, containers, {
    mode: 'test', port, endpoint: backendConfig.S3_ENDPOINT, businessBucket: backendConfig.S3_BUCKET,
  });
  assert.equal(recovery.target, restoredDatabase);
  const sourceBucket = containers.catalogAsset.bucket;
  const suffix = Date.now() + '-' + randomUUID().slice(0, 8);
  const targetBucket = 'wearly-restore-' + suffix + '-test';
  const output = path.join(directory, 'objects-' + suffix);
  fs.mkdirSync(output); // Fresh directory; never overwrite an existing archive.
  const report = { status: 'running', database, restoredDatabase, sourceBucket, targetBucket,
    startedAt: new Date().toISOString(), checks: [] };
  const save = () => fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
  save();
  const dbOptions = { host: '127.0.0.1', port, user: config.POSTGRES_USER,
    password: config.POSTGRES_PASSWORD, connectionTimeoutMillis: 5000, query_timeout: 10000 };
  let sourceDb, restoredDb, sdk, s3, sourceStorage, targetStorage, app;
  const send = command => s3.send(command, { abortSignal: AbortSignal.timeout(8000) });
  const rows = async db => (await db.query(
    'SELECT to_jsonb(c) AS data FROM "CatalogAsset" c WHERE "verifiedAt" IS NOT NULL AND "deletedAt" IS NULL ORDER BY id LIMIT 101',
  )).rows.map(row => row.data);
  async function privateBucket(bucket) {
    try {
      await send(new sdk.GetBucketPolicyCommand({ Bucket: bucket }));
      throw new Error('BUCKET_POLICY_PRESENT');
    } catch (error) {
      if (error.name !== 'NoSuchBucketPolicy') throw error;
    }
    const versioning = await send(new sdk.GetBucketVersioningCommand({ Bucket: bucket }));
    assert(!versioning.Status, 'Versioned bucket is outside this recovery scope');
  }
  async function anonymousDenied(bucket, key) {
    const response = await fetch(new URL('/' + bucket + '/' + key, backendConfig.S3_ENDPOINT), {
      signal: AbortSignal.timeout(8000),
    });
    await response.body?.cancel();
    assert.equal(response.status, 403, 'Object must remain private in S3');
  }
  await recordVerification(report, save, async () => {
    const { Client } = requireBackend('pg');
    sourceDb = new Client({ ...dbOptions, database });
    restoredDb = new Client({ ...dbOptions, database: restoredDatabase });
    sdk = requireBackend('@aws-sdk/client-s3');
    s3 = new sdk.S3Client({ endpoint: backendConfig.S3_ENDPOINT, region: backendConfig.S3_REGION,
      forcePathStyle: true, maxAttempts: 1, credentials: {
        accessKeyId: backendConfig.S3_ACCESS_KEY_ID, secretAccessKey: backendConfig.S3_SECRET_ACCESS_KEY,
      } });
    requireBackend('reflect-metadata');
    const { ConfigService } = requireBackend('@nestjs/config');
    const { StorageService } = requireBackend('./dist/integrations/storage/storage.service');
    sourceStorage = new StorageService(new ConfigService({ ...backendConfig, S3_BUCKET: sourceBucket }));
    targetStorage = new StorageService(new ConfigService({ ...backendConfig, S3_BUCKET: targetBucket }));
    await sourceDb.connect(); await restoredDb.connect();
    const before = await rows(sourceDb);
    assert(before.length > 0 && before.length <= 100, 'Recovery is bounded to 1..100 synthetic catalog assets');
    assert(before.some(asset => asset.id === containers.catalogAsset.id));
    assert.deepEqual(await rows(restoredDb), before, 'Restored catalog metadata differs');
    let total = 0;
    for (const asset of before) { validateAsset(asset); total += asset.size; }
    assert(total <= 64 * 1024 * 1024, 'Synthetic archive exceeds 64 MiB limit');
    await privateBucket(sourceBucket);
    const manifest = [];
    for (const asset of before) {
      const bytes = await sourceStorage.readImage(asset.objectKey);
      verifyBytes(asset, bytes);
      await anonymousDenied(sourceBucket, asset.objectKey);
      const file = asset.id + '.bin';
      fs.writeFileSync(path.join(output, file), bytes, { flag: 'wx' });
      manifest.push({ id: asset.id, objectKey: asset.objectKey, mimeType: asset.mimeType,
        size: asset.size, sha256: asset.sha256, file });
    }
    fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
      database, restoredDatabase, sourceBucket, catalogSnapshotSha256: digest(JSON.stringify(before)), assets: manifest,
    }, null, 2), { flag: 'wx' });
    report.checks.push('verified synthetic catalog objects exported to local archive; source bucket private/unversioned');
    save();
    // Never accept an existing bucket, including one owned by these credentials.
    try {
      await send(new sdk.HeadBucketCommand({ Bucket: targetBucket }));
      throw new Error('RESTORE_BUCKET_ALREADY_EXISTS');
    } catch (error) {
      if (error.$metadata?.httpStatusCode !== 404) throw error;
    }
    await send(new sdk.CreateBucketCommand({ Bucket: targetBucket }));
    report.bucketCreated = true; save();
    await privateBucket(targetBucket);
    for (const asset of manifest) {
      const file = path.join(output, asset.file);
      assert.equal(fs.statSync(file).size, asset.size);
      const bytes = fs.readFileSync(file);
      verifyBytes(asset, bytes);
      await send(new sdk.PutObjectCommand({ Bucket: targetBucket, Key: asset.objectKey, Body: bytes,
        ContentType: asset.mimeType, CacheControl: 'private, no-store', IfNoneMatch: '*' }));
      verifyBytes(asset, await targetStorage.readImage(asset.objectKey));
      const headers = await send(new sdk.HeadObjectCommand({ Bucket: targetBucket, Key: asset.objectKey }));
      assert.equal(headers.ContentType, asset.mimeType);
      assert.equal(headers.ContentLength, asset.size);
      await anonymousDenied(targetBucket, asset.objectKey);
      verifyBytes(asset, await sourceStorage.readImage(asset.objectKey));
    }
    assert.deepEqual(await rows(sourceDb), before, 'Source catalog changed during recovery');
    assert.deepEqual(await rows(restoredDb), before, 'Restored catalog changed during recovery');
    report.checks.push('new private bucket restored from files; exact bytes/MIME/size match; source objects and both catalog snapshots unchanged');
    // Verify the restored DB + new bucket through the actual compiled public API.
    const dbUrl = new URL('postgresql://127.0.0.1');
    dbUrl.port = String(port); dbUrl.username = config.POSTGRES_USER; dbUrl.password = config.POSTGRES_PASSWORD;
    dbUrl.pathname = '/' + restoredDatabase;
    Object.assign(process.env, backendConfig, { NODE_ENV: 'test', DATABASE_URL: dbUrl.toString(),
      S3_BUCKET: targetBucket, REDIS_HOST: '127.0.0.1', PASSWORD_RECOVERY_ENABLED: 'false' });
    const { NestFactory } = requireBackend('@nestjs/core');
    const { AppModule } = requireBackend('./dist/app.module');
    const { configureApp } = requireBackend('./dist/bootstrap');
    app = await createRecoveryApp(NestFactory, AppModule);
    configureApp(app); await app.listen(0, '127.0.0.1');
    for (const asset of manifest) {
      const response = await fetch((await app.getUrl()) + '/api/v1/catalog/images/' + asset.id, {
        signal: AbortSignal.timeout(12000),
      });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('content-type'), asset.mimeType);
      verifyBytes(asset, Buffer.from(await response.arrayBuffer()));
    }
    report.checks.push('compiled API serves exact restored images using restored DB and new bucket');
    report.objects = manifest.length; report.bytes = total; report.status = 'passed';
  }, async () => {
    const closed = await Promise.allSettled([
      () => sourceDb?.end(), () => restoredDb?.end(), () => app?.close(),
      () => sourceStorage?.onModuleDestroy(), () => targetStorage?.onModuleDestroy(), () => s3?.destroy(),
    ].map(async close => close()));
    if (closed.some(result => result.status === 'rejected')) throw new Error('CLEANUP_FAILED');
  });
  assert.equal(report.status, 'passed');
  console.log('PASS local catalog object recovery; source, archive and new bucket retained: ' + path.relative(root, output));
}
if (require.main === module) main().catch(error => {
  console.error('Object recovery failed (' + (error.code || error.name || 'Error') + '); inspect retained local evidence.');
  process.exitCode = 1;
});
