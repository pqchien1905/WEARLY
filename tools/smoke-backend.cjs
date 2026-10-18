// Bounded verification of the compiled API on an OS-assigned loopback port.
// Reads existing data only; closes the application before returning.
const path = require('node:path');
const { createRequire } = require('node:module');
const backend = path.join(__dirname, '../backend');
const fromBackend = createRequire(path.join(backend, 'package.json'));
process.chdir(backend);
fromBackend('reflect-metadata');
const { NestFactory } = fromBackend('@nestjs/core');
const { AppModule } = fromBackend('./dist/app.module');
const { configureApp } = fromBackend('./dist/bootstrap');
async function main() {
  const app = await NestFactory.create(AppModule, { logger: false });
  try {
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    for (const [route, expected] of [['/api/v1/health/ready', 200], ['/api/v1/products', 200], ['/api/v1/uploads/images', 401]]) {
      const response = await fetch(base + route, { signal: AbortSignal.timeout(10000) });
      if (response.status !== expected) throw new Error('Unexpected response for ' + route);
      console.log(route + ': ' + response.status);
    }
    const response = await fetch(base + '/api/docs-json', { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('Development Swagger is required for this smoke test');
    const schema = await response.json();
    if (!schema.paths['/api/v1/uploads/images']?.post || !schema.paths['/api/v1/uploads/images/{id}']?.delete) throw new Error('Compiled upload routes missing');
    console.log('Compiled private upload routes verified; no data was written.');
  } finally { await app.close(); }
}
const deadline = setTimeout(() => { console.error('Smoke test timed out'); process.exit(1); }, 30000);
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
