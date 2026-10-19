// Failure-path regression tests: run the CLI with controlled Docker boundaries.
// No Docker daemon, database, credentials or real signals are used here.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const { promisify } = require('node:util');
const source = fs.readFileSync(path.join(__dirname, 'verify-containers.cjs'), 'utf8');
const database = 'wearly_handoff_123456_abcdef12_test';

async function scenario({ signal, signalAt = 'api', failFirstStop = false } = {}) {
  const processStub = new EventEmitter();
  Object.assign(processStub, { env: {}, argv: ['node', 'verify-containers.cjs', database] });
  const calls = [], checkpoints = [], messages = [];
  let handledSignal = false, creationCheckpoint = false;
  const execFile = () => {};
  execFile[promisify.custom] = async (command, args, options) => {
    calls.push({ args, options });
    if (args[0] === 'run') {
      const kind = args.includes('wearly-handoff-api:local') ? 'api' : 'worker';
      creationCheckpoint = creationCheckpoint || checkpoints.some(r => r.queuePrefix);
      if (signal && signalAt === kind) handledSignal = processStub.emit(signal);
      return { stdout: kind + '-id', stderr: '' };
    }
    if (args[0] === 'inspect') throw Object.assign(new Error('verification boundary failed'), { code: 'E_VERIFY' });
    if (args[0] === 'stop' && args.at(-1) === 'api-id' && failFirstStop) {
      throw Object.assign(new Error('stop boundary failed'), { code: 'E_STOP' });
    }
    return { stdout: '', stderr: '' };
  };
  const fakeFs = {
    readFileSync(file) {
      if (String(file).endsWith('result.json')) return JSON.stringify({ status: 'passed', database, host: '127.0.0.1', port: 5433 });
      return '';
    },
    writeFileSync(file, data) {
      if (String(file).endsWith('containers.json')) checkpoints.push(JSON.parse(data));
    },
  };
  const requireBackend = name => {
    assert.equal(name, 'dotenv');
    return { parse: () => ({ POSTGRES_USER: 'local', POSTGRES_PASSWORD: 'synthetic-only' }) };
  };
  const sandbox = {
    __dirname, process: processStub, URL, AbortSignal, setTimeout, clearTimeout,
    console: { log: message => messages.push(message), error: message => messages.push(message) },
    require(name) {
      if (name === 'node:fs') return fakeFs;
      if (name === 'node:child_process') return { execFile };
      if (name === 'node:module') return { createRequire: () => requireBackend };
      return require(name);
    },
  };
  await vm.runInNewContext(source, sandbox, { filename: 'verify-containers.cjs' });
  return { calls, checkpoints, messages, handledSignal, creationCheckpoint, exitCode: processStub.exitCode };
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  test(`${signal} during container creation checkpoints its ID and stops it`, async () => {
    const result = await scenario({ signal });
    assert.equal(result.handledSignal, true, 'signal must be intercepted');
    assert.equal(result.creationCheckpoint, true, 'run metadata must exist before docker run');
    assert.deepEqual(result.calls.filter(c => c.args[0] === 'stop').map(c => c.args.at(-1)), ['api-id']);
    assert.equal(result.calls.filter(c => c.args[0] === 'run').length, 1, 'do not start worker after interruption');
    assert(result.checkpoints.some(r => r.containersRetained?.includes('api-id')));
    assert.equal(result.checkpoints.at(-1).status, 'failed');
    assert.notEqual(result.exitCode, 0);
    assert.equal(result.messages.some(m => m.startsWith('PASS')), false);
  });
}

test('signal while worker creation is in flight stops both known containers', async () => {
  const result = await scenario({ signal: 'SIGINT', signalAt: 'worker' });
  assert.equal(result.handledSignal, true);
  assert.deepEqual(result.calls.filter(c => c.args[0] === 'stop').map(c => c.args.at(-1)), ['api-id', 'worker-id']);
  assert.deepEqual(result.checkpoints.at(-1).containersRetained, ['api-id', 'worker-id']);
});

test('a failed first stop does not skip second stop or erase original failure', async () => {
  const result = await scenario({ failFirstStop: true });
  assert.deepEqual(result.calls.filter(c => c.args[0] === 'stop').map(c => c.args.at(-1)), ['api-id', 'worker-id']);
  const report = result.checkpoints.at(-1);
  assert.equal(report.error, 'E_VERIFY');
  assert.deepEqual(report.containersRetained, ['api-id', 'worker-id']);
  assert.equal(report.cleanup[0].stopError, 'E_STOP');
  assert.equal(report.cleanup[1].stopped, true);
  assert.equal(report.status, 'failed');
});

test('log capture is bounded even on verification failure', async () => {
  const result = await scenario();
  const captures = result.calls.filter(c => c.args[0] === 'logs');
  assert.equal(captures.length, 2);
  for (const capture of captures) assert(capture.options.timeout > 0 && capture.options.timeout <= 15000);
});
