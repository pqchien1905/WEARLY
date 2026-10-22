const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");
const recovery = require("./native-recovery.cjs");
const objects = require("./recovery-objects.cjs");
const postgres = require("./recovery-postgres.cjs");
function folder(t) {
  const root = fs.mkdtempSync(
    path.join(os.tmpdir(), "wearly-native-recovery-test-"),
  );
  t.after(() => {
    function clean(dir) {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory() && !e.isSymbolicLink()) {
          clean(p);
          fs.rmdirSync(p);
        } else fs.unlinkSync(p);
      }
    }
    clean(root);
    fs.rmdirSync(root);
  });
  return root;
}
const config = () => ({
  NODE_ENV: "development",
  DATABASE_URL:
    "postgresql://fixture:private-fixture-password@127.0.0.1:5432/wearly",
  S3_ENDPOINT: "http://127.0.0.1:9000",
  S3_BUCKET: "wearly",
  S3_REGION: "us-east-1",
  S3_ACCESS_KEY_ID: "fixture",
  S3_SECRET_ACCESS_KEY: "private-fixture-storage",
});
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
function asset(bytes) {
  const id = randomUUID();
  return {
    id,
    objectKey: `catalog/${id}.png`,
    size: bytes.length,
    sha256: hash(bytes),
    mimeType: "image/png",
  };
}
test("backup accepts configured local business source but rejects remote or production before writing", (t) => {
  assert.equal(recovery.validateConfig(config()).database.database, "wearly");
  for (const patch of [
    { NODE_ENV: "production" },
    {
      DATABASE_URL:
        "postgresql://fixture:private-fixture-password@remote.test/wearly",
    },
    { DATABASE_URL: config().DATABASE_URL + "?options=unsafe" },
    { S3_ENDPOINT: "https://remote.test" },
    { S3_ENDPOINT: "http://127.0.0.1:9000/nested" },
  ]) {
    assert.throws(
      () => recovery.validateConfig({ ...config(), ...patch }),
      (error) => {
        assert(!String(error).includes("private-fixture"));
        return true;
      },
    );
  }
});
test("recovery archive paths reject outside directories and nested links", (t) => {
  const root = folder(t),
    outside = folder(t);
  fs.mkdirSync(path.join(root, "child"));
  fs.symlinkSync(outside, path.join(root, "child/link"), "junction");
  assert.throws(() => recovery.safeFile(root, "../private"));
  assert.throws(() => recovery.safeFile(root, "child/link/private"));
  assert.equal(
    recovery.safeFile(root, "child/archive.dump"),
    path.join(root, "child/archive.dump"),
  );
});
test("managed catalog bytes must match canonical key, size and hash", () => {
  const bytes = Buffer.from("synthetic-image"),
    a = asset(bytes);
  objects.verifyBytes(a, bytes);
  for (const patch of [
    { objectKey: "private/photo.png" },
    { objectKey: "../outside.png" },
    { size: 8 * 1024 * 1024 + 1 },
    { sha256: "0".repeat(64) },
  ])
    assert.throws(() => objects.verifyBytes({ ...a, ...patch }, bytes));
  assert.throws(() => objects.verifyBytes(a, Buffer.from("corrupted-image")));
});
test("object collection refuses a missing or oversized stream instead of certifying partial bytes", async () => {
  await assert.rejects(objects.readBody(undefined, 4));
  await assert.rejects(
    objects.readBody(
      (async function* () {
        yield Buffer.alloc(5);
      })(),
      4,
    ),
  );
  assert.deepEqual(
    await objects.readBody(
      (async function* () {
        yield Buffer.from("ab");
        yield Buffer.from("cd");
      })(),
      4,
    ),
    Buffer.from("abcd"),
  );
});
test("completed archive verifies every listed hash and rejects incomplete or corrupt files", (t) => {
  const root = folder(t),
    bytes = Buffer.from("fixture-dump");
  fs.writeFileSync(path.join(root, "database.dump"), bytes);
  const manifest = {
    version: 1,
    status: "complete",
    files: [{ file: "database.dump", size: bytes.length, sha256: hash(bytes) }],
  };
  recovery.verifyFiles(root, manifest);
  assert.throws(() =>
    recovery.verifyFiles(root, { ...manifest, status: "incomplete" }),
  );
  fs.writeFileSync(path.join(root, "database.dump"), "corrupt");
  assert.throws(() => recovery.verifyFiles(root, manifest));
});
test("native failures do not return private stderr, arguments or environment", async () => {
  await assert.rejects(
    postgres.runNative(
      process.execPath,
      ["-e", 'process.stderr.write("private-fixture-secret");process.exit(9)'],
      {},
    ),
    (error) => {
      assert.equal(error.message, "RECOVERY_NATIVE_COMMAND_FAILED");
      assert(!JSON.stringify(error).includes("private-fixture"));
      return true;
    },
  );
});
