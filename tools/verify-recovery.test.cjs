const test = require('node:test');
const assert = require('node:assert/strict');
const { validateRecovery } = require('./verify-recovery.cjs');
const database = 'wearly_handoff_123456_abcdef12_test';
const evidence = { status: 'passed', database, host: '127.0.0.1', port: 5433 };

test('recovery rejects business names, path traversal and production before connecting', () => {
  for (const name of ['wearly', 'wearly_test', '../' + database, database + ';DROP DATABASE x']) {
    assert.throws(() => validateRecovery(name, { ...evidence, database: name }, 'test', 5433));
  }
  assert.throws(() => validateRecovery(database, evidence, 'production', 5433));
});
test('recovery requires matching successful local bootstrap evidence and port', () => {
  for (const change of [{ status: 'failed' }, { database: 'other_test' }, { host: 'remote.example' }, { port: 5432 }]) {
    assert.throws(() => validateRecovery(database, { ...evidence, ...change }, 'test', 5433));
  }
  assert.doesNotThrow(() => validateRecovery(database, evidence, 'test', 5433));
});
