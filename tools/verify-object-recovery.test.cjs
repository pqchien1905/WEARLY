const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { validateEvidence, validateAsset, verifyBytes, recordVerification } = require('./verify-object-recovery.cjs');
const database = 'wearly_handoff_123456_abcdef12_test';
const target = 'wearly_restore_123456_abcdef12_test';
const bootstrap = { status: 'passed', database, host: '127.0.0.1', port: 5433 };
const recovery = { status: 'passed', database, target, mismatchedSections: [] };
const containers = { status: 'passed', database, catalogAsset: { bucket: 'wearly-private-test', id: '11111111-1111-4111-8111-111111111111' } };
const config = { mode: 'test', port: 5433, endpoint: 'http://127.0.0.1:9000', businessBucket: 'wearly-private' };
const bytes = Buffer.from('synthetic image bytes');
const asset = { id: containers.catalogAsset.id, objectKey: 'catalog/11111111-1111-4111-8111-111111111111.png',
  mimeType: 'image/png', size: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };

test('object recovery requires matching successful synthetic local evidence', () => {
  assert.doesNotThrow(() => validateEvidence(database, bootstrap, recovery, containers, config));
  for (const changed of [{ mode: 'production' }, { endpoint: 'https://remote.test' },
    { endpoint: 'http://secret@localhost:9000' }, { endpoint: 'http://localhost:9000/prefix' },
    { port: 5432 }, { businessBucket: 'wearly-private-test' }]) {
    assert.throws(() => validateEvidence(database, bootstrap, recovery, containers, { ...config, ...changed }));
  }
  for (const changed of [{ status: 'failed' }, { database: 'wearly' }, { target: 'wearly_test' },
    { mismatchedSections: ['tables'] }]) {
    assert.throws(() => validateEvidence(database, bootstrap, { ...recovery, ...changed }, containers, config));
  }
  assert.throws(() => validateEvidence('../' + database, bootstrap, recovery, containers, config));
  assert.throws(() => validateEvidence(database, bootstrap, recovery, { ...containers, status: 'failed' }, config));
  assert.throws(() => validateEvidence(database, bootstrap, recovery,
    { ...containers, catalogAsset: { ...containers.catalogAsset, bucket: 'business' } }, config));
});
test('archive entries cannot escape the catalog prefix or bypass byte/hash verification', () => {
  assert.doesNotThrow(() => validateAsset(asset));
  assert.doesNotThrow(() => verifyBytes(asset, bytes));
  for (const changed of [{ objectKey: '../../secret' }, { objectKey: 'uploads/private.png' },
    { objectKey: 'catalog/22222222-2222-4222-8222-222222222222.png' },
    { mimeType: 'text/html' }, { size: 0 }, { size: 8388609 }, { sha256: 'invalid' }]) {
    assert.throws(() => validateAsset({ ...asset, ...changed }));
  }
  assert.throws(() => verifyBytes(asset, Buffer.from('corrupt image bytes')));
  assert.throws(() => verifyBytes({ ...asset, size: bytes.length + 1 }, bytes));
});
test('real Nest startup failure records failed evidence and closes existing resources', () => {
  // A child process detects Nest's abortOnError exit, which would bypass catch/finally.
  const result = spawnSync(process.execPath, ['-e', `
    const assert = require('node:assert/strict');
    require('./backend/node_modules/reflect-metadata');
    const { Module } = require('./backend/node_modules/@nestjs/common');
    const { NestFactory } = require('./backend/node_modules/@nestjs/core');
    const { recordVerification, createRecoveryApp } = require('./tools/verify-object-recovery.cjs');
    class Broken {}
    Module({ providers: [{ provide: 'FAIL', useFactory: () => { throw new Error('Synthetic startup failure'); } }] })(Broken);
    (async () => {
      const report = { status: 'running' }, saved = [], closed = [];
      await assert.rejects(recordVerification(report, () => saved.push({ ...report }),
        () => createRecoveryApp(NestFactory, Broken),
        async () => { closed.push('sourceDb', 'restoredDb', 'sourceStorage', 'targetStorage', 's3'); }),
        /Synthetic startup failure/);
      assert.equal(report.status, 'failed');
      assert.equal(saved.at(-1).status, 'failed');
      assert.equal(closed.length, 5);
      assert(report.finishedAt);
      console.log('STARTUP_FAILURE_CLEANED');
    })().catch(() => { process.exitCode = 1; });
  `], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8', timeout: 10000, windowsHide: true });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /STARTUP_FAILURE_CLEANED/);
});
test('cleanup failure cannot leave a passed report or erase the original failure', async () => {
  for (const failOperation of [false, true]) {
    const report = { status: 'running' }, saved = [];
    const pending = recordVerification(report, () => saved.push({ ...report }), async () => {
      if (failOperation) throw Object.assign(new Error('Synthetic'), { code: 'ORIGINAL_FAILURE' });
      report.status = 'passed';
    }, async () => { throw new Error('Synthetic cleanup failure'); });
    if (failOperation) await assert.rejects(pending, { code: 'ORIGINAL_FAILURE' });
    else await pending;
    assert.equal(saved.at(-1).status, 'failed');
    assert.equal(saved.at(-1).error, failOperation ? 'ORIGINAL_FAILURE' : 'CLEANUP_FAILED');
  }
});
