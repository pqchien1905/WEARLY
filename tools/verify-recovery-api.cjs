// Spawned with a private inspection environment; never starts WorkerModule.
const path = require("node:path"),
  assert = require("node:assert/strict"),
  { createHash } = require("node:crypto"),
  { createRequire } = require("node:module");
const backend = path.resolve(__dirname, "../backend"),
  req = createRequire(path.join(backend, "package.json"));
async function main() {
  const context = require('./recovery-context.cjs').loadContext(path.dirname(backend), process.env.RECOVERY_REPORT_FILE, process.env);
  const performed = ['archiveContext', 'bundledAssets'], skipped = [];
  const db = new URL(process.env.DATABASE_URL);
  if (
    !["127.0.0.1", "localhost", "[::1]"].includes(db.hostname) ||
    !/^\/wearly_recovery_\d{13}_[a-f0-9]{8}$/.test(db.pathname) ||
    process.env.GEMINI_API_KEY?.trim() ||
    process.env.VNPAY_ENABLED !== "false" ||
    process.env.LOCAL_MAIL_ENABLED !== "false"
  )
    throw Error("INSPECTION_ONLY");
  process.chdir(backend);
  req("reflect-metadata");
  const { Client } = req('pg'), { databaseSchemaReady } = req('./dist/database/schema-readiness');
  const probe = new Client({ ...context.config.database, connectionTimeoutMillis:3000, query_timeout:10000, options:'-c statement_timeout=8000' });
  probe.on('error',()=>{});
  try {
    await probe.connect();
    const compatible = await databaseSchemaReady(probe);
    context.report.applicationCompatibility.schema = compatible ? 'verified' : 'mismatched';
    context.save();
    assert(compatible);
    performed.push('compiledSchema');
  } finally { await probe.end(); }
  const { NestFactory } = req("@nestjs/core"),
    { JwtService } = req("@nestjs/jwt"),
    { AppModule } = req("./dist/app.module"),
    { configureApp } = req("./dist/bootstrap");
  const app = await NestFactory.create(AppModule, {
    logger: false,
    abortOnError: false,
  });
  try {
    configureApp(app);
    await app.listen(0, "127.0.0.1");
    const base = await app.getUrl();
    for (const route of [
      "/api/v1/health/ready",
      "/api/v1/products",
      "/api/v1/content",
    ]) {
      assert.equal(
        (await fetch(base + route, { signal: AbortSignal.timeout(10000) }))
          .status,
        200,
      );
      performed.push(route);
    }
    if (process.env.RECOVERY_VERIFY_ASSET) {
      const response = await fetch(
        base + "/api/v1/catalog/images/" + process.env.RECOVERY_VERIFY_ASSET,
        { signal: AbortSignal.timeout(10000) },
      );
      assert.equal(response.status, 200);
      assert.equal(
        createHash("sha256")
          .update(Buffer.from(await response.arrayBuffer()))
          .digest("hex"),
        process.env.RECOVERY_VERIFY_HASH,
      );
      performed.push('managedImageBytes');
    } else skipped.push('managedImageBytes: no fixture supplied');
    if (process.env.RECOVERY_VERIFY_SESSION) {
      // Even a correctly signed bearer referencing the old session must be rejected.
      const token = new JwtService().sign(
        {
          sub: process.env.RECOVERY_VERIFY_USER,
          sid: process.env.RECOVERY_VERIFY_SESSION,
          typ: "access",
        },
        {
          secret: process.env.JWT_ACCESS_SECRET,
          algorithm: "HS256",
          issuer: "wearly",
          audience: "wearly-api",
          expiresIn: 60,
        },
      );
      assert.equal(
        (
          await fetch(base + "/api/v1/auth/me", {
            headers: { Authorization: "Bearer " + token },
            signal: AbortSignal.timeout(10000),
          })
        ).status,
        401,
      );
      performed.push('oldSessionRefused');
    } else skipped.push('oldSessionRefused: no fixture supplied');
    assert.equal(
      (
        await fetch(base + "/api/v1/admin/audit", {
          signal: AbortSignal.timeout(10000),
        })
      ).status,
      401,
    );
    performed.push('privateRouteRefused');
    context.report.applicationCompatibility.api = 'verified';
    context.report.applicationChecks = { performed, skipped, verifiedAt: new Date().toISOString() };
    context.save();
    console.log('PASS restored API: ' + JSON.stringify(context.report.applicationChecks));
  } finally {
    await app.close();
  }
}
const timer = setTimeout(() => {
  console.error("RECOVERY_API_TIMEOUT");
  process.exit(1);
}, 30000);
main()
  .catch(() => {
    console.error("RECOVERY_API_VERIFICATION_FAILED");
    process.exitCode = 1;
  })
  .finally(() => clearTimeout(timer));
