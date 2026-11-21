const fs = require("node:fs");
const path = require("node:path");
const net = require("node:net");
const http = require("node:http");
const { createHash, randomUUID, randomBytes } = require("node:crypto");
const { spawn } = require("node:child_process");
const { createRequire } = require("node:module");

const roles = ["api", "worker", "web"];
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const fail = (code) => {
  throw Error(code);
};
const exists = (file) => {
  try {
    return fs.lstatSync(file);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
};
const inside = (parent, file) => {
  const relative = path.relative(parent, file);
  return (
    relative === "" ||
    (!relative.startsWith(".." + path.sep) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  );
};
function directory(file, create) {
  const stat = exists(file);
  if (stat && (stat.isSymbolicLink() || !stat.isDirectory()))
    fail("UNSAFE_RUNTIME_PATH");
  if (!stat && create) fs.mkdirSync(file);
}
function regularFile(file) {
  const stat = exists(file);
  if (stat && (stat.isSymbolicLink() || !stat.isFile()))
    fail("UNSAFE_RUNTIME_PATH");
  return stat;
}
function locations(root, create = false) {
  const workspace = fs.realpathSync(root),
    candidate = path.join(workspace, ".tools");
  const stat = exists(candidate);
  let tools = candidate;
  if (stat?.isSymbolicLink()) {
    // A Git worktree's shared .tools junction is intentional; arbitrary junctions are not.
    const git = path.join(workspace, ".git");
    if (!regularFile(git)) fail("UNSAFE_RUNTIME_PATH");
    const entry = fs.readFileSync(git, "utf8").trim();
    if (!entry.startsWith("gitdir: ")) fail("UNSAFE_RUNTIME_PATH");
    const gitDir = path.resolve(workspace, entry.slice(8));
    const common = fs.realpathSync(
      path.resolve(
        gitDir,
        fs.readFileSync(path.join(gitDir, "commondir"), "utf8").trim(),
      ),
    );
    tools = fs.realpathSync(candidate);
    if (tools !== fs.realpathSync(path.join(path.dirname(common), ".tools")))
      fail("UNSAFE_RUNTIME_PATH");
  } else directory(tools, create);
  const base = path.join(tools, "runtime");
  const scoped = path.join(
    base,
    createHash("sha256").update(workspace).digest("hex").slice(0, 20),
  );
  directory(base, create);
  directory(scoped, create);
  return {
    workspace,
    directory: scoped,
    stateFile: path.join(scoped, "runtime.json"),
    lockFile: path.join(scoped, "operation.lock"),
    buildFile: path.join(scoped, "build.json"),
  };
}
function validIdentity(value) {
  if (
    !value ||
    typeof value.workspace !== "string" ||
    !path.isAbsolute(value.workspace) ||
    !uuid.test(value.runId) ||
    !roles.includes(value.role) ||
    !/^[a-f0-9]{64}$/.test(value.secret)
  )
    fail("INVALID_RUNTIME_STATE");
}
function validChild(value) {
  validIdentity(value);
  if (
    value.host !== "127.0.0.1" ||
    !Number.isInteger(value.controlPort) ||
    value.controlPort < 1 ||
    value.controlPort > 65535 ||
    !Number.isInteger(value.pid) ||
    value.pid < 1
  )
    fail("INVALID_RUNTIME_STATE");
}
function validateState(loc, state) {
  if (
    !state ||
    state.workspace !== loc.workspace ||
    !uuid.test(state.runId) ||
    !Array.isArray(state.children) ||
    state.children.length > 3
  )
    fail("INVALID_RUNTIME_STATE");
  const seen = new Set();
  for (const child of state.children) {
    validChild(child);
    if (
      child.workspace !== state.workspace ||
      child.runId !== state.runId ||
      seen.has(child.role)
    )
      fail("INVALID_RUNTIME_STATE");
    seen.add(child.role);
  }
  return state;
}
function readJson(file) {
  const stat = regularFile(file);
  if (!stat) return null;
  if (stat.size > 32768) fail("INVALID_RUNTIME_STATE");
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    fail("INVALID_RUNTIME_STATE");
  }
}
function atomicJson(loc, file, value) {
  locations(loc.workspace, true);
  if (!inside(loc.directory, file) || path.dirname(file) !== loc.directory)
    fail("UNSAFE_RUNTIME_PATH");
  regularFile(file);
  const temporary = path.join(loc.directory, randomUUID() + ".tmp");
  try {
    fs.writeFileSync(temporary, JSON.stringify(value, null, 2), {
      flag: "wx",
      mode: 0o600,
    });
    fs.renameSync(temporary, file);
  } finally {
    if (regularFile(temporary)) fs.unlinkSync(temporary);
  }
}
function saveState(loc, state) {
  validateState(loc, state);
  atomicJson(loc, loc.stateFile, state);
}
function readState(loc) {
  const state = readJson(loc.stateFile);
  return state ? validateState(loc, state) : null;
}
function removeState(loc, runId) {
  if (readState(loc)?.runId === runId) fs.unlinkSync(loc.stateFile);
}
async function locked(root, work) {
  const loc = locations(root, true),
    nonce = randomUUID();
  regularFile(loc.lockFile);
  try {
    fs.writeFileSync(loc.lockFile, nonce, { flag: "wx", mode: 0o600 });
  } catch (error) {
    if (error.code === "EEXIST") fail("LOCAL_OPERATION_IN_PROGRESS");
    throw error;
  }
  try {
    return await work(loc);
  } finally {
    if (
      regularFile(loc.lockFile) &&
      fs.readFileSync(loc.lockFile, "utf8") === nonce
    )
      fs.unlinkSync(loc.lockFile);
  }
}
async function controlRequest(child, action) {
  validChild(child);
  if (!["status", "stop"].includes(action)) fail("INVALID_RUNTIME_ACTION");
  const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
  const send = (operation, expectedSocket) =>
    new Promise((resolve, reject) => {
      let connection;
      const request = http.request(
        {
          hostname: "127.0.0.1",
          port: child.controlPort,
          path: `/${operation}`,
          method: operation === "stop" ? "POST" : "GET",
          agent,
          signal: AbortSignal.timeout(2000),
          headers: {
            Authorization: `Bearer ${child.secret}`,
            "X-Wearly-Run": child.runId,
            "X-Wearly-Role": child.role,
            "X-Wearly-Workspace": Buffer.from(child.workspace).toString(
              "base64",
            ),
          },
        },
        (response) => {
          if (response.statusCode < 200 || response.statusCode >= 300) {
            response.destroy();
            reject(Error("CONTROL_UNVERIFIED"));
            return;
          }
          const chunks = [];
          let size = 0;
          response.on("data", (chunk) => {
            size += chunk.length;
            if (size > 8192) {
              response.destroy();
              reject(Error("CONTROL_UNVERIFIED"));
            } else chunks.push(chunk);
          });
          response.on("error", () => reject(Error("CONTROL_UNVERIFIED")));
          response.on("aborted", () => reject(Error("CONTROL_UNVERIFIED")));
          response.on("end", () => {
            try {
              const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
              if (
                result.workspace !== child.workspace ||
                result.runId !== child.runId ||
                result.role !== child.role ||
                result.pid !== child.pid ||
                typeof result.ready !== "boolean"
              )
                fail("CONTROL_UNVERIFIED");
              resolve({
                result,
                socket: connection,
                keepAlive:
                  response.headers.connection?.toLowerCase() !== "close",
              });
            } catch {
              reject(Error("CONTROL_UNVERIFIED"));
            }
          });
        },
      );
      request.on("error", (error) =>
        reject(Error("CONTROL_UNVERIFIED", { cause: error })),
      );
      request.once("socket", (socket) => {
        connection = socket;
        // Never transmit a stop to a replacement connection, even if the port is reused.
        if (expectedSocket && (socket !== expectedSocket || socket.destroyed)) {
          request.destroy(Error("CONTROL_UNVERIFIED"));
          return;
        }
        request.end();
      });
    });
  try {
    const verified = await send("status");
    if (action === "status") return verified.result;
    if (!verified.keepAlive || verified.socket.destroyed)
      fail("CONTROL_UNVERIFIED");
    // Let Agent release the completed GET before requesting that exact socket.
    await new Promise((resolve) => setImmediate(resolve));
    return (await send("stop", verified.socket)).result;
  } finally {
    agent.destroy();
  }
}
async function status(root) {
  const loc = locations(root),
    state = readState(loc);
  if (!state || !state.children.length)
    return { status: "stopped", children: [] };
  const children = await Promise.all(
    state.children.map(async (child) => {
      try {
        const reply = await controlRequest(child, "status");
        return {
          role: child.role,
          pid: child.pid,
          status: reply.ready ? "ready" : "starting-or-stopping",
        };
      } catch {
        return { role: child.role, pid: child.pid, status: "unverified" };
      }
    }),
  );
  return {
    status: children.some((child) => child.status === "unverified")
      ? "unverified"
      : children.length === 3 &&
          children.every((child) => child.status === "ready")
        ? "running"
        : "partial",
    children,
  };
}
const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
async function stopChildren(children) {
  const results = await Promise.all(
    children.map(async (child) => {
      try {
        if (child.exited?.()) return { role: child.role, status: "stopped" };
        await controlRequest(child, "stop");
        const deadline = Date.now() + 155000;
        while (Date.now() < deadline) {
          await delay(100);
          try {
            await controlRequest(child, "status");
          } catch (error) {
            if (child.exited?.() || error.cause?.code === "ECONNREFUSED")
              return { role: child.role, status: "stopped" };
            // A timeout or an identity mismatch is not evidence of termination.
          }
        }
        return { role: child.role, status: "unverified" };
      } catch {
        return { role: child.role, status: "unverified" };
      }
    }),
  );
  return results;
}
async function stop(root) {
  // No state means a read-only no-op; do not create directories for an unused runtime.
  const initial = readState(locations(root));
  if (!initial || !initial.children.length)
    return { status: "stopped", children: [] };
  return locked(root, async (loc) => {
    const state = readState(loc);
    if (!state) return { status: "stopped", children: [] };
    const children = await stopChildren(state.children);
    const stopped = children.every((child) => child.status === "stopped");
    if (stopped) removeState(loc, state.runId);
    return { status: stopped ? "stopped" : "unverified", children };
  });
}
function port(value) {
  if (!Number.isInteger(value) || value < 1 || value > 65535)
    fail("INVALID_LOCAL_PORT");
  return value;
}
async function assertPortAvailable(value) {
  port(value);
  for (const host of ["127.0.0.1", "::1"])
    await new Promise((resolve, reject) => {
      const server = net.createServer();
      server.once("error", (error) => {
        if (
          host === "::1" &&
          ["EAFNOSUPPORT", "EADDRNOTAVAIL"].includes(error.code)
        )
          resolve();
        else reject(Error("LOCAL_PORT_IN_USE"));
      });
      server.listen({ port: value, host, exclusive: true }, () =>
        server.close(resolve),
      );
    });
}
async function start(root, options = {}, dependencies = {}) {
  const apiPort = port(options.apiPort ?? 3000),
    webPort = port(options.webPort ?? 8080);
  if (apiPort === webPort) fail("INVALID_LOCAL_PORT");
  return locked(root, async (loc) => {
    if (readState(loc)?.children.length) fail("LOCAL_RUNTIME_ALREADY_RECORDED");
    const config = await (dependencies.prepare ?? prepare)(loc, {
      ...options,
      apiPort,
      webPort,
    });
    await (dependencies.portCheck ?? assertPortAvailable)(apiPort);
    await (dependencies.portCheck ?? assertPortAvailable)(webPort);
    const state = {
      workspace: loc.workspace,
      runId: randomUUID(),
      children: [],
    };
    try {
      for (const role of roles) {
        const identity = {
          workspace: loc.workspace,
          runId: state.runId,
          role,
          secret: randomBytes(32).toString("hex"),
        };
        const child = await (dependencies.launch ?? launch)(identity, config, {
          apiPort,
          webPort,
        });
        state.children.push(child);
        saveState(loc, state);
        // The child can survive parent exit only after its authenticated control is recorded.
        await child.owned?.();
        delete child.owned;
        saveState(loc, state);
        const ready = await controlRequest(child, "status");
        if (!ready.ready) fail("LOCAL_CHILD_NOT_READY");
      }
      return {
        status: "running",
        apiUrl: `http://localhost:${apiPort}/api/v1`,
        webUrl: `http://localhost:${webPort}`,
        children: state.children.map((child) => ({
          role: child.role,
          pid: child.pid,
          status: "ready",
        })),
      };
    } catch (error) {
      const result = await stopChildren(state.children);
      if (result.every((child) => child.status === "stopped"))
        removeState(loc, state.runId);
      throw error;
    }
  });
}
function runCommand(binary, args, options = {}) {
  const env = { ...(options.env ?? process.env) };
  const inheritedPath = env.PATH ?? env.Path ?? "";
  for (const key of Object.keys(env))
    if (key.toLowerCase() === "path") delete env[key];
  env.PATH = path.dirname(process.execPath) + path.delimiter + inheritedPath;
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, {
      ...options,
      env,
      stdio: options.stdio ?? "inherit",
      windowsHide: true,
    });
    child.once("error", () => reject(Error("COMMAND_FAILED_SPAWN")));
    child.once("exit", (code) =>
      code === 0 ? resolve() : reject(Error("COMMAND_FAILED_" + code)),
    );
  });
}
const localHost = (host) =>
  ["localhost", "127.0.0.1", "::1", "[::1]"].includes(host);
function configure(input, options) {
  const apiPort = port(options.apiPort),
    webPort = port(options.webPort);
  try {
    const db = new URL(input.DATABASE_URL),
      storage = new URL(input.S3_ENDPOINT);
    if (
      !["development", "test", undefined].includes(input.NODE_ENV) ||
      !["postgres:", "postgresql:"].includes(db.protocol) ||
      !localHost(db.hostname) ||
      !localHost(input.REDIS_HOST) ||
      !localHost(storage.hostname) ||
      !["http:", "https:"].includes(storage.protocol) ||
      storage.username ||
      storage.password ||
      storage.search ||
      storage.hash
    )
      fail("LOCAL_CONFIGURATION_REQUIRED");
    if (input.S3_PUBLIC_ENDPOINT) {
      const publicUrl = new URL(input.S3_PUBLIC_ENDPOINT);
      if (
        !localHost(publicUrl.hostname) ||
        !["http:", "https:"].includes(publicUrl.protocol) ||
        publicUrl.username ||
        publicUrl.password
      )
        fail("LOCAL_CONFIGURATION_REQUIRED");
    }
    if (
      (input.LOCAL_MAIL_ENABLED === "true" ||
        (input.PASSWORD_RECOVERY_ENABLED === "true" &&
          input.SMTP_ALLOW_INSECURE_LOCAL === "true")) &&
      !localHost(input.SMTP_HOST)
    )
      fail("LOCAL_CONFIGURATION_REQUIRED");
    // Recovery may use the configured external SMTP server. prepare() still
    // validates its settings; plaintext/local-mail mode stays loopback-only.
  } catch {
    fail("LOCAL_CONFIGURATION_REQUIRED");
  }
  return {
    ...input,
    NODE_ENV: input.NODE_ENV ?? "development",
    HOST: "127.0.0.1",
    PORT: apiPort,
    CORS_ORIGINS: `http://localhost:${webPort}`,
    PASSWORD_RESET_WEB_URL: `http://localhost:${webPort}/#/reset-password`,
    VNPAY_RETURN_URL: `http://localhost:${apiPort}/api/v1/payments/vnpay/return`,
    VNPAY_WEB_RETURN_URL: `http://localhost:${webPort}/#/payments/return`,
  };
}
function fingerprint(root) {
  const digest = createHash("sha256");
  function visit(folder) {
    directory(folder, false);
    if (!exists(folder)) fail("LOCAL_BUILD_REQUIRED");
    for (const entry of fs
      .readdirSync(folder, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(folder, entry.name);
      if (entry.isSymbolicLink()) fail("UNSAFE_RUNTIME_PATH");
      if (entry.isDirectory()) visit(file);
      else {
        regularFile(file);
        digest.update(path.relative(root, file).replaceAll(path.sep, "/"));
        digest.update(fs.readFileSync(file));
      }
    }
  }
  visit(root);
  return digest.digest("hex");
}
function recordBuild(loc, apiPort) {
  atomicJson(loc, loc.buildFile, {
    workspace: loc.workspace,
    apiUrl: `http://localhost:${port(apiPort)}/api/v1`,
    builtAt: new Date().toISOString(),
    backend: fingerprint(path.join(loc.workspace, "backend/dist")),
    web: fingerprint(path.join(loc.workspace, "frontend/build/web")),
  });
}
function verifyBuild(loc, apiPort) {
  const build = readJson(loc.buildFile);
  if (
    !build ||
    build.workspace !== loc.workspace ||
    build.apiUrl !== `http://localhost:${port(apiPort)}/api/v1` ||
    build.backend !== fingerprint(path.join(loc.workspace, "backend/dist")) ||
    build.web !== fingerprint(path.join(loc.workspace, "frontend/build/web"))
  )
    fail("LOCAL_BUILD_REQUIRED");
  return build;
}
async function build(root, options = {}) {
  const apiPort = port(options.apiPort ?? 3000);
  return locked(root, async (loc) => {
    if (readState(loc)?.children.length)
      fail("STOP_LOCAL_RUNTIME_BEFORE_BUILD");
    if (Number(process.versions.node.split(".")[0]) !== 24)
      fail("NODE_24_REQUIRED");
    const npm = path.join(
      path.dirname(process.execPath),
      "node_modules/npm/bin/npm-cli.js",
    );
    if (!regularFile(npm)) fail("NPM_CLI_NOT_FOUND");
    await runCommand(process.execPath, [npm, "run", "build"], {
      cwd: path.join(loc.workspace, "backend"),
    });
    const flutter = path.join(loc.workspace, ".tools/flutter/bin/flutter.bat");
    if (process.platform !== "win32") fail("USE_NATIVE_WINDOWS_RUNTIME");
    if (!regularFile(flutter) || /["%!\r\n]/.test(flutter))
      fail("FLUTTER_PATH_UNSUPPORTED");
    await runCommand(
      process.env.ComSpec || "cmd.exe",
      [
        "/d",
        "/s",
        "/c",
        `""${flutter}" build web --release --dart-define=USE_REMOTE_API=true --dart-define=API_BASE_URL=http://localhost:${apiPort}/api/v1"`,
      ],
      {
        cwd: path.join(loc.workspace, "frontend"),
        windowsVerbatimArguments: true,
      },
    );
    recordBuild(loc, apiPort);
    return { status: "built", apiUrl: `http://localhost:${apiPort}/api/v1` };
  });
}
function environmentFile(loc, requested) {
  const file = path.resolve(loc.workspace, requested ?? "backend/.env");
  if (!inside(loc.workspace, file) && !inside(loc.directory, file))
    fail("UNSAFE_ENV_PATH");
  if (!regularFile(file)) fail("LOCAL_ENV_REQUIRED");
  const real = fs.realpathSync(file);
  if (!inside(loc.workspace, real) && !inside(loc.directory, real))
    fail("UNSAFE_ENV_PATH");
  return real;
}
async function prepare(loc, options) {
  const build = verifyBuild(loc, options.apiPort),
    req = createRequire(path.join(loc.workspace, "backend/package.json"));
  const input = req("dotenv").parse(
    fs.readFileSync(environmentFile(loc, options.envFile)),
  );
  const env = req("./dist/config/env.validation").validateEnv(
    configure(input, options),
  );
  const { OperationsProbes, operationsResources } = req(
    "./dist/modules/operations/operations.probes",
  );
  const config = new (req("@nestjs/config").ConfigService)(env),
    probes = new OperationsProbes(config, operationsResources);
  const checks = await Promise.allSettled([
    probes.database(),
    probes.redis(),
    probes.storage(),
    probes.mail(),
  ]);
  if (
    checks.some((result) => result.status === "rejected") ||
    !checks[0].value.database.schemaReady ||
    checks[2].value.status !== "ok"
  )
    fail("LOCAL_DEPENDENCY_UNAVAILABLE");
  if (checks[1].value.worker.status === "ok")
    fail("LOCAL_WORKER_ALREADY_ACTIVE");
  return { env, build };
}
function childEnvironment(env, identity, options) {
  const result = {};
  for (const key of [
    "PATH",
    "Path",
    "SystemRoot",
    "SYSTEMROOT",
    "WINDIR",
    "TEMP",
    "TMP",
    "USERPROFILE",
    "APPDATA",
    "LOCALAPPDATA",
    "HOME",
    "ComSpec",
  ])
    if (process.env[key]) result[key] = process.env[key];
  for (const [key, value] of Object.entries(env)) result[key] = String(value);
  // Empty values are removed by Windows; prevent dotenv from reviving a real key.
  if (!result.GEMINI_API_KEY?.trim()) result.GEMINI_API_KEY = " ";
  result.WEARLY_RUNTIME_IDENTITY = JSON.stringify(identity);
  result.WEARLY_RUNTIME_WEB_PORT = String(options.webPort);
  return result;
}
async function launch(identity, config, options) {
  const child = spawn(
    process.execPath,
    [path.join(__dirname, "local-runtime-child.cjs")],
    {
      cwd: path.join(identity.workspace, "backend"),
      env: childEnvironment(config.env, identity, options),
      stdio: ["ignore", "ignore", "ignore", "ipc"],
      detached: true,
      windowsHide: true,
    },
  );
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.disconnect();
      reject(Error("LOCAL_CHILD_START_TIMEOUT"));
    }, 20000);
    child.once("error", () => {
      clearTimeout(timer);
      reject(Error("LOCAL_CHILD_START_FAILED"));
    });
    child.once("exit", () => {
      clearTimeout(timer);
      reject(Error("LOCAL_CHILD_START_FAILED"));
    });
    child.on("message", (message) => {
      if (message?.event !== "control") return;
      clearTimeout(timer);
      const state = {
        ...identity,
        pid: child.pid,
        host: "127.0.0.1",
        controlPort: message.port,
        exited: () => child.exitCode !== null || child.signalCode !== null,
      };
      try {
        validChild(state);
      } catch (error) {
        child.disconnect();
        reject(error);
        return;
      }
      state.owned = async () => {
        await new Promise((resolve, reject) =>
          child.send({ event: "owned" }, (error) =>
            error ? reject(Error("LOCAL_CHILD_START_FAILED")) : resolve(),
          ),
        );
        child.disconnect();
        child.unref();
        const deadline = Date.now() + 20000;
        while (Date.now() < deadline) {
          if (state.exited()) fail("LOCAL_CHILD_START_FAILED");
          try {
            if ((await controlRequest(state, "status")).ready) return;
          } catch {
            /* bounded initialization */
          }
          await delay(100);
        }
        fail("LOCAL_CHILD_START_TIMEOUT");
      };
      resolve(state);
    });
  });
}
function createLogger(loc, role) {
  if (!roles.includes(role)) fail("INVALID_RUNTIME_STATE");
  const file = path.join(loc.directory, role + ".log");
  const allowed = new Set([
    "LOCAL_CHILD_STARTING",
    "LOCAL_CHILD_READY",
    "LOCAL_CHILD_STOPPING",
    "LOCAL_CHILD_STOPPED",
    "LOCAL_CHILD_START_FAILED",
    "LOCAL_CHILD_CLOSE_TIMEOUT",
    "LOCAL_CHILD_CLOSE_FAILED",
    "LOCAL_UNCAUGHT_EXCEPTION",
    "LOCAL_UNHANDLED_REJECTION",
    "LOCAL_APPLICATION_ERROR",
    "LOCAL_APPLICATION_FATAL",
    "WORKER_HEARTBEAT_UNAVAILABLE",
    "WORKER_HEARTBEAT_CLOSE_UNAVAILABLE",
    "RECOVERY_QUEUE_UNAVAILABLE",
    "RECOVERY_QUEUE_FORCED_CLOSE",
    "RECOVERY_NOTIFICATION_UNAVAILABLE",
    "QUEUE_UNAVAILABLE",
    "WORKER_QUEUE_UNAVAILABLE",
    "OUTBOX_RETRY_PENDING",
    "RECOVERY_WORKER_UNAVAILABLE",
    "RECOVERY_DELIVERY_FAILED",
    "RECOVERY_RETENTION_PENDING",
    "MAIL_WORKER_RETRY_PENDING",
    "IMAGE_RETENTION_RETRY_PENDING",
  ]);
  return (message) => {
    locations(loc.workspace, true);
    const code = allowed.has(message) ? message : "RUNTIME_EVENT";
    if ((regularFile(file)?.size ?? 0) > 1024 * 1024) {
      const oldest = file + ".2",
        previous = file + ".1";
      if (regularFile(oldest)) fs.unlinkSync(oldest);
      if (regularFile(previous)) fs.renameSync(previous, oldest);
      fs.renameSync(file, previous);
    }
    fs.appendFileSync(file, new Date().toISOString() + " " + code + "\n", {
      mode: 0o600,
    });
  };
}

module.exports = {
  locations,
  saveState,
  readState,
  validIdentity,
  validChild,
  regularFile,
  atomicJson,
  locked,
  controlRequest,
  status,
  stop,
  start,
  assertPortAvailable,
  runCommand,
  port,
  inside,
  configure,
  recordBuild,
  verifyBuild,
  build,
  prepare,
  createLogger,
};

if (require.main === module) {
  (async () => {
    const [action, ...args] = process.argv.slice(2),
      options = {};
    let root = path.resolve(__dirname, "..");
    for (let i = 0; i < args.length; i += 2) {
      const name = args[i],
        value = args[i + 1];
      if (!value) fail("INVALID_LOCAL_ARGUMENT");
      if (name === "--workspace") root = value;
      else if (name === "--api-port") options.apiPort = port(Number(value));
      else if (name === "--web-port") options.webPort = port(Number(value));
      else if (name === "--env-file") options.envFile = value;
      else fail("INVALID_LOCAL_ARGUMENT");
    }
    const command = { build, start, status, stop }[action];
    if (!command) fail("INVALID_LOCAL_ACTION");
    const result = await command(root, options);
    console.log(JSON.stringify(result, null, 2));
    if (result.status === "unverified") process.exitCode = 1;
  })().catch((error) => {
    const code = /^[A-Z][A-Z0-9_]+$/.test(error.message)
      ? error.message
      : "LOCAL_RUNTIME_FAILED";
    console.error(code);
    process.exitCode = 1;
  });
}
