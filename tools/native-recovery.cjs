const fs = require("node:fs"),
  path = require("node:path"),
  { createHash, randomUUID } = require("node:crypto");
const { createRequire } = require("node:module");
const req = createRequire(path.resolve(__dirname, "../backend/package.json"));
const postgres = require("./recovery-postgres.cjs");
const fail = (code) => {
  throw Error(code);
};
function validateConfig(env) {
  try {
    const db = new URL(env.DATABASE_URL),
      s3 = new URL(env.S3_ENDPOINT);
    const local = (host) => ["127.0.0.1", "localhost", "[::1]"].includes(host);
    if (
      env.NODE_ENV === "production" ||
      !["postgres:", "postgresql:"].includes(db.protocol) ||
      !local(db.hostname) ||
      db.search ||
      db.hash ||
      !/^\/[A-Za-z_][A-Za-z0-9_]*$/.test(db.pathname) ||
      !db.username ||
      !db.password ||
      !local(s3.hostname) ||
      !["http:", "https:"].includes(s3.protocol) ||
      s3.pathname !== "/" ||
      s3.search ||
      s3.hash ||
      s3.username ||
      s3.password ||
      !env.S3_ACCESS_KEY_ID ||
      !env.S3_SECRET_ACCESS_KEY ||
      !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(env.S3_BUCKET)
    )
      fail("RECOVERY_LOCAL_CONFIGURATION_REQUIRED");
    return {
      database: {
        host: db.hostname.replace(/^\[|\]$/g, ""),
        port: Number(db.port || 5432),
        user: decodeURIComponent(db.username),
        password: decodeURIComponent(db.password),
        database: db.pathname.slice(1),
      },
      storage: {
        endpoint: s3.href,
        region: env.S3_REGION || "us-east-1",
        forcePathStyle: true,
        maxAttempts: 1,
        credentials: {
          accessKeyId: env.S3_ACCESS_KEY_ID,
          secretAccessKey: env.S3_SECRET_ACCESS_KEY,
        },
      },
      bucket: env.S3_BUCKET,
    };
  } catch {
    fail("RECOVERY_LOCAL_CONFIGURATION_REQUIRED");
  }
}
function safeFile(root, name) {
  if (
    typeof name !== "string" ||
    !name ||
    name.includes("\\") ||
    name.split("/").some((part) => !part || part === "." || part === "..") ||
    path.isAbsolute(name) ||
    name.includes(":")
  )
    fail("RECOVERY_UNSAFE_PATH");
  const canonical = fs.realpathSync(root);
  let current = canonical;
  const parts = name.split("/");
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    try {
      const stat = fs.lstatSync(current);
      if (
        stat.isSymbolicLink() ||
        (i < parts.length - 1 && !stat.isDirectory()) ||
        (i === parts.length - 1 && !stat.isFile())
      )
        fail("RECOVERY_UNSAFE_PATH");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  return current;
}
function verifyFiles(root, manifest) {
  if (
    manifest?.version !== 1 ||
    manifest.status !== "complete" ||
    !Array.isArray(manifest.files) ||
    !manifest.files.length ||
    manifest.files.length > 10002
  )
    fail("RECOVERY_INVALID_MANIFEST");
  const seen = new Set();
  let total = 0;
  for (const file of manifest.files) {
    if (
      seen.has(file.file) ||
      !Number.isSafeInteger(file.size) ||
      file.size < 0 ||
      !/^[a-f0-9]{64}$/.test(file.sha256)
    )
      fail("RECOVERY_INVALID_MANIFEST");
    seen.add(file.file);
    total += file.size;
    if (total > 1024 * 1024 * 1024) fail("RECOVERY_ARCHIVE_LIMIT");
    const target = safeFile(root, file.file),
      stat = fs.statSync(target);
    if (stat.size !== file.size) fail("RECOVERY_FILE_MISMATCH");
    if (fileHash(target) !== file.sha256) fail("RECOVERY_FILE_MISMATCH");
  }
}
function fileHash(target) {
  const handle = fs.openSync(target, "r"),
    hash = createHash("sha256"),
    buffer = Buffer.alloc(65536);
  try {
    let count;
    while ((count = fs.readSync(handle, buffer, 0, buffer.length, null)) > 0)
      hash.update(buffer.subarray(0, count));
  } finally {
    fs.closeSync(handle);
  }
  return hash.digest("hex");
}
function locations(workspace) {
  const runtime = require("./local-runtime.cjs").locations(workspace);
  const tools = path.dirname(path.dirname(runtime.directory));
  let current = tools;
  for (const part of ["recovery", path.basename(runtime.directory)]) {
    current = path.join(current, part);
    if (fs.existsSync(current)) {
      const stat = fs.lstatSync(current);
      if (stat.isSymbolicLink() || !stat.isDirectory())
        fail("RECOVERY_UNSAFE_PATH");
    } else fs.mkdirSync(current);
  }
  return { workspace: runtime.workspace, base: current };
}
async function backup(workspace, options = {}) {
  const canonical = fs.realpathSync(workspace);
  const input =
    options.env ??
    req("dotenv").parse(
      fs.readFileSync(safeFile(canonical, options.envFile ?? "backend/.env")),
    );
  const config = validateConfig(input);
  if (process.env.NODE_ENV === "production")
    fail("RECOVERY_LOCAL_CONFIGURATION_REQUIRED");
  if (process.platform !== "win32") fail("RECOVERY_WINDOWS_REQUIRED");
  const bin = "C:/Program Files/PostgreSQL/17/bin";
  for (const command of ["pg_dump.exe", "pg_restore.exe"]) {
    const version = await postgres.runNative(path.join(bin, command), [
      "--version",
    ]);
    if (!/\(PostgreSQL\) 17\./.test(version))
      fail("RECOVERY_POSTGRES_17_REQUIRED");
  }
  const loc = locations(canonical),
    directory = path.join(loc.base, Date.now() + "-" + randomUUID());
  fs.mkdirSync(directory);
  await postgres.runNative("powershell.exe", [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(__dirname, "recovery-private.ps1"),
    "-Directory",
    directory,
  ]);
  const manifest = {
    version: 1,
    status: "incomplete",
    source: { database: config.database.database, bucket: config.bucket },
    startedAt: new Date().toISOString(),
    files: [],
  };
  const manifestFile = path.join(directory, "manifest.json");
  const save = () =>
    fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 2), {
      mode: 0o600,
    });
  save();
  options.onArchive?.(directory);
  const { Client } = req("pg"),
    { S3Client } = req("@aws-sdk/client-s3");
  const client = new Client({
    ...config.database,
    connectionTimeoutMillis: 3000,
    query_timeout: 35000,
    options:
      "-c timezone=UTC -c statement_timeout=30000 -c idle_in_transaction_session_timeout=300000",
  });
  const s3 = new S3Client(config.storage);
  client.on("error", () => {});
  try {
    await client.connect();
    await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    await client.query("SET LOCAL search_path TO public,pg_catalog");
    manifest.snapshotAt = (
      await client.query("SELECT transaction_timestamp() AS time")
    ).rows[0].time.toISOString();
    manifest.snapshot = await postgres.snapshot(client);
    const exported = (await client.query("SELECT pg_export_snapshot() AS id"))
      .rows[0].id;
    await options.afterSnapshot?.();
    const pgEnvironment = {
      ...process.env,
      PGPASSWORD: config.database.password,
      PGOPTIONS: "-c timezone=UTC",
      PGCONNECT_TIMEOUT: "5",
    };
    // Reject inherited libpq routing/configuration; explicit CLI arguments own routing.
    for (const key of Object.keys(pgEnvironment))
      if (
        key.startsWith("PG") &&
        !["PGPASSWORD", "PGOPTIONS", "PGCONNECT_TIMEOUT"].includes(key)
      )
        delete pgEnvironment[key];
    const connection = [
      "-h",
      config.database.host,
      "-p",
      String(config.database.port),
      "-U",
      config.database.user,
      "-d",
      config.database.database,
    ];
    await postgres.runNative(
      path.join(bin, "pg_dump.exe"),
      [
        ...connection,
        "-Fc",
        "--snapshot=" + exported,
        "-f",
        path.join(directory, "database.dump"),
      ],
      { env: pgEnvironment },
    );
    await postgres.runNative(path.join(bin, "pg_restore.exe"), [
      "--list",
      path.join(directory, "database.dump"),
    ]);
    const collected = await require("./recovery-objects.cjs").collectObjects(
      client,
      s3,
      config.bucket,
      directory,
      canonical,
    );
    Object.assign(manifest, collected);
    const dumpFile = path.join(directory, "database.dump"),
      dumpSize = fs.statSync(dumpFile).size;
    if (dumpSize > 1024 * 1024 * 1024) fail("RECOVERY_ARCHIVE_LIMIT");
    manifest.files.push({
      file: "database.dump",
      size: dumpSize,
      sha256: fileHash(dumpFile),
    });
    manifest.source.gitRevision = (
      await postgres.runNative("git", ["rev-parse", "HEAD"], { cwd: canonical })
    ).trim();
    await client.query("COMMIT");
    manifest.status = "complete";
    manifest.finishedAt = new Date().toISOString();
    verifyFiles(directory, manifest);
    save();
    return {
      directory,
      tables: Object.keys(manifest.snapshot.tables).length,
      objects: manifest.objects.length,
    };
  } catch {
    manifest.status = "failed";
    manifest.error = "RECOVERY_BACKUP_FAILED";
    manifest.finishedAt = new Date().toISOString();
    save();
    throw Error("RECOVERY_BACKUP_FAILED");
  } finally {
    await client.end().catch(() => {});
    s3.destroy();
  }
}
module.exports = { validateConfig, safeFile, verifyFiles, locations, backup };
if (require.main === module) {
  (async () => {
    if (process.argv[2] !== "backup") fail("RECOVERY_INVALID_ACTION");
    const args = process.argv.slice(3);
    if (args.length && !(args.length === 2 && args[0] === "--env-file"))
      fail("RECOVERY_INVALID_ARGUMENTS");
    const result = await backup(path.resolve(__dirname, ".."), {
      envFile: args[1],
    });
    console.log("Backup complete: " + result.directory);
    console.log(
      "Tables: " + result.tables + "; managed images: " + result.objects,
    );
  })().catch(() => {
    console.error("RECOVERY_FAILED; inspect the retained private manifest.");
    process.exitCode = 1;
  });
}
