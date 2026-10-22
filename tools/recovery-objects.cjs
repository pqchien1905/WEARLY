const { createHash } = require("node:crypto");
const fs = require("node:fs"),
  path = require("node:path"),
  { createRequire } = require("node:module");
const req = createRequire(path.resolve(__dirname, "../backend/package.json"));
const fail = (code) => {
  throw Error(code);
};
function verifyBytes(asset, bytes) {
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
  if (
    !uuid.test(asset.id) ||
    !["image/png", "image/jpeg"].includes(asset.mimeType) ||
    asset.objectKey !==
      `catalog/${asset.id}${asset.mimeType === "image/png" ? ".png" : ".jpg"}` ||
    !Number.isInteger(asset.size) ||
    asset.size < 1 ||
    asset.size > 8 * 1024 * 1024 ||
    !/^[a-f0-9]{64}$/.test(asset.sha256)
  )
    fail("RECOVERY_INVALID_ASSET");
  if (
    bytes.length !== asset.size ||
    createHash("sha256").update(bytes).digest("hex") !== asset.sha256
  )
    fail("RECOVERY_OBJECT_MISMATCH");
}
async function readBody(body, maximum) {
  if (!body || typeof body[Symbol.asyncIterator] !== "function")
    fail("RECOVERY_OBJECT_MISSING");
  const chunks = [];
  let total = 0;
  try {
    for await (const chunk of body) {
      total += chunk.length;
      if (total > maximum) fail("RECOVERY_OBJECT_LIMIT");
      chunks.push(Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
  } finally {
    body.destroy?.();
  }
}
async function privateBucket(s3, bucket) {
  const sdk = req("@aws-sdk/client-s3");
  try {
    await s3.send(new sdk.GetBucketPolicyCommand({ Bucket: bucket }), {
      abortSignal: AbortSignal.timeout(10000),
    });
    fail("RECOVERY_PRIVATE_BUCKET_REQUIRED");
  } catch (error) {
    if (!["NoSuchBucketPolicy", "NoSuchBucketPolicyError"].includes(error.name))
      throw Error("RECOVERY_PRIVATE_BUCKET_REQUIRED");
  }
  const state = await s3.send(
    new sdk.GetBucketVersioningCommand({ Bucket: bucket }),
    { abortSignal: AbortSignal.timeout(10000) },
  );
  if (state.Status) fail("RECOVERY_UNVERSIONED_BUCKET_REQUIRED");
}
async function collectObjects(client, s3, bucket, directory, workspace) {
  const { GetObjectCommand } = req("@aws-sdk/client-s3");
  await privateBucket(s3, bucket);
  const assets = (
    await client.query(
      'SELECT id,"objectKey","mimeType",size,sha256 FROM public."CatalogAsset" WHERE "verifiedAt" IS NOT NULL AND "deletedAt" IS NULL AND "purgedAt" IS NULL ORDER BY id LIMIT 10001',
    )
  ).rows;
  if (assets.length > 10000) fail("RECOVERY_ARCHIVE_LIMIT");
  fs.mkdirSync(path.join(directory, "objects"));
  fs.mkdirSync(path.join(directory, "bundled"));
  const files = [],
    objects = [],
    bundled = [];
  let total = 0;
  const deadline = Date.now() + 120000;
  const save = (name, bytes) => {
    total += bytes.length;
    if (
      total > 1024 * 1024 * 1024 ||
      files.length >= 10000 ||
      Date.now() > deadline
    )
      fail("RECOVERY_ARCHIVE_LIMIT");
    fs.writeFileSync(path.join(directory, name), bytes, {
      flag: "wx",
      mode: 0o600,
    });
    files.push({
      file: name,
      size: bytes.length,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    });
  };
  for (const asset of assets) {
    // Validate metadata before using its key on the object service.
    if (
      !/^catalog\/[a-f0-9-]+\.(png|jpg)$/.test(asset.objectKey) ||
      asset.size < 1 ||
      asset.size > 8 * 1024 * 1024
    )
      fail("RECOVERY_INVALID_ASSET");
    const response = await s3.send(
      new GetObjectCommand({ Bucket: bucket, Key: asset.objectKey }),
      { abortSignal: AbortSignal.timeout(10000) },
    );
    const bytes = await readBody(response.Body, 8 * 1024 * 1024);
    verifyBytes(asset, bytes);
    const file = "objects/" + path.basename(asset.objectKey);
    save(file, bytes);
    objects.push({ ...asset, file });
  }
  const source = path.join(workspace, "frontend/assets/images");
  if (
    fs.lstatSync(source).isSymbolicLink() ||
    !fs.lstatSync(source).isDirectory()
  )
    fail("RECOVERY_UNSAFE_PATH");
  for (const entry of fs
    .readdirSync(source, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))) {
    if (
      !entry.isFile() ||
      entry.isSymbolicLink() ||
      !/^[a-zA-Z0-9_.-]+$/.test(entry.name)
    )
      fail("RECOVERY_UNSAFE_PATH");
    const file = path.join(source, entry.name),
      stat = fs.statSync(file);
    if (stat.size > 8 * 1024 * 1024) fail("RECOVERY_OBJECT_LIMIT");
    const bytes = fs.readFileSync(file),
      archived = "bundled/" + entry.name;
    save(archived, bytes);
    bundled.push({
      source: "frontend/assets/images/" + entry.name,
      file: archived,
    });
  }
  const external = (
    await client.query(
      'SELECT count(*)::int AS count FROM public."ProductImage" WHERE url NOT LIKE $1 AND url NOT LIKE $2',
      ["assets/images/%", "catalog/images/%"],
    )
  ).rows[0].count;
  return {
    files,
    objects,
    bundled,
    exclusions: {
      privateTryOnBytes: "not backed up",
      externalCatalogReferences: external,
    },
  };
}
module.exports = { verifyBytes, readBody, privateBucket, collectObjects };
