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
  if (
    !process.argv.includes("--backup-only") &&
    typeof recovery.restore !== "function"
  )
    throw Error("RESTORE_NOT_IMPLEMENTED");
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
  const imageId = randomUUID(),
    usageId = randomUUID(),
    jobId = randomUUID(),
    completedJobId = randomUUID(),
    sessionId = randomUUID(),
    resetId = randomUUID(),
    mailId = randomUUID();
  const privateKey = `users/${id}/images/${imageId}.png`;
  let privateCreated = false;
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
    if (!process.argv.includes("--backup-only")) {
      stage = "FIXTURE";
      const variant = (
        await db.query(
          'SELECT id FROM public."ProductVariant" ORDER BY id LIMIT 1',
        )
      ).rows[0];
      if (!variant) throw Error("SEEDED_TEST_CATALOG_REQUIRED");
      await db.query('UPDATE public."User" SET role=$2 WHERE id=$1', [
        id,
        "ADMIN",
      ]);
      stage = "FIXTURE_SESSION";
      await db.query(
        'INSERT INTO public."RefreshToken" (id,"userId","tokenHash","familyId","browserScope","expiresAt","updatedAt") VALUES ($1,$2,$3,$4,$5,now()+interval \'1 day\',now())',
        [sessionId, id, "session-" + id, randomUUID(), "customer"],
      );
      await db.query(
        'INSERT INTO public."PasswordResetToken" (id,"userId","tokenHash","expiresAt") VALUES ($1,$2,$3,now()+interval \'1 day\')',
        [resetId, id, createHash("sha256").update(id).digest("hex")],
      );
      stage = "FIXTURE_IMAGE";
      await db.query(
        'INSERT INTO public."ImageAsset" (id,"userId","objectKey","mimeType",size,"consentAt","verifiedAt","expiresAt","updatedAt") VALUES ($1,$2,$3,$4,$5,now(),now(),now()+interval \'1 day\',now())',
        [imageId, id, privateKey, "image/png", bytes.length],
      );
      await s3.send(
        new sdk.PutObjectCommand({
          Bucket: config.bucket,
          Key: privateKey,
          Body: bytes,
          ContentType: "image/png",
        }),
        { abortSignal: AbortSignal.timeout(10000) },
      );
      privateCreated = true;
      stage = "FIXTURE_AI";
      await db.query(
        'INSERT INTO public."AiUsage" (id,"userId",kind,"requestKey","inputHash",status,model,"estimatedCostVnd","deadlineAt","expiresAt") VALUES ($1,$2,$3,$4,$5,$6,$7,3000,now()+interval \'1 hour\',now()+interval \'1 day\')',
        [
          usageId,
          id,
          "TRY_ON",
          randomUUID(),
          "b".repeat(64),
          "PROCESSING",
          "gemini-fixture",
        ],
      );
      for (const [job, status, usage] of [
        [jobId, "PENDING", usageId],
        [completedJobId, "COMPLETED", null],
      ])
        await db.query(
          'INSERT INTO public."AIJob" (id,"userId","variantId","imageId",status,"consentAt","updatedAt","usageId") VALUES ($1,$2,$3,$4,$5,now(),now(),$6)',
          [job, id, variant.id, imageId, status, usage],
        );
      await db.query(
        'INSERT INTO public."OutboxEvent" (id,"jobId") VALUES ($1,$2)',
        [randomUUID(), jobId],
      );
      await db.query(
        'INSERT INTO public."TryOnResult" (id,"jobId","objectKey","expiresAt") VALUES ($1,$2,$3,now()+interval \'1 day\')',
        [randomUUID(), completedJobId, "results/" + completedJobId + ".png"],
      );
      stage = "FIXTURE_MAIL";
      await db.query(
        'INSERT INTO public."MailOutbox" (id,"eventKey",recipient,subject,body,status,"leaseToken","leaseUntil","updatedAt") VALUES ($1,$2,$3,$4,$5,$6,$7,now()+interval \'1 hour\',now())',
        [
          mailId,
          "recovery-" + id,
          id + "@recovery.test",
          "Synthetic recovery",
          "Synthetic recovery",
          "PROCESSING",
          randomUUID(),
        ],
      );
    }
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
    if (!process.argv.includes("--backup-only")) {
      stage = "RESTORE";
      await db.query("BEGIN READ ONLY");
      const sourceBefore = await postgres.snapshot(db);
      await db.query("COMMIT");
      const restored = await recovery.restore(root, result.directory, {
        env: testEnv,
      });
      const target = new Client({
        ...config.database,
        database: restored.target.database,
        options: "-c timezone=UTC",
      });
      await target.connect();
      try {
        assert.equal(
          (
            await target.query('SELECT active FROM public."User" WHERE id=$1', [
              id,
            ])
          ).rows[0].active,
          false,
        );
        assert(
          (
            await target.query(
              'SELECT "revokedAt" FROM public."RefreshToken" WHERE id=$1',
              [sessionId],
            )
          ).rows[0].revokedAt,
        );
        assert(
          (
            await target.query(
              'SELECT "consumedAt" FROM public."PasswordResetToken" WHERE id=$1',
              [resetId],
            )
          ).rows[0].consumedAt,
        );
        assert(
          (
            await target.query(
              'SELECT "purgedAt" FROM public."ImageAsset" WHERE id=$1',
              [imageId],
            )
          ).rows[0].purgedAt,
        );
        assert.equal(
          (
            await target.query(
              'SELECT status FROM public."AIJob" WHERE id=$1',
              [jobId],
            )
          ).rows[0].status,
          "FAILED",
        );
        const usage = (
          await target.query(
            'SELECT status,"estimatedCostVnd"::text AS cost FROM public."AiUsage" WHERE id=$1',
            [usageId],
          )
        ).rows[0];
        assert.equal(usage.status, "UNKNOWN");
        assert.equal(usage.cost, "3000");
        assert(
          (
            await target.query(
              'SELECT "publishedAt" FROM public."OutboxEvent" WHERE "jobId"=$1',
              [jobId],
            )
          ).rows[0].publishedAt,
        );
        assert.equal(
          (
            await target.query(
              'SELECT status FROM public."MailOutbox" WHERE id=$1',
              [mailId],
            )
          ).rows[0].status,
          "FAILED",
        );
        assert.equal(
          (
            await target.query(
              'SELECT "expiresAt"<now() AS expired FROM public."TryOnResult" WHERE "jobId"=$1',
              [completedJobId],
            )
          ).rows[0].expired,
          true,
        );
        await assert.rejects(
          s3.send(
            new sdk.HeadObjectCommand({
              Bucket: restored.target.bucket,
              Key: privateKey,
            }),
            { abortSignal: AbortSignal.timeout(10000) },
          ),
          (error) => error.$metadata?.httpStatusCode === 404,
        );
        const object = await s3.send(
          new sdk.GetObjectCommand({
            Bucket: restored.target.bucket,
            Key: objectKey,
          }),
          { abortSignal: AbortSignal.timeout(10000) },
        );
        assert.deepEqual(
          Buffer.from(await object.Body.transformToByteArray()),
          bytes,
        );
      } finally {
        await target.end();
      }
      assert.equal(
        (await db.query('SELECT active FROM public."User" WHERE id=$1', [id]))
          .rows[0].active,
        true,
      );
      assert.equal(
        (
          await db.query('SELECT status FROM public."AIJob" WHERE id=$1', [
            jobId,
          ])
        ).rows[0].status,
        "PENDING",
      );
      await db.query("BEGIN READ ONLY");
      const sourceAfter = await postgres.snapshot(db);
      await db.query("COMMIT");
      assert.deepEqual(sourceAfter, sourceBefore);
      await assert.rejects(
        recovery.assertFreshTargets(db, s3, restored.target),
        /RECOVERY_TARGET_EXISTS/,
      );
      const inspection = req("dotenv").parse(
        fs.readFileSync(restored.inspectionFile),
      );
      console.log(
        (
          await postgres.runNative(
            process.execPath,
            [path.join(__dirname, "verify-recovery-api.cjs")],
            {
              cwd: root,
              env: {
                ...process.env,
                ...inspection,
                RECOVERY_VERIFY_ASSET: assetId,
                RECOVERY_REPORT_FILE: path.join(restored.directory, 'result.json'),
                RECOVERY_VERIFY_HASH: createHash("sha256")
                  .update(bytes)
                  .digest("hex"),
                RECOVERY_VERIFY_USER: id,
                RECOVERY_VERIFY_SESSION: sessionId,
              },
            },
          )
        ).trim(),
      );
      console.log(
        "PASS fresh restore: exact snapshot verified before quarantine; old auth/private images/pending work suppressed; source unchanged.",
      );
    }
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
    if (createdUser) {
      await db.query(
        'DELETE FROM public."OutboxEvent" WHERE "jobId" IN ($1,$2)',
        [jobId, completedJobId],
      );
      await db.query(
        'DELETE FROM public."TryOnResult" WHERE "jobId" IN ($1,$2)',
        [jobId, completedJobId],
      );
      await db.query('DELETE FROM public."AIJob" WHERE id IN ($1,$2)', [
        jobId,
        completedJobId,
      ]);
      await db.query('DELETE FROM public."AiUsage" WHERE id=$1', [usageId]);
      await db.query('DELETE FROM public."ImageAsset" WHERE id=$1', [imageId]);
      await db.query('DELETE FROM public."MailOutbox" WHERE id=$1', [mailId]);
    }
    if (privateCreated)
      await s3.send(
        new sdk.DeleteObjectCommand({ Bucket: config.bucket, Key: privateKey }),
        { abortSignal: AbortSignal.timeout(10000) },
      );
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
    [
      "BACKUP_NOT_IMPLEMENTED",
      "RESTORE_NOT_IMPLEMENTED",
      "SEEDED_TEST_CATALOG_REQUIRED",
    ].includes(error.message)
      ? error.message
      : "NATIVE_RECOVERY_ACCEPTANCE_FAILED_" + stage,
  );
  process.exitCode = 1;
});
