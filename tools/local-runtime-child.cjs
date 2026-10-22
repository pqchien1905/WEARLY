const http = require("node:http");
const { timingSafeEqual } = require("node:crypto");
const path = require("node:path");
const fs = require("node:fs");
const { createRequire } = require("node:module");
const {
  validIdentity,
  locations,
  createLogger,
} = require("./local-runtime.cjs");

async function startControl(identity, application) {
  validIdentity(identity);
  let stopping = false,
    closing;
  const close = () =>
    (closing ??= new Promise((resolve) => {
      if (!server.listening) {
        resolve();
        return;
      }
      server.close(() => resolve());
      server.closeIdleConnections();
    }));
  const server = http.createServer(async (request, response) => {
    const expected = Buffer.from("Bearer " + identity.secret),
      actual = Buffer.from(request.headers.authorization ?? "");
    const authenticated =
      !request.headers.origin &&
      !request.headers["sec-fetch-site"] &&
      expected.length === actual.length &&
      timingSafeEqual(expected, actual) &&
      request.headers["x-wearly-run"] === identity.runId &&
      request.headers["x-wearly-role"] === identity.role &&
      request.headers["x-wearly-workspace"] ===
        Buffer.from(identity.workspace).toString("base64");
    response.setHeader("Cache-Control", "private, no-store");
    response.setHeader("Content-Type", "application/json");
    if (!authenticated) {
      response.writeHead(403).end("{}");
      return;
    }
    const stop = request.url === "/stop" && request.method === "POST";
    if (!stop && !(request.url === "/status" && request.method === "GET")) {
      response.writeHead(404).end("{}");
      return;
    }
    const state = application.status();
    response
      .writeHead(stop ? 202 : 200)
      .end(
        JSON.stringify({
          workspace: identity.workspace,
          runId: identity.runId,
          role: identity.role,
          pid: process.pid,
          ready: !stopping && !stop && state.ready === true,
        }),
      );
    if (stop && !stopping) {
      stopping = true;
      try {
        await application.stop();
        await close();
      } catch {
        /* Keep failed shutdown observable until the owning child exits. */
      }
    }
  });
  server.requestTimeout = 3000;
  server.headersTimeout = 3000;
  server.keepAliveTimeout = 500;
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  return { port: server.address().port, close };
}
module.exports = { startControl };

async function main() {
  const identity = JSON.parse(process.env.WEARLY_RUNTIME_IDENTITY ?? "null");
  validIdentity(identity);
  if (fs.realpathSync(identity.workspace) !== identity.workspace)
    throw Error("INVALID_RUNTIME_STATE");
  const loc = locations(identity.workspace, true),
    write = createLogger(loc, identity.role);
  let app,
    server,
    ready = false,
    owned = false,
    closing,
    exitCode = 0,
    control;
  const log = (code) => {
    try {
      write(code);
    } catch {
      /* A log failure must not expose raw errors on stderr. */
    }
  };
  const closeApplication = async () => {
    ready = false;
    if (app) await app.close();
    if (server)
      await new Promise((resolve) => {
        server.close(resolve);
        server.closeIdleConnections();
      });
  };
  const stop = () =>
    (closing ??= (async () => {
      const deadline = setTimeout(() => {
        log("LOCAL_CHILD_CLOSE_TIMEOUT");
        process.exit(1);
      }, 150000);
      deadline.unref();
      log("LOCAL_CHILD_STOPPING");
      try {
        await closeApplication();
      } catch {
        exitCode = 1;
        log("LOCAL_CHILD_CLOSE_FAILED");
      }
      await control?.close();
      clearTimeout(deadline);
      log("LOCAL_CHILD_STOPPED");
      process.exit(exitCode);
    })());
  control = await startControl(identity, { status: () => ({ ready }), stop });
  process.on("message", (message) => {
    if (message?.event === "owned") owned = true;
  });
  process.on("disconnect", () => {
    if (!owned) void stop();
  });
  process.on("uncaughtException", () => {
    exitCode = 1;
    log("LOCAL_UNCAUGHT_EXCEPTION");
    void stop();
  });
  process.on("unhandledRejection", () => {
    exitCode = 1;
    log("LOCAL_UNHANDLED_REJECTION");
    void stop();
  });
  if (identity.role !== "api") {
    process.on("SIGINT", () => void stop());
    process.on("SIGTERM", () => void stop());
  }
  process.send?.({ event: "control", port: control.port });
  write("LOCAL_CHILD_STARTING");
  try {
    if (identity.role === "web") {
      const { createStaticServer } = require("./serve.cjs");
      server = createStaticServer(
        path.join(identity.workspace, "frontend/build/web"),
      );
      await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(
          Number(process.env.WEARLY_RUNTIME_WEB_PORT),
          "127.0.0.1",
          resolve,
        );
      });
    } else {
      const req = createRequire(
        path.join(identity.workspace, "backend/package.json"),
      );
      req("reflect-metadata");
      const { NestFactory } = req("@nestjs/core");
      const logger = {
        log: () => {},
        warn: (message) => log(message),
        error: () => log("LOCAL_APPLICATION_ERROR"),
        debug: () => {},
        verbose: () => {},
        fatal: () => log("LOCAL_APPLICATION_FATAL"),
      };
      if (identity.role === "api") {
        app = await NestFactory.create(req("./dist/app.module").AppModule, {
          logger,
          abortOnError: false,
        });
        req("./dist/bootstrap").configureApp(app);
        await app.listen(Number(process.env.PORT), "127.0.0.1");
        await app
          .get(req("./dist/modules/health/health.controller").HealthController)
          .ready();
      } else {
        app = await NestFactory.createApplicationContext(
          req("./dist/worker/worker.module").WorkerModule,
          { logger, abortOnError: false },
        );
        const { OperationsProbes, operationsResources } = req(
          "./dist/modules/operations/operations.probes",
        );
        const probe = await new OperationsProbes(
          app.get(req("@nestjs/config").ConfigService),
          operationsResources,
        ).redis();
        if (probe.worker.status !== "ok") throw Error("WORKER_NOT_READY");
      }
    }
    if (closing) {
      await closeApplication();
      return;
    }
    ready = true;
    log("LOCAL_CHILD_READY");
  } catch {
    exitCode = 1;
    log("LOCAL_CHILD_START_FAILED");
    await stop();
  }
}
if (require.main === module) void main().catch(() => process.exit(1));
