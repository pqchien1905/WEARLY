const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path"),
  os = require("node:os");
const ci = require("./ci-verify.cjs");
function project(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wearly-ci-test-"));
  fs.mkdirSync(path.join(root, "backend"));
  fs.mkdirSync(path.join(root, "frontend"));
  t.after(() => {
    function clean(dir) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const file = path.join(dir, entry.name);
        if (entry.isDirectory() && !entry.isSymbolicLink()) {
          clean(file);
          fs.rmdirSync(file);
        } else fs.unlinkSync(file);
      }
    }
    clean(root);
    fs.rmdirSync(root);
  });
  return root;
}
const input = () => ({
  NODE_ENV: "test",
  CI_DATABASE_URL:
    "postgresql://wearly_ci:ci-fixture-password-only@127.0.0.1:5432/wearly_ci_test",
  CI_REDIS_HOST: "127.0.0.1",
  CI_REDIS_PORT: "6379",
  CI_S3_ENDPOINT: "http://127.0.0.1:9000",
});
test("CI refuses existing user environment files without changing either file", (t) => {
  for (const name of [".env", ".env.test"]) {
    const root = project(t),
      file = path.join(root, "backend", name);
    fs.writeFileSync(file, "private-user-settings");
    assert.throws(
      () => ci.prepareEnvironment(root, input()),
      /CI_ENV_ALREADY_EXISTS/,
    );
    assert.equal(fs.readFileSync(file, "utf8"), "private-user-settings");
    assert.equal(fs.readdirSync(path.join(root, "backend")).length, 1);
  }
});
test("CI rejects business databases, remote services and configured providers before writes", (t) => {
  for (const patch of [
    {
      CI_DATABASE_URL:
        "postgresql://wearly_ci:ci-fixture-password-only@127.0.0.1:5432/wearly",
    },
    {
      CI_DATABASE_URL:
        "postgresql://wearly_ci:ci-fixture-password-only@remote.test:5432/wearly_ci_test",
    },
    { CI_REDIS_HOST: "remote.test" },
    { CI_S3_ENDPOINT: "https://remote.test" },
    { GEMINI_API_KEY: "private-fixture-key" },
    { VNPAY_ENABLED: "true" },
    { VNPAY_HASH_SECRET: "private-fixture-secret" },
    { NODE_ENV: "production" },
  ]) {
    const root = project(t);
    assert.throws(() => ci.prepareEnvironment(root, { ...input(), ...patch }));
    assert.deepEqual(fs.readdirSync(path.join(root, "backend")), []);
    assert(!fs.existsSync(path.join(root, ".tools")));
  }
});
test("prepared CI settings isolate test resources and disable outbound providers", (t) => {
  const root = project(t);
  ci.prepareEnvironment(root, input());
  const env = ci.readEnvironment(root);
  assert.equal(env.DATABASE_URL, env.TEST_DATABASE_URL);
  assert.equal(env.S3_BUCKET, "wearly-ci-test");
  assert.equal(env.GEMINI_API_KEY.trim(), "");
  assert.equal(env.VNPAY_ENABLED, "false");
  assert.equal(env.LOCAL_MAIL_ENABLED, "false");
  assert.equal(env.PASSWORD_RECOVERY_ENABLED, "false");
  assert.match(env.AI_QUEUE_PREFIX, /^ci-/);
  assert.notEqual(env.JWT_ACCESS_SECRET, env.JWT_REFRESH_SECRET);
});
test("modified prepared files invalidate CI before commands run", async (t) => {
  const root = project(t);
  ci.prepareEnvironment(root, input());
  fs.appendFileSync(
    path.join(root, "backend/.env"),
    "\nGEMINI_API_KEY=unexpected\n",
  );
  let calls = 0;
  await assert.rejects(
    ci.runStage(root, "backend", async () => {
      calls++;
    }),
    /CI_ENV_CHANGED/,
  );
  assert.equal(calls, 0);
});
test("CI stops at the first failed command and preserves the failure", async (t) => {
  const root = project(t);
  ci.prepareEnvironment(root, input());
  const calls = [];
  await assert.rejects(
    ci.runStage(root, "backend", async (binary, args, options) => {
      calls.push(args);
      assert.equal(options.env.GEMINI_API_KEY, " ");
      if (calls.length === 2) throw Error("synthetic build failure");
    }),
    /synthetic build failure/,
  );
  assert.equal(calls.length, 2);
  assert(!calls.some((args) => args.includes("test:e2e")));
});
test("backend migration and integration use only the prepared test environment", async (t) => {
  const root = project(t);
  ci.prepareEnvironment(root, input());
  const calls = [];
  await ci.runStage(root, "backend", async (binary, args, options) => {
    calls.push(args.at(-1));
    assert.equal(options.env.DATABASE_URL, input().CI_DATABASE_URL);
    assert.equal(options.env.TEST_REDIS_HOST, "127.0.0.1");
    assert.equal(options.env.TEST_S3_BUCKET, "wearly-ci-test");
  });
  assert(calls.indexOf("prisma:deploy") < calls.indexOf("test:e2e"));
  assert(calls.includes("test:e2e"));
});
test("CI tools path cannot escape through an existing junction", (t) => {
  const root = project(t),
    outside = project(t);
  fs.symlinkSync(outside, path.join(root, ".tools"), "junction");
  assert.throws(() => ci.prepareEnvironment(root, input()), /UNSAFE_CI_PATH/);
  assert.deepEqual(fs.readdirSync(path.join(root, "backend")), []);
  assert(!fs.existsSync(path.join(outside, "ci")));
});
