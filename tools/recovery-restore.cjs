const fs = require("node:fs"),
  path = require("node:path"),
  { createHash, randomBytes, randomUUID } = require("node:crypto"),
  { createRequire } = require("node:module");
const req = createRequire(path.resolve(__dirname, "../backend/package.json"));
const postgres = require("./recovery-postgres.cjs"),
  objects = require("./recovery-objects.cjs");
const fail = (code) => {
  throw Error(code);
};
const quote = (value) => '"' + value.replaceAll('"', '""') + '"';
async function restore(workspace, archive, options = {}) {
  const recovery = require("./native-recovery.cjs");
  const loc = recovery.locations(workspace),
    directory = fs.realpathSync(archive);
  if (
    fs.lstatSync(archive).isSymbolicLink() ||
    path.dirname(directory) !== loc.base ||
    !/^\d{13}-[a-f0-9-]{36}$/.test(path.basename(directory))
  )
    fail("RECOVERY_UNSAFE_PATH");
  const manifestPath = recovery.safeFile(directory, "manifest.json");
  if (fs.statSync(manifestPath).size > 16 * 1024 * 1024)
    fail("RECOVERY_INVALID_MANIFEST");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  recovery.verifyFiles(directory, manifest);
  if (
    !manifest.snapshot?.tables ||
    !manifest.snapshot?.schema ||
    !Array.isArray(manifest.objects) ||
    !Array.isArray(manifest.bundled) ||
    !manifest.source
  )
    fail("RECOVERY_INVALID_MANIFEST");
  for (const row of Object.values(manifest.snapshot.tables))
    if (
      !Number.isSafeInteger(row.count) ||
      row.count < 0 ||
      !/^[a-f0-9]{64}$/.test(row.sha256)
    )
      fail("RECOVERY_INVALID_MANIFEST");
  const indexed = new Map(manifest.files.map((file) => [file.file, file]));
  const expected = new Set(["database.dump"]);
  if (!indexed.has("database.dump")) fail("RECOVERY_INVALID_MANIFEST");
  for (const asset of manifest.objects) {
    if (
      asset.file !== "objects/" + path.basename(asset.objectKey) ||
      !indexed.has(asset.file) ||
      expected.has(asset.file)
    )
      fail("RECOVERY_INVALID_MANIFEST");
    const bytes = fs.readFileSync(recovery.safeFile(directory, asset.file));
    objects.verifyBytes(asset, bytes);
    expected.add(asset.file);
  }
  let workspaceAssetsMatch = true;
  for (const asset of manifest.bundled) {
    if (
      !/^frontend\/assets\/images\/[a-zA-Z0-9_.-]+$/.test(asset.source) ||
      asset.file !== "bundled/" + path.basename(asset.source) ||
      !indexed.has(asset.file) ||
      expected.has(asset.file)
    )
      fail("RECOVERY_INVALID_MANIFEST");
    expected.add(asset.file);
    try {
      const source = recovery.safeFile(loc.workspace, asset.source);
      workspaceAssetsMatch &&=
        createHash("sha256").update(fs.readFileSync(source)).digest("hex") ===
        indexed.get(asset.file).sha256;
    } catch {
      workspaceAssetsMatch = false;
    }
  }
  if (expected.size !== indexed.size) fail("RECOVERY_INVALID_MANIFEST");
  const input =
    options.env ??
    req("dotenv").parse(
      fs.readFileSync(
        recovery.safeFile(loc.workspace, options.envFile ?? "backend/.env"),
      ),
    );
  const config = recovery.validateConfig(input);
  if (
    !["127.0.0.1", "localhost", "::1"].includes(
      input.REDIS_HOST || "127.0.0.1",
    ) ||
    !Number.isInteger(Number(input.REDIS_PORT || 6379)) ||
    Number(input.REDIS_PORT || 6379) < 1 ||
    Number(input.REDIS_PORT || 6379) > 65535
  )
    fail("RECOVERY_LOCAL_CONFIGURATION_REQUIRED");
  if (process.platform !== "win32" || process.env.NODE_ENV === "production")
    fail("RECOVERY_LOCAL_CONFIGURATION_REQUIRED");
  if (
    config.database.database !== manifest.source.database ||
    config.bucket !== manifest.source.bucket
  )
    fail("RECOVERY_SOURCE_CONFIGURATION_MISMATCH");
  const bin = "C:/Program Files/PostgreSQL/17/bin";
  if (
    !/\(PostgreSQL\) 17\./.test(
      await postgres.runNative(path.join(bin, "pg_restore.exe"), ["--version"]),
    )
  )
    fail("RECOVERY_POSTGRES_17_REQUIRED");
  const adminConfig = JSON.parse(
    fs.readFileSync(
      recovery.safeFile(path.resolve(loc.base, "../.."), "postgres-admin.json"),
      "utf8",
    ),
  );
  const host = (value) => (value === "localhost" ? "127.0.0.1" : value);
  if (
    host(adminConfig.host) !== host(config.database.host) ||
    Number(adminConfig.port) !== config.database.port ||
    adminConfig.database !== "postgres" ||
    !adminConfig.user ||
    !adminConfig.password
  )
    fail("RECOVERY_ADMIN_CONFIGURATION_MISMATCH");
  const suffix = Date.now() + "_" + randomUUID().slice(0, 8),
    target = {
      database: "wearly_recovery_" + suffix,
      bucket: "wearly-recovery-" + suffix.replace("_", "-"),
    };
  const output = path.join(loc.base, "restore-" + suffix);
  fs.mkdirSync(output);
  await postgres.runNative("powershell.exe", [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(__dirname, "recovery-private.ps1"),
    "-Directory",
    output,
  ]);
  const report = {
    version: 1,
    status: "incomplete",
    archive: path.basename(directory),
    target,
    startedAt: new Date().toISOString(),
    workspaceAssetsMatch,
    stage: "PREFLIGHT",
  };
  const save = () =>
    fs.writeFileSync(
      path.join(output, "result.json"),
      JSON.stringify(report, null, 2),
      { mode: 0o600 },
    );
  save();
  const { Client } = req("pg"),
    sdk = req("@aws-sdk/client-s3");
  const admin = new Client({
      ...adminConfig,
      connectionTimeoutMillis: 3000,
      query_timeout: 15000,
    }),
    s3 = new sdk.S3Client(config.storage);
  let restored;
  admin.on("error", () => {});
  try {
    await admin.connect();
    const role = (
      await admin.query(
        "SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=$1",
        [config.database.user],
      )
    ).rows[0];
    if (!role || role.rolsuper || role.rolcreatedb || role.rolcreaterole)
      fail("RECOVERY_ORDINARY_OWNER_REQUIRED");
    await recovery.assertFreshTargets(admin, s3, target);
    report.stage = "CREATE_DATABASE";
    save();
    await admin.query(
      `CREATE DATABASE ${quote(target.database)} WITH OWNER ${quote(config.database.user)} ENCODING 'UTF8' TEMPLATE template0`,
    );
    report.databaseCreated = true;
    save();
    await admin.query(
      `REVOKE CONNECT ON DATABASE ${quote(target.database)} FROM PUBLIC`,
    );
    report.stage = "RESTORE_DATABASE";
    save();
    const pgEnv = postgres.environment(config.database);
    await postgres.runNative(
      path.join(bin, "pg_restore.exe"),
      [
        "-h",
        config.database.host,
        "-p",
        String(config.database.port),
        "-U",
        config.database.user,
        "-d",
        target.database,
        "--exit-on-error",
        "--single-transaction",
        "--no-owner",
        "--no-privileges",
        recovery.safeFile(directory, "database.dump"),
      ],
      { env: pgEnv },
    );
    report.stage = "VERIFY_DATABASE";
    save();
    restored = new Client({
      ...config.database,
      database: target.database,
      connectionTimeoutMillis: 3000,
      query_timeout: 35000,
      options: "-c timezone=UTC -c statement_timeout=30000",
    });
    restored.on("error", () => {});
    await restored.connect();
    await restored.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    await restored.query("SET LOCAL search_path TO public,pg_catalog");
    const before = await postgres.snapshot(restored);
    await restored.query("COMMIT");
    if (
      JSON.stringify(postgres.canonicalSnapshot(before)) !==
      JSON.stringify(postgres.canonicalSnapshot(manifest.snapshot))
    ) {
      report.mismatchedSections = Object.keys(before).filter(
        (key) =>
          JSON.stringify(before[key]) !==
          JSON.stringify(manifest.snapshot[key]),
      );
      fail("RECOVERY_SNAPSHOT_MISMATCH");
    }
    report.exactSnapshotVerified = true;
    report.stage = "CREATE_BUCKET";
    save();
    await s3.send(new sdk.CreateBucketCommand({ Bucket: target.bucket }), {
      abortSignal: AbortSignal.timeout(10000),
    });
    report.bucketCreated = true;
    save();
    await objects.privateBucket(s3, target.bucket);
    report.stage = "RESTORE_OBJECTS";
    save();
    for (const asset of manifest.objects) {
      const bytes = fs.readFileSync(recovery.safeFile(directory, asset.file));
      objects.verifyBytes(asset, bytes);
      await s3.send(
        new sdk.PutObjectCommand({
          Bucket: target.bucket,
          Key: asset.objectKey,
          Body: bytes,
          ContentType: asset.mimeType,
          IfNoneMatch: "*",
        }),
        { abortSignal: AbortSignal.timeout(10000) },
      );
      const fetched = await s3.send(
        new sdk.GetObjectCommand({
          Bucket: target.bucket,
          Key: asset.objectKey,
        }),
        { abortSignal: AbortSignal.timeout(10000) },
      );
      objects.verifyBytes(
        asset,
        await objects.readBody(fetched.Body, 8 * 1024 * 1024),
      );
    }
    report.objectsVerified = manifest.objects.length;
    report.stage = "QUARANTINE";
    save();
    report.quarantine = await postgres.quarantine(restored, target.database);
    const url = new URL(input.DATABASE_URL);
    url.pathname = "/" + target.database;
    const inspection = {
      NODE_ENV: "development",
      HOST: "127.0.0.1",
      PORT: "3000",
      DATABASE_URL: url.href,
      REDIS_HOST: input.REDIS_HOST || "127.0.0.1",
      REDIS_PORT: input.REDIS_PORT || "6379",
      AI_QUEUE_PREFIX: "recovery-" + randomUUID(),
      JWT_ACCESS_SECRET: randomBytes(32).toString("hex"),
      JWT_REFRESH_SECRET: randomBytes(32).toString("hex"),
      CORS_ORIGINS: "http://localhost:8080",
      SWAGGER_ENABLED: "false",
      S3_ENDPOINT: config.storage.endpoint,
      S3_REGION: config.storage.region,
      S3_BUCKET: target.bucket,
      S3_ACCESS_KEY_ID: config.storage.credentials.accessKeyId,
      S3_SECRET_ACCESS_KEY: config.storage.credentials.secretAccessKey,
      GEMINI_API_KEY: " ",
      VNPAY_ENABLED: "false",
      VNPAY_TMN_CODE: "",
      VNPAY_HASH_SECRET: "",
      AI_PROVIDER_URL: "",
      AI_PROVIDER_API_KEY: "",
      LOCAL_MAIL_ENABLED: "false",
      PASSWORD_RECOVERY_ENABLED: "false",
    };
    const inspectionFile = path.join(output, "inspection.env");
    fs.writeFileSync(
      inspectionFile,
      Object.entries(inspection)
        .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
        .join("\n") + "\n",
      { flag: "wx", mode: 0o600 },
    );
    report.status = "complete";
    report.stage = "QUARANTINED";
    report.finishedAt = new Date().toISOString();
    save();
    return { directory: output, target, inspectionFile };
  } catch (error) {
    report.status = "failed";
    report.error = [
      "RECOVERY_SNAPSHOT_MISMATCH",
      "RECOVERY_QUARANTINE_MISMATCH",
      "RECOVERY_NATIVE_COMMAND_FAILED",
      "RECOVERY_TARGET_EXISTS",
    ].includes(error.message)
      ? error.message
      : "RECOVERY_RESTORE_FAILED";
    report.finishedAt = new Date().toISOString();
    save();
    throw Error("RECOVERY_RESTORE_FAILED");
  } finally {
    await restored?.end().catch(() => {});
    await admin.end().catch(() => {});
    s3.destroy();
  }
}
module.exports = { restore };
