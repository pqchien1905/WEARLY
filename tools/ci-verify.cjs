const fs = require("node:fs"),
  path = require("node:path"),
  { createHash, randomUUID } = require("node:crypto"),
  { createRequire } = require("node:module");
const requireBackend = createRequire(
  path.resolve(__dirname, "../backend/package.json"),
);
const { runCommand } = require("./local-runtime.cjs");
const fail = (code) => {
  throw Error(code);
};
const digest = (file) =>
  createHash("sha256").update(fs.readFileSync(file)).digest("hex");
function safe(file, directory = false) {
  try {
    const s = fs.lstatSync(file);
    if (s.isSymbolicLink() || (directory ? !s.isDirectory() : !s.isFile()))
      fail("UNSAFE_CI_PATH");
    return true;
  } catch (e) {
    if (e.code === "ENOENT") return false;
    throw e;
  }
}
function files(root) {
  const workspace = fs.realpathSync(root);
  safe(path.join(workspace, "backend"), true);
  safe(path.join(workspace, ".tools"), true);
  safe(path.join(workspace, ".tools/ci"), true);
  return {
    workspace,
    env: path.join(workspace, "backend/.env"),
    test: path.join(workspace, "backend/.env.test"),
    directory: path.join(workspace, ".tools/ci"),
    manifest: path.join(workspace, ".tools/ci/manifest.json"),
  };
}
function configuration(input) {
  const local = (host) =>
    ["localhost", "127.0.0.1", "[::1]", "::1"].includes(host);
  for (const key of [
    "GEMINI_API_KEY",
    "VNPAY_TMN_CODE",
    "VNPAY_HASH_SECRET",
    "AI_PROVIDER_URL",
    "AI_PROVIDER_API_KEY",
  ])
    if (String(input[key] ?? "").trim()) fail("CI_PROVIDERS_DISABLED_REQUIRED");
  for (const key of [
    "VNPAY_ENABLED",
    "LOCAL_MAIL_ENABLED",
    "MAIL_DELIVERY_ENABLED",
    "PASSWORD_RECOVERY_ENABLED",
  ])
    if (input[key] && input[key] !== "false")
      fail("CI_PROVIDERS_DISABLED_REQUIRED");
  if (input.NODE_ENV && input.NODE_ENV !== "test")
    fail("CI_TEST_MODE_REQUIRED");
  const database =
    input.CI_DATABASE_URL ??
    "postgresql://wearly_ci:ci-fixture-password-only@127.0.0.1:5432/wearly_ci_test";
  const redisHost = input.CI_REDIS_HOST ?? "127.0.0.1",
    redisPort = Number(input.CI_REDIS_PORT ?? 6379),
    endpoint = input.CI_S3_ENDPOINT ?? "http://127.0.0.1:9000";
  try {
    const db = new URL(database),
      s3 = new URL(endpoint);
    if (
      !["postgres:", "postgresql:"].includes(db.protocol) ||
      !local(db.hostname) ||
      db.pathname !== "/wearly_ci_test" ||
      db.username !== "wearly_ci" ||
      db.password !== "ci-fixture-password-only" ||
      db.search ||
      db.hash ||
      !local(redisHost) ||
      !Number.isInteger(redisPort) ||
      redisPort < 1 ||
      redisPort > 65535 ||
      !local(s3.hostname) ||
      s3.protocol !== "http:" ||
      s3.username ||
      s3.password ||
      s3.search ||
      s3.hash
    )
      fail("CI_SYNTHETIC_SERVICES_REQUIRED");
  } catch {
    fail("CI_SYNTHETIC_SERVICES_REQUIRED");
  }
  return {
    NODE_ENV: "test",
    HOST: "127.0.0.1",
    PORT: "3000",
    DATABASE_URL: database,
    TEST_DATABASE_URL: database,
    REDIS_HOST: redisHost,
    REDIS_PORT: String(redisPort),
    TEST_REDIS_HOST: redisHost,
    TEST_REDIS_PORT: String(redisPort),
    AI_QUEUE_PREFIX: "ci-" + randomUUID(),
    JWT_ACCESS_SECRET: randomUUID() + randomUUID(),
    JWT_REFRESH_SECRET: randomUUID() + randomUUID(),
    CORS_ORIGINS: "http://localhost:8080",
    SWAGGER_ENABLED: "false",
    S3_ENDPOINT: endpoint,
    TEST_S3_ENDPOINT: endpoint,
    S3_REGION: "us-east-1",
    S3_BUCKET: "wearly-ci-test",
    TEST_S3_BUCKET: "wearly-ci-test",
    S3_ACCESS_KEY_ID: "ci-fixture",
    S3_SECRET_ACCESS_KEY: "ci-storage-fixture-only",
    S3_PUBLIC_ENDPOINT: "",
    GEMINI_API_KEY: " ",
    VNPAY_ENABLED: "false",
    VNPAY_TMN_CODE: "",
    VNPAY_HASH_SECRET: "",
    AI_PROVIDER_URL: "",
    AI_PROVIDER_API_KEY: "",
    LOCAL_MAIL_ENABLED: "false",
    MAIL_DELIVERY_ENABLED: "false",
    PASSWORD_RECOVERY_ENABLED: "false",
  };
}
function prepareEnvironment(root, input) {
  // Validate every resource before making directories, writing files or connecting.
  const env = configuration(input),
    f = files(root);
  if (safe(f.env) || safe(f.test) || safe(f.manifest))
    fail("CI_ENV_ALREADY_EXISTS");
  const created = [];
  try {
    const text =
      "# Synthetic CI only; never use for a store.\n" +
      Object.entries(env)
        .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
        .join("\n") +
      "\n";
    fs.writeFileSync(f.env, text, { flag: "wx", mode: 0o600 });
    created.push(f.env);
    const testText =
      Object.entries(env)
        .filter(([key]) => key.startsWith("TEST_"))
        .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
        .join("\n") + "\n";
    fs.writeFileSync(f.test, testText, { flag: "wx", mode: 0o600 });
    created.push(f.test);
    const tools = path.dirname(f.directory);
    if (!safe(tools, true)) fs.mkdirSync(tools);
    if (!safe(f.directory, true)) fs.mkdirSync(f.directory);
    fs.writeFileSync(
      f.manifest,
      JSON.stringify({
        workspace: f.workspace,
        env: digest(f.env),
        test: digest(f.test),
      }),
      { flag: "wx", mode: 0o600 },
    );
  } catch (error) {
    for (const file of created) fs.unlinkSync(file);
    throw error;
  }
}
function readEnvironment(root) {
  const f = files(root);
  if (!safe(f.env) || !safe(f.test) || !safe(f.manifest))
    fail("CI_ENV_NOT_PREPARED");
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(f.manifest, "utf8"));
  } catch {
    fail("CI_ENV_CHANGED");
  }
  if (
    manifest.workspace !== f.workspace ||
    manifest.env !== digest(f.env) ||
    manifest.test !== digest(f.test)
  )
    fail("CI_ENV_CHANGED");
  const env = requireBackend("dotenv").parse(fs.readFileSync(f.env));
  // Recheck safety independently of hashes, rather than trusting a prepared marker.
  configuration({
    ...env,
    CI_DATABASE_URL: env.DATABASE_URL,
    CI_REDIS_HOST: env.REDIS_HOST,
    CI_REDIS_PORT: env.REDIS_PORT,
    CI_S3_ENDPOINT: env.S3_ENDPOINT,
  });
  if (
    env.S3_BUCKET !== "wearly-ci-test" ||
    env.TEST_DATABASE_URL !== env.DATABASE_URL ||
    env.TEST_S3_BUCKET !== env.S3_BUCKET
  )
    fail("CI_SYNTHETIC_SERVICES_REQUIRED");
  return env;
}
function npmCli() {
  const candidates = [
    path.join(
      path.dirname(process.execPath),
      "node_modules/npm/bin/npm-cli.js",
    ),
    path.resolve(
      path.dirname(process.execPath),
      "../lib/node_modules/npm/bin/npm-cli.js",
    ),
  ];
  const found = candidates.find(fs.existsSync);
  if (!found) fail("NPM_CLI_NOT_FOUND");
  return found;
}
async function runStage(root, stage, run = runCommand) {
  const env = { ...process.env, ...readEnvironment(root), GEMINI_API_KEY: " " };
  if (Number(process.versions.node.split(".")[0]) !== 24)
    fail("NODE_24_REQUIRED");
  if (stage === "backend") {
    for (const name of ["lint", "build", "test", "prisma:deploy", "test:e2e"])
      await run(process.execPath, [npmCli(), "run", name], {
        cwd: path.join(root, "backend"),
        env,
      });
  } else if (stage === "frontend") {
    for (const args of [
      ["pub", "get", "--enforce-lockfile"],
      ["analyze", "--no-pub"],
      ["test", "--no-pub", "--reporter", "expanded"],
    ])
      await run("flutter", args, { cwd: path.join(root, "frontend"), env });
  } else if (stage === "tools") {
    const tests = fs
      .readdirSync(path.join(root, "tools"))
      .filter((name) => name.endsWith(".test.cjs"))
      .sort()
      .map((name) => path.join("tools", name));
    await run(process.execPath, ["--test", ...tests], { cwd: root, env });
  } else fail("INVALID_CI_STAGE");
}
async function storage(root) {
  const env = readEnvironment(root),
    { S3Client, HeadBucketCommand, CreateBucketCommand } =
      requireBackend("@aws-sdk/client-s3");
  const client = new S3Client({
    endpoint: env.S3_ENDPOINT,
    region: env.S3_REGION,
    forcePathStyle: true,
    maxAttempts: 1,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    },
  });
  try {
    for (let attempt = 0; attempt < 10; attempt++) {
      try {
        await client.send(new HeadBucketCommand({ Bucket: env.S3_BUCKET }), {
          abortSignal: AbortSignal.timeout(1500),
        });
        return;
      } catch (error) {
        if (error.$metadata?.httpStatusCode === 404) {
          await client.send(
            new CreateBucketCommand({ Bucket: env.S3_BUCKET }),
            { abortSignal: AbortSignal.timeout(2000) },
          );
          return;
        }
        if (attempt === 9) fail("CI_STORAGE_UNAVAILABLE");
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
  } finally {
    client.destroy();
  }
}
module.exports = { prepareEnvironment, readEnvironment, runStage };
if (require.main === module) {
  (async () => {
    const root = path.resolve(__dirname, ".."),
      stage = process.argv[2];
    if (stage === "prepare") prepareEnvironment(root, process.env);
    else if (stage === "storage") await storage(root);
    else await runStage(root, stage);
    console.log("PASS CI " + stage);
  })().catch((error) => {
    console.error(
      /^[A-Z][A-Z0-9_]+$/.test(error.message)
        ? error.message
        : "CI_VERIFICATION_FAILED",
    );
    process.exitCode = 1;
  });
}
