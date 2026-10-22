// Start/stop the real compiled applications against dedicated synthetic services.
const fs = require("node:fs"),
  path = require("node:path"),
  net = require("node:net"),
  assert = require("node:assert/strict");
const { createRequire } = require("node:module"),
  { randomUUID, createHash } = require("node:crypto");
const runtime = require("./local-runtime.cjs");
const root = path.resolve(__dirname, ".."),
  req = createRequire(path.join(root, "backend/package.json"));
const digest = (file) =>
  createHash("sha256").update(fs.readFileSync(file)).digest("hex");
async function freePort() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  await runtime.assertPortAvailable(port);
  return port;
}
async function main() {
  const normalFile = path.join(root, "backend/.env"),
    before = digest(normalFile),
    dotenv = req("dotenv");
  const normal = dotenv.parse(fs.readFileSync(normalFile)),
    test = dotenv.parse(fs.readFileSync(path.join(root, "backend/.env.test"))),
    target = new URL(test.TEST_DATABASE_URL);
  if (
    !/^\/[a-zA-Z0-9_]+_test$/.test(target.pathname) ||
    target.href === new URL(normal.DATABASE_URL).href
  )
    throw Error("DEDICATED_TEST_DATABASE_REQUIRED");
  assert.equal(
    (await runtime.status(root)).status,
    "stopped",
    "An existing recorded runtime must be handled by its operator.",
  );
  const loc = runtime.locations(root, true),
    run = randomUUID(),
    envFile = path.join(loc.directory, "acceptance-" + run + ".env");
  const env = {
    ...normal,
    NODE_ENV: "test",
    DATABASE_URL: target.href,
    REDIS_HOST: test.TEST_REDIS_HOST || normal.REDIS_HOST,
    REDIS_PORT: test.TEST_REDIS_PORT || normal.REDIS_PORT,
    S3_ENDPOINT: test.TEST_S3_ENDPOINT || normal.S3_ENDPOINT,
    S3_PUBLIC_ENDPOINT: "",
    S3_BUCKET: test.TEST_S3_BUCKET || normal.S3_BUCKET + "-test",
    AI_QUEUE_PREFIX: "runtime-test-" + run,
    JWT_ACCESS_SECRET: randomUUID() + randomUUID(),
    JWT_REFRESH_SECRET: randomUUID() + randomUUID(),
    GEMINI_API_KEY: " ",
    VNPAY_ENABLED: "false",
    LOCAL_MAIL_ENABLED: "false",
    PASSWORD_RECOVERY_ENABLED: "false",
  };
  if (!env.S3_BUCKET.endsWith("-test") || env.S3_BUCKET === normal.S3_BUCKET)
    throw Error("DEDICATED_TEST_BUCKET_REQUIRED");
  const lock = new (req("pg").Client)({ connectionString: target.href });
  await lock.connect();
  let started = false,
    apiPort,
    webPort;
  try {
    const result = await lock.query(
      "SELECT pg_try_advisory_lock(hashtext($1)) AS locked",
      ["wearly-worker-e2e"],
    );
    if (!result.rows[0].locked) throw Error("ANOTHER_TEST_WORKER_ACTIVE");
    const pending = await lock.query(
      `SELECT EXISTS(SELECT 1 FROM public."OutboxEvent" WHERE "publishedAt" IS NULL) OR EXISTS(SELECT 1 FROM public."AIJob" WHERE status IN ('PENDING','PROCESSING')) AS pending`,
    );
    if (pending.rows[0].pending) throw Error("INSPECT_UNFINISHED_TEST_AI_JOBS");
    fs.writeFileSync(
      envFile,
      Object.entries(env)
        .map(([key, value]) => `${key}=${JSON.stringify(String(value))}`)
        .join("\n"),
      { flag: "wx", mode: 0o600 },
    );
    const reuse = process.argv.includes("--reuse-build");
    if (reuse) {
      const manifest = JSON.parse(fs.readFileSync(loc.buildFile, "utf8"));
      apiPort = Number(new URL(manifest.apiUrl).port);
      runtime.verifyBuild(loc, apiPort);
      await runtime.assertPortAvailable(apiPort);
    } else apiPort = await freePort();
    webPort = await freePort();
    assert.notEqual(apiPort, webPort);
    if (!reuse) await runtime.build(root, { apiPort });
    // An actual unavailable dependency must fail before any managed child exists.
    const broken = { ...env, REDIS_PORT: "1" };
    fs.writeFileSync(
      envFile,
      Object.entries(broken)
        .map(([key, value]) => `${key}=${JSON.stringify(String(value))}`)
        .join("\n"),
    );
    await assert.rejects(
      runtime.start(root, { apiPort, webPort, envFile }),
      /LOCAL_DEPENDENCY_UNAVAILABLE/,
    );
    assert.equal((await runtime.status(root)).status, "stopped");
    fs.writeFileSync(
      envFile,
      Object.entries(env)
        .map(([key, value]) => `${key}=${JSON.stringify(String(value))}`)
        .join("\n"),
    );
    const running = await runtime.start(root, { apiPort, webPort, envFile });
    started = true;
    assert.equal(running.status, "running");
    assert.equal((await runtime.status(root)).children.length, 3);
    const ready = await fetch(
      `http://127.0.0.1:${apiPort}/api/v1/health/ready`,
    );
    assert.equal(ready.status, 200);
    assert.equal((await ready.json()).status, "ready");
    assert.equal(
      (await fetch(`http://127.0.0.1:${apiPort}/api/v1/products`)).status,
      200,
    );
    assert.equal(
      (await fetch(`http://127.0.0.1:${apiPort}/api/v1/admin/operations`))
        .status,
      401,
    );
    const web = await fetch(`http://127.0.0.1:${webPort}`);
    assert.equal(web.status, 200);
    assert.match(web.headers.get("x-robots-tag"), /noindex/);
    assert.match(await web.text(), /flutter_bootstrap/);
    const { OperationsProbes, operationsResources } = req(
      "./dist/modules/operations/operations.probes",
    );
    const config = new (req("@nestjs/config").ConfigService)(
      req("./dist/config/env.validation").validateEnv(
        runtime.configure(env, { apiPort, webPort }),
      ),
    );
    const probes = new OperationsProbes(config, operationsResources);
    assert.equal((await probes.redis()).worker.status, "ok");
    const recorded = runtime.readState(loc);
    assert(recorded.children.every((child) => !("env" in child)));
    const stopped = await runtime.stop(root);
    assert.equal(stopped.status, "stopped");
    started = false;
    assert.equal((await runtime.status(root)).status, "stopped");
    await runtime.assertPortAvailable(apiPort);
    await runtime.assertPortAvailable(webPort);
    assert.equal((await probes.redis()).worker.status, "unavailable");
    assert.equal((await probes.database()).database.schemaReady, true);
    assert.equal((await probes.storage()).status, "ok");
    assert.equal(digest(normalFile), before);
    const resultData = {
      checkedAt: new Date().toISOString(),
      apiPort,
      webPort,
      status: "passed",
      schemaReady: true,
      workerHeartbeatRemoved: true,
      dependenciesStillAvailable: true,
      environmentUnchanged: true,
      externalProvidersDisabled: true,
    };
    runtime.atomicJson(
      loc,
      path.join(loc.directory, "acceptance.json"),
      resultData,
    );
    console.log(
      "PASS native runtime: compiled API/worker/web, authenticated status/stop, heartbeat cleanup, loopback ports released, native services and backend/.env preserved.",
    );
  } finally {
    if (started) await runtime.stop(root);
    if (fs.existsSync(envFile)) fs.unlinkSync(envFile);
    await lock.end();
  }
}
main().catch((error) => {
  console.error(
    /^[A-Z][A-Z0-9_]+$/.test(error.message)
      ? error.message
      : "LOCAL_RUNTIME_ACCEPTANCE_FAILED",
  );
  process.exitCode = 1;
});
