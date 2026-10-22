// Dedicated test resources only. Source fixtures are removed; archives are retained.
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { randomUUID, createHash } = require("node:crypto"),
  { createRequire } = require("node:module");
const root = path.resolve(__dirname, ".."),
  req = createRequire(path.join(root, "backend/package.json"));
const recovery = require("./native-recovery.cjs"),
  postgres = require("./recovery-postgres.cjs");
let stage = "CONFIG";
async function main() {
  if (typeof recovery.backup !== "function")
    throw Error("BACKUP_NOT_IMPLEMENTED");
  const env = {
    ...req("dotenv").parse(fs.readFileSync(path.join(root, "backend/.env"))),
    ...req("dotenv").parse(
      fs.readFileSync(path.join(root, "backend/.env.test")),
    ),
  };
  const sourceUrl = env.TEST_DATABASE_URL;
  if (
    !sourceUrl ||
    sourceUrl === env.DATABASE_URL ||
    !new URL(sourceUrl).pathname.endsWith("_test")
  )
    throw Error("DEDICATED_TEST_DATABASE_REQUIRED");
  const testEnv = {
    ...env,
    NODE_ENV: "test",
    DATABASE_URL: sourceUrl,
    S3_BUCKET: env.TEST_S3_BUCKET || env.S3_BUCKET + "-test",
    S3_ENDPOINT: env.TEST_S3_ENDPOINT || env.S3_ENDPOINT,
  };
  if (
    testEnv.S3_BUCKET === env.S3_BUCKET ||
    !testEnv.S3_BUCKET.endsWith("-test")
  )
    throw Error("DEDICATED_TEST_BUCKET_REQUIRED");
  const config = recovery.validateConfig(testEnv),
    { Client } = req("pg"),
    sdk = req("@aws-sdk/client-s3");
  const db = new Client({
      ...config.database,
      connectionTimeoutMillis: 3000,
      options: "-c timezone=UTC",
    }),
    s3 = new sdk.S3Client(config.storage);
  const id = randomUUID(),
    assetId = randomUUID(),
    objectKey = `catalog/${assetId}.png`,
    oldName = "recovery-before-" + id,
    newName = "recovery-after-" + id;
  let locked = false,
    createdUser = false,
    createdAsset = false,
    createdObject = false;
  await db.connect();
  try {
    locked = (
      await db.query(
        "SELECT pg_try_advisory_lock(hashtext('wearly-worker-e2e')) AS locked",
      )
    ).rows[0].locked;
    if (!locked) throw Error("TEST_DATABASE_IN_USE");
    const bytes = await req("sharp")({
      create: { width: 2, height: 2, channels: 3, background: "#336699" },
    })
      .png()
      .toBuffer();
    await db.query(
      'INSERT INTO public."User" (id,email,"passwordHash",name,"updatedAt") VALUES ($1,$2,$3,$4,now())',
      [id, id + "@recovery.test", "synthetic-unusable-password", oldName],
    );
    createdUser = true;
    await s3.send(
      new sdk.PutObjectCommand({
        Bucket: config.bucket,
        Key: objectKey,
        Body: bytes,
        ContentType: "image/png",
      }),
      { abortSignal: AbortSignal.timeout(10000) },
    );
    createdObject = true;
    await db.query(
      'INSERT INTO public."CatalogAsset" (id,"productId","actorId","requestKey","inputHash","objectKey",sha256,"mimeType",size,width,height,"verifiedAt") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,2,2,now())',
      [
        assetId,
        randomUUID(),
        id,
        randomUUID(),
        "a".repeat(64),
        objectKey,
        createHash("sha256").update(bytes).digest("hex"),
        "image/png",
        bytes.length,
      ],
    );
    createdAsset = true;
    stage = "BACKUP";
    const result = await recovery.backup(root, {
      env: testEnv,
      afterSnapshot: async () => {
        await db.query('UPDATE public."User" SET name=$2 WHERE id=$1', [
          id,
          newName,
        ]);
      },
    });
    const manifest = JSON.parse(
      fs.readFileSync(path.join(result.directory, "manifest.json"), "utf8"),
    );
    assert.equal(manifest.status, "complete");
    recovery.verifyFiles(result.directory, manifest);
    assert(manifest.objects.some((a) => a.id === assetId));
    stage = "SNAPSHOT_SQL";
    const sqlFile = path.join(result.directory, "snapshot-verification.sql");
    assert(!fs.existsSync(sqlFile));
    await postgres.runNative(
      "C:/Program Files/PostgreSQL/17/bin/pg_restore.exe",
      ["--file=" + sqlFile, path.join(result.directory, "database.dump")],
    );
    try {
      const sql = fs.readFileSync(sqlFile, "utf8");
      assert(sql.includes(oldName));
      assert(!sql.includes(newName));
    } finally {
      fs.unlinkSync(sqlFile);
    }
    assert.equal(
      (await db.query('SELECT name FROM public."User" WHERE id=$1', [id]))
        .rows[0].name,
      newName,
    );
    stage = "MISSING_OBJECT";
    await s3.send(
      new sdk.DeleteObjectCommand({ Bucket: config.bucket, Key: objectKey }),
      { abortSignal: AbortSignal.timeout(10000) },
    );
    createdObject = false;
    let failedDirectory;
    await assert.rejects(
      recovery.backup(root, {
        env: testEnv,
        onArchive: (directory) => {
          failedDirectory = directory;
        },
      }),
    );
    assert(failedDirectory);
    assert.notEqual(
      JSON.parse(
        fs.readFileSync(path.join(failedDirectory, "manifest.json"), "utf8"),
      ).status,
      "complete",
    );
    console.log(
      "PASS synthetic backup: exported snapshot preserves pre-change data; catalog hashes verified; missing object cannot complete.",
    );
    console.log("Retained archive: " + result.directory);
  } finally {
    if (createdAsset)
      await db.query('DELETE FROM public."CatalogAsset" WHERE id=$1', [
        assetId,
      ]);
    if (createdUser)
      await db.query('DELETE FROM public."User" WHERE id=$1', [id]);
    if (createdObject)
      await s3.send(
        new sdk.DeleteObjectCommand({ Bucket: config.bucket, Key: objectKey }),
        { abortSignal: AbortSignal.timeout(10000) },
      );
    if (locked)
      await db.query(
        "SELECT pg_advisory_unlock(hashtext('wearly-worker-e2e'))",
      );
    await db.end();
    s3.destroy();
  }
}
main().catch((error) => {
  console.error(
    error.message === "BACKUP_NOT_IMPLEMENTED"
      ? "BACKUP_NOT_IMPLEMENTED"
      : "NATIVE_RECOVERY_ACCEPTANCE_FAILED_" + stage,
  );
  process.exitCode = 1;
});
