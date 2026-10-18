// Run only against the local development MinIO instance; never changes a bucket policy.
const { createRequire } = require('node:module');
const path = require('node:path');
const fs = require('node:fs');
const backend = path.join(__dirname, '../backend');
const fromBackend = createRequire(path.join(backend, 'package.json'));
const config = fromBackend('dotenv').parse(fs.readFileSync(path.join(backend, '.env')));
const { S3Client, HeadBucketCommand, CreateBucketCommand, GetBucketPolicyCommand, GetBucketVersioningCommand } = fromBackend('@aws-sdk/client-s3');
async function main() {
  if (!['http://127.0.0.1:9000', 'http://localhost:9000'].includes(config.S3_ENDPOINT)) throw new Error('Local storage endpoint required');
  const client = new S3Client({ endpoint: config.S3_ENDPOINT, region: config.S3_REGION, forcePathStyle: true, maxAttempts: 2, credentials: { accessKeyId: config.S3_ACCESS_KEY_ID, secretAccessKey: config.S3_SECRET_ACCESS_KEY } });
  try {
    for (const Bucket of [config.S3_BUCKET, config.S3_BUCKET + '-test']) {
      try { await client.send(new HeadBucketCommand({ Bucket })); }
      catch (error) {
        if (error.$metadata?.httpStatusCode !== 404) throw error;
        await client.send(new CreateBucketCommand({ Bucket }));
      }
      try {
        await client.send(new GetBucketPolicyCommand({ Bucket }));
        throw new Error('Existing bucket policy requires manual inspection; refusing to change it');
      } catch (error) { if (error.name !== 'NoSuchBucketPolicy') throw error; }
      const versioning = await client.send(new GetBucketVersioningCommand({ Bucket }));
      if (versioning.Status) throw new Error('Private-image cleanup requires an unversioned bucket');
      console.log('Private, unversioned bucket ready: ' + Bucket);
    }
  } finally { client.destroy(); }
}
main().catch(error => { console.error(error.name === 'Error' ? error.message : 'Storage setup failed: ' + error.name); process.exitCode = 1; });
