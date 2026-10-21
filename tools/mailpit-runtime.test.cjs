const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { buildOptions } = require('./mailpit-runtime.cjs');
test('local inbox binds only loopback and cannot inherit mail forwarding, relay or webhook configuration', () => {
  const folder = path.resolve('.tools/mailpit');
  const result = buildOptions(path.join(folder,'mailpit.exe'), folder, {
    PATH:'system-path', MP_SMTP_RELAY_ALL:'true', mp_smtp_forward_config:'remote.yml',
    MP_WEBHOOK_URL:'https://example.test/capture', MP_UI_BIND_ADDR:'0.0.0.0:8025', MP_API_CORS:'*',
  });
  const flag = name => result.args[result.args.indexOf(name)+1];
  assert.equal(flag('--listen'),'127.0.0.1:8025');
  assert.equal(flag('--smtp'),'127.0.0.1:1025');
  assert.equal(flag('--database'),path.join(folder,'mailpit.db'));
  assert.equal(flag('--allowed-hosts'),'localhost,127.0.0.1');
  assert(result.args.includes('--disable-version-check'));
  assert(result.args.includes('--ignore-duplicate-ids'));
  assert.deepEqual(result.options.env,{PATH:'system-path'});
  assert.equal(result.options.windowsHide,true);
  assert(!result.args.some(a=>/relay|forward|webhook/.test(a)));
});
