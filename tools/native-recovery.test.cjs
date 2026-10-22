const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");
const recovery = require("./native-recovery.cjs");
const objects = require("./recovery-objects.cjs");
const postgres = require("./recovery-postgres.cjs");
test('restore metadata requires all schema arrays before any destination writes',()=>{
  assert.throws(()=>postgres.validateSnapshot({tables:{User:{count:1,sha256:'0'.repeat(64)}},schema:{}}),/RECOVERY_INVALID_MANIFEST/);
  assert.throws(()=>postgres.validateSnapshot({tables:[],schema:{}}),/RECOVERY_INVALID_MANIFEST/);
});
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

test("restore refuses an existing destination database before touching storage", async () => {
  let storageCalls = 0;
  const admin = { query: async () => ({ rows: [{ exists: true }] }) };
  await assert.rejects(
    () =>
      recovery.assertFreshTargets(
        admin,
        {
          send: async () => {
            storageCalls++;
          },
        },
        {
          database: "wearly_recovery_1792630000000_abcdef12",
          bucket: "wearly-recovery-1792630000000-abcdef12",
        },
      ),
    /RECOVERY_TARGET_EXISTS/,
  );
  assert.equal(storageCalls, 0);
});
test("restore refuses an existing bucket instead of changing or reusing it", async () => {
  let calls = 0;
  await assert.rejects(
    () =>
      recovery.assertFreshTargets(
        { query: async () => ({ rows: [] }) },
        {
          send: async () => {
            calls++;
            return {};
          },
        },
        {
          database: "wearly_recovery_1792630000000_abcdef12",
          bucket: "wearly-recovery-1792630000000-abcdef12",
        },
      ),
    /RECOVERY_TARGET_EXISTS/,
  );
  assert.equal(calls, 1);
});
test("quarantine cannot mutate a business source even if passed the wrong connection", async () => {
  const queries = [];
  await assert.rejects(
    () =>
      postgres.quarantine(
        {
          query: async (sql) => {
            queries.push(sql);
            return { rows: [{ database: "wearly" }] };
          },
        },
        "wearly_recovery_1792630000000_abcdef12",
      ),
    /RECOVERY_TARGET_REQUIRED/,
  );
  assert.equal(queries.length, 1);
  assert.match(queries[0], /current_database/);
});
test("schema comparison normalizes only equivalent PostgreSQL varchar-array text coercions", () => {
  const source =
    "CHECK (kind::text = ANY (ARRAY['STYLIST'::character varying, 'TRY_ON'::character varying]::text[]))";
  const restored =
    "CHECK (kind::text = ANY (ARRAY['STYLIST'::character varying::text, 'TRY_ON'::character varying::text]))";
  assert.equal(postgres.canonicalConstraint(source), restored);
  const different =
    "CHECK (kind::text = ANY (ARRAY['STYLIST'::integer]::text[]))";
  assert.equal(postgres.canonicalConstraint(different), different);
  assert.notEqual(
    postgres.canonicalConstraint(source.replace("TRY_ON", "OTHER")),
    restored,
  );
  assert.equal(
    postgres.canonicalConstraint(
      "ARRAY['contains ::character varying'::character varying]::text[]",
    ),
    "ARRAY['contains ::character varying'::character varying::text]",
  );
});
test("corrupt archive is refused before any restore directory or target is created", async (t) => {
  const root = folder(t);
  fs.mkdirSync(path.join(root, ".tools"));
  const loc = recovery.locations(root),
    archive = path.join(loc.base, Date.now() + "-" + randomUUID());
  fs.mkdirSync(archive);
  fs.writeFileSync(path.join(archive, "database.dump"), "corrupt");
  fs.writeFileSync(
    path.join(archive, "manifest.json"),
    JSON.stringify({
      version: 1,
      status: "complete",
      files: [{ file: "database.dump", size: 7, sha256: "0".repeat(64) }],
    }),
  );
  const before = fs.readdirSync(loc.base);
  await assert.rejects(
    recovery.restore(root, archive, { env: config() }),
    /RECOVERY_FILE_MISMATCH/,
  );
  assert.deepEqual(fs.readdirSync(loc.base), before);
});
test("native PostgreSQL environment cannot inherit alternate routing with mixed case keys", () => {
  const env = postgres.environment(
    { password: "current-private-fixture" },
    {
      PATH: "toolchain",
      pghostaddr: "remote.test",
      PGSERVICE: "remote-service",
      pgpassword: "old-private-fixture",
      PGOPTIONS: "unsafe",
    },
  );
  assert.equal(env.PGPASSWORD, "current-private-fixture");
  assert.equal(env.PGOPTIONS, "-c timezone=UTC");
  assert.equal(env.PATH, "toolchain");
  assert(!("pghostaddr" in env));
  assert(!("PGSERVICE" in env));
  assert(!("pgpassword" in env));
});

test("malformed schema is refused before restore output or native configuration access", async (t) => {
  const root = folder(t);
  fs.mkdirSync(path.join(root, '.tools'));
  const loc = recovery.locations(root), archive = path.join(loc.base, Date.now()+'-'+randomUUID());
  fs.mkdirSync(archive);
  const bytes = Buffer.from('fixture');
  fs.writeFileSync(path.join(archive,'database.dump'),bytes);
  fs.writeFileSync(path.join(archive,'manifest.json'),JSON.stringify({version:1,status:'complete',files:[{file:'database.dump',size:bytes.length,sha256:hash(bytes)}],snapshot:{tables:{User:{count:0,sha256:hash('')}},schema:{}},objects:[],bundled:[],source:{database:'wearly',bucket:'wearly'}}));
  const before=fs.readdirSync(loc.base);
  await assert.rejects(recovery.restore(root,archive,{env:config()}),/RECOVERY_INVALID_MANIFEST/);
  assert.deepEqual(fs.readdirSync(loc.base),before);
});

test("application acceptance requires a matching recovery report and fresh bundled asset hashes", (t) => {
  const context = require('./recovery-context.cjs');
  const root=folder(t);fs.mkdirSync(path.join(root,'.tools'));
  const loc=recovery.locations(root), archive=Date.now()+'-'+randomUUID(), dir=path.join(loc.base,archive);
  fs.mkdirSync(dir);fs.mkdirSync(path.join(dir,'bundled'));
  fs.mkdirSync(path.join(root,'frontend/assets/images'),{recursive:true});
  const bytes=Buffer.from('image-fixture'),source=path.join(root,'frontend/assets/images/shirt.jpg');
  fs.writeFileSync(source,bytes);fs.writeFileSync(path.join(dir,'bundled/shirt.jpg'),bytes);
  const schema=Object.fromEntries(['columns','enums','constraints','indexes','triggers','functions','views','sequences'].map(k=>[k,[]]));
  fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify({version:1,status:'complete',files:[{file:'bundled/shirt.jpg',size:bytes.length,sha256:hash(bytes)}],snapshot:{tables:{User:{count:0,sha256:hash('')}},schema},bundled:[{file:'bundled/shirt.jpg',source:'frontend/assets/images/shirt.jpg'}]}));
  const target={database:'wearly_recovery_1792630000000_abcdef12',bucket:'wearly-recovery-1792630000000-abcdef12'}, reportDir=path.join(loc.base,'restore-1792630000000_abcdef12');
  fs.mkdirSync(reportDir);
  const reportFile=path.join(reportDir,'result.json');
  fs.writeFileSync(reportFile,JSON.stringify({version:1,status:'complete',stage:'QUARANTINED',exactSnapshotVerified:true,archive,target}));
  const env={...config(),DATABASE_URL:config().DATABASE_URL.replace('/wearly','/'+target.database),S3_BUCKET:target.bucket};
  assert.throws(()=>context.loadContext(root,undefined,env),/RECOVERY_CONTEXT_REQUIRED/);
  assert.throws(()=>context.loadContext(root,reportFile,{...env,S3_BUCKET:'wrong'}),/RECOVERY_CONTEXT_MISMATCH/);
  assert.equal(context.loadContext(root,reportFile,env).report.applicationCompatibility.assets,'verified');
  fs.writeFileSync(source,'changed');
  assert.throws(()=>context.loadContext(root,reportFile,env),/RECOVERY_ASSETS_MISMATCH/);
  assert.equal(JSON.parse(fs.readFileSync(reportFile)).applicationCompatibility.assets,'mismatched');
  fs.unlinkSync(source);
  assert.throws(()=>context.loadContext(root,reportFile,env),/RECOVERY_ASSETS_MISMATCH/);
});
