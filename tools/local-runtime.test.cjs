const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  http = require("node:http");
const { randomUUID, randomBytes } = require("node:crypto");
const runtime = require("./local-runtime.cjs");
const { startControl } = require("./local-runtime-child.cjs");

function workspace(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wearly-runtime-test-"));
  t.after(() => {
    // Delete only the exact test-owned files; no recursive filesystem deletion.
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
function identity(root, role = "api") {
  return {
    workspace: fs.realpathSync(root),
    runId: randomUUID(),
    role,
    secret: randomBytes(32).toString("hex"),
  };
}
async function controlled(t, root, options = {}) {
  const id = identity(root);
  let closes = 0;
  const control = await startControl(id, {
    status: () => ({ ready: true }),
    stop: async () => {
      closes++;
    },
    ...options,
  });
  t.after(() => control.close());
  return {
    state: {
      ...id,
      pid: process.pid,
      host: "127.0.0.1",
      controlPort: control.port,
    },
    closes: () => closes,
    control,
  };
}

test("status on an untouched workspace creates no runtime or tools files", async (t) => {
  const root = workspace(t),
    before = fs.readdirSync(root);
  assert.equal((await runtime.status(root)).status, "stopped");
  assert.deepEqual(fs.readdirSync(root), before);
});
test("forged identity and recycled PID cannot stop a live unrelated control server", async (t) => {
  const root = workspace(t),
    child = await controlled(t, root);
  for (const patch of [
    { secret: "0".repeat(64) },
    { runId: randomUUID() },
    { workspace: root + "-elsewhere" },
    { role: "worker" },
  ]) {
    await assert.rejects(
      runtime.controlRequest({ ...child.state, ...patch }, "stop"),
    );
    assert.equal(child.closes(), 0);
  }
  assert.equal(
    (await runtime.controlRequest(child.state, "status")).ready,
    true,
  );
  await runtime.controlRequest(child.state, "stop");
  assert.equal(child.closes(), 1);
});
test("control refuses browser origin and off-loopback state before disclosing its secret", async (t) => {
  const root = workspace(t),
    child = await controlled(t, root);
  const reply = await fetch(
    `http://127.0.0.1:${child.state.controlPort}/stop`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${child.state.secret}`,
        Origin: "http://untrusted.test",
        "X-Wearly-Run": child.state.runId,
        "X-Wearly-Role": "api",
        "X-Wearly-Workspace": Buffer.from(child.state.workspace).toString(
          "base64",
        ),
      },
    },
  );
  assert.equal(reply.status, 403);
  assert.equal(child.closes(), 0);
  await assert.rejects(
    runtime.controlRequest({ ...child.state, host: "example.test" }, "status"),
    /INVALID_RUNTIME_STATE/,
  );
});
test("runtime state rejects another workspace and symlink escape", async (t) => {
  const root = workspace(t),
    other = workspace(t),
    loc = runtime.locations(root, true);
  assert.throws(
    () =>
      runtime.saveState(loc, {
        workspace: other,
        runId: randomUUID(),
        children: [],
      }),
    /INVALID_RUNTIME_STATE/,
  );
  fs.rmdirSync(loc.directory);
  fs.symlinkSync(other, loc.directory, "junction");
  assert.throws(() => runtime.locations(root, true), /UNSAFE_RUNTIME_PATH/);
  assert.deepEqual(fs.readdirSync(other), []);
});
test("an occupied foreign listener is refused and left running", async (t) => {
  const server = http.createServer((_req, res) => res.end("foreign"));
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  t.after(() => new Promise((r) => server.close(r)));
  const port = server.address().port;
  await assert.rejects(runtime.assertPortAvailable(port), /LOCAL_PORT_IN_USE/);
  assert.equal(
    await (await fetch(`http://127.0.0.1:${port}`)).text(),
    "foreign",
  );
});

test("a recycled control port never receives a destructive request before identity verification", async (t) => {
  const root = workspace(t);
  let stops = 0;
  const server = http.createServer((req, res) => {
    if (req.method === "POST" && req.url === "/stop") stops++;
    res.end("{}");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const state = {
    ...identity(root),
    pid: process.pid,
    host: "127.0.0.1",
    controlPort: server.address().port,
  };
  await assert.rejects(runtime.controlRequest(state, "stop"));
  assert.equal(stops, 0);
});

test("stop refuses a new connection after the verified listener closes its socket", async (t) => {
  const root = workspace(t),
    id = identity(root);
  let stops = 0;
  const server = http.createServer((req, res) => {
    if (req.method === "POST") stops++;
    res.setHeader("Connection", "close");
    res.end(
      JSON.stringify({
        ...id,
        secret: undefined,
        pid: process.pid,
        ready: true,
      }),
    );
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const state = {
    ...id,
    pid: process.pid,
    host: "127.0.0.1",
    controlPort: server.address().port,
  };
  await assert.rejects(runtime.controlRequest(state, "stop"));
  assert.equal(stops, 0);
});
test("nonzero native command exits fail instead of reporting a successful build", async () => {
  await assert.rejects(
    runtime.runCommand(process.execPath, ["-e", "process.exit(17)"], {
      cwd: __dirname,
    }),
    /COMMAND_FAILED.*17/,
  );
});
test("build commands use the selected Node toolchain ahead of the inherited PATH", async (t) => {
  const root = workspace(t),
    file = path.join(root, "path.txt");
  await runtime.runCommand(
    process.execPath,
    [
      "-e",
      "require('node:fs').writeFileSync(process.argv[1],process.env.PATH)",
      file,
    ],
    { cwd: root, env: { ...process.env, PATH: "inherited-fixture-path" } },
  );
  assert.equal(
    fs.readFileSync(file, "utf8").split(path.delimiter)[0],
    path.dirname(process.execPath),
  );
});
test("a partially failed launch stops only this run and retains other owned processes", async (t) => {
  const root = workspace(t),
    foreign = await controlled(t, root),
    created = [];
  await assert.rejects(
    runtime.start(
      root,
      { apiPort: 13001, webPort: 13002 },
      {
        prepare: async () => ({ env: {}, build: {} }),
        portCheck: async () => {},
        launch: async (context) => {
          if (context.role === "worker") throw Error("WORKER_FIXTURE_FAILED");
          const child = await startControl(context, {
            status: () => ({ ready: true }),
            stop: async () => {
              created.push("stopped");
            },
          });
          t.after(() => child.close());
          return {
            ...context,
            pid: process.pid,
            host: "127.0.0.1",
            controlPort: child.port,
          };
        },
      },
    ),
    /WORKER_FIXTURE_FAILED/,
  );
  assert.deepEqual(created, ["stopped"]);
  assert.equal(foreign.closes(), 0);
  assert.equal((await runtime.status(root)).status, "stopped");
});
test("unreachable stale state is never treated as verified or used for PID termination", async (t) => {
  const root = workspace(t),
    loc = runtime.locations(root, true),
    id = identity(root);
  runtime.saveState(loc, {
    workspace: loc.workspace,
    runId: id.runId,
    children: [{ ...id, pid: process.pid, host: "127.0.0.1", controlPort: 1 }],
  });
  assert.equal((await runtime.status(root)).status, "unverified");
  const stopped = await runtime.stop(root);
  assert.equal(stopped.status, "unverified");
  assert(fs.existsSync(loc.stateFile));
});
test("native child configuration is local, consistent and leaves source settings intact", () => {
  const input = {
    NODE_ENV: "development",
    DATABASE_URL: "postgresql://fixture:synthetic@localhost:5432/local_test",
    REDIS_HOST: "127.0.0.1",
    S3_ENDPOINT: "http://127.0.0.1:9000",
    CORS_ORIGINS: "http://localhost:5173",
    PASSWORD_RESET_WEB_URL: "http://localhost:5173/#/reset-password",
  };
  const before = JSON.stringify(input),
    configured = runtime.configure(input, { apiPort: 13001, webPort: 13002 });
  assert.equal(configured.HOST, "127.0.0.1");
  assert.equal(configured.PORT, 13001);
  assert.equal(configured.CORS_ORIGINS, "http://localhost:13002");
  assert.equal(
    configured.PASSWORD_RESET_WEB_URL,
    "http://localhost:13002/#/reset-password",
  );
  assert.equal(
    configured.VNPAY_RETURN_URL,
    "http://localhost:13001/api/v1/payments/vnpay/return",
  );
  assert.equal(JSON.stringify(input), before);
  for (const patch of [
    { DATABASE_URL: "postgresql://fixture:synthetic@remote.test/db" },
    { REDIS_HOST: "remote.test" },
    { S3_ENDPOINT: "https://remote.test" },
    { NODE_ENV: "production" },
  ])
    assert.throws(
      () =>
        runtime.configure(
          { ...input, ...patch },
          { apiPort: 13001, webPort: 13002 },
        ),
      /LOCAL_CONFIGURATION_REQUIRED/,
    );
});
test("native recovery preserves external SMTP while local plaintext stays loopback-only", () => {
  const input = {
    DATABASE_URL: "postgresql://fixture:synthetic@localhost:5432/fixture_test",
    REDIS_HOST: "localhost",
    S3_ENDPOINT: "http://127.0.0.1:9000",
    PASSWORD_RECOVERY_ENABLED: "true",
    LOCAL_MAIL_ENABLED: "false",
    SMTP_HOST: "smtp.example.com",
    SMTP_PORT: "465",
    SMTP_SECURE: "true",
    SMTP_ALLOW_INSECURE_LOCAL: "false",
    SMTP_USER: "fixture@example.com",
    SMTP_PASSWORD: "synthetic-test-only",
  };
  const options = { apiPort: 13001, webPort: 13002 };
  const configured = runtime.configure(input, options);
  for (const key of [
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_SECURE",
    "SMTP_USER",
    "SMTP_PASSWORD",
  ])
    assert.equal(configured[key], input[key]);
  for (const patch of [
    { LOCAL_MAIL_ENABLED: "true" },
    { SMTP_ALLOW_INSECURE_LOCAL: "true" },
  ])
    assert.throws(
      () => runtime.configure({ ...input, ...patch }, options),
      /LOCAL_CONFIGURATION_REQUIRED/,
    );
  assert.doesNotThrow(() =>
    runtime.configure(
      {
        ...input,
        SMTP_HOST: "127.0.0.1",
        SMTP_ALLOW_INSECURE_LOCAL: "true",
      },
      options,
    ),
  );
});
test("changed compiled assets and a different API origin require a fresh runtime build", async (t) => {
  const root = workspace(t),
    loc = runtime.locations(root, true);
  fs.mkdirSync(path.join(root, "backend"));
  fs.mkdirSync(path.join(root, "backend/dist"));
  fs.mkdirSync(path.join(root, "frontend"));
  fs.mkdirSync(path.join(root, "frontend/build"));
  fs.mkdirSync(path.join(root, "frontend/build/web"));
  fs.writeFileSync(path.join(root, "backend/dist/app.module.js"), "fixture");
  fs.writeFileSync(
    path.join(root, "frontend/build/web/main.dart.js"),
    "fixture",
  );
  runtime.recordBuild(loc, 13001);
  assert(runtime.verifyBuild(loc, 13001));
  assert.throws(() => runtime.verifyBuild(loc, 13003), /LOCAL_BUILD_REQUIRED/);
  fs.writeFileSync(
    path.join(root, "frontend/build/web/main.dart.js"),
    "other browser fixture",
  );
  assert.throws(() => runtime.verifyBuild(loc, 13001), /LOCAL_BUILD_REQUIRED/);
});
test("runtime logs allow only known event codes and rotate bounded files", async (t) => {
  const root = workspace(t),
    loc = runtime.locations(root, true),
    log = runtime.createLogger(loc, "api"),
    file = path.join(loc.directory, "api.log");
  log("LOCAL_CHILD_READY");
  log("SUPERPRIVATEAPIKEYVALUE");
  log("postgresql://private-secret");
  const content = fs.readFileSync(file, "utf8");
  assert.match(content, /LOCAL_CHILD_READY/);
  assert(!content.includes("SUPERPRIVATE"));
  assert(!content.includes("private-secret"));
  fs.writeFileSync(file, "x".repeat(1024 * 1024 + 1));
  log("LOCAL_CHILD_STOPPED");
  assert(fs.statSync(file).size < 1024);
  assert(fs.existsSync(file + ".1"));
});
test("failed shutdown remains observable instead of claiming the app stopped", async (t) => {
  const root = workspace(t),
    child = await controlled(t, root, {
      stop: async () => {
        throw Error("synthetic close failure");
      },
    });
  await runtime.controlRequest(child.state, "stop");
  assert.equal(
    (await runtime.controlRequest(child.state, "status")).ready,
    false,
  );
});
test("a child failing readiness is stopped and cannot produce a successful start", async (t) => {
  const root = workspace(t);
  let closed = 0;
  await assert.rejects(
    runtime.start(
      root,
      { apiPort: 13001, webPort: 13002 },
      {
        prepare: async () => ({ env: {} }),
        portCheck: async () => {},
        launch: async (identity) => {
          const control = await startControl(identity, {
            status: () => ({ ready: false }),
            stop: async () => {
              closed++;
            },
          });
          t.after(() => control.close());
          return {
            ...identity,
            pid: process.pid,
            host: "127.0.0.1",
            controlPort: control.port,
          };
        },
      },
    ),
    /LOCAL_CHILD_NOT_READY/,
  );
  assert.equal(closed, 1);
  assert.equal((await runtime.status(root)).status, "stopped");
});
