// Bounded real API verification. Only unique synthetic rows in the dedicated
// *_test database are created/deleted; the normal development API stays running.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const backend = path.join(root, 'backend');
const requireBackend = createRequire(path.join(backend, 'package.json'));
const dotenv = requireBackend('dotenv');
const normal = dotenv.parse(fs.readFileSync(path.join(backend, '.env')));
const test = dotenv.parse(fs.readFileSync(path.join(backend, '.env.test')));
const target = new URL(test.TEST_DATABASE_URL);
if (!/^\/[a-zA-Z0-9_]+_test$/.test(target.pathname) || target.href === new URL(normal.DATABASE_URL).href) {
  throw new Error('A separate *_test database is required.');
}
Object.assign(process.env, normal, { DATABASE_URL: target.href, NODE_ENV: 'test',
  JWT_ACCESS_SECRET: randomUUID() + randomUUID(), JWT_REFRESH_SECRET: randomUUID() + randomUUID(),
  AI_QUEUE_PREFIX: 'flutter-test-' + randomUUID(), CORS_ORIGINS: 'http://127.0.0.1:4183' });
process.chdir(backend);
requireBackend('reflect-metadata');
const { NestFactory } = requireBackend('@nestjs/core');
const { AppModule } = requireBackend('./dist/app.module');
const { PrismaService } = requireBackend('./dist/database/prisma.service');
const { configureApp } = requireBackend('./dist/bootstrap');
const fixture = 'flutter-test-' + randomUUID();
const browser = process.argv.includes('--browser');
function flutter(args) {
  const binary = path.join(root, '.tools/flutter/bin/flutter.bat');
  // All arguments below are local constants, loopback URLs or generated UUIDs.
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `""${binary}" ${args.join(' ')}"`],
      { cwd: path.join(root, 'frontend'), stdio: 'inherit', windowsHide: true, windowsVerbatimArguments: true });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error('Flutter command failed: ' + code)));
  });
}
async function main() {
  const app = await NestFactory.create(AppModule, { logger: false });
  const db = app.get(PrismaService);
  let category, brand, product;
  try {
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    category = await db.category.create({ data: { slug: fixture, name: 'Áo kiểm thử' } });
    brand = await db.brand.create({ data: { slug: fixture, name: 'Wearly kiểm thử' } });
    product = await db.product.create({ data: { slug: fixture, name: 'Áo cotton kiểm thử', description: 'Sản phẩm chỉ dành cho kiểm thử.', material: 'Cotton', style: 'Tối giản',
      categoryId: category.id, brandId: brand.id,
      images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo cotton', position: 0 } },
      variants: { create: { sku: fixture, size: 'M', color: 'Trắng', colorHex: '#FFFFFF', price: '490000', inventory: { create: { quantity: 10 } } } } } });
    const url = (await app.getUrl()) + '/api/v1';
    if (browser) {
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-api-browser.cjs')({ root, url, fixture });
    } else {
      await flutter(['test', 'test/live_shopping_test.dart', '--reporter', 'expanded', '--dart-define=LIVE_SHOPPING_API_URL=' + url, '--dart-define=LIVE_SHOPPING_FIXTURE=' + fixture]);
    }
    console.log('PASS real PostgreSQL shopping; normal development database untouched.');
  } finally {
    // Restrict every cleanup to this run's exact account emails/product IDs.
    try {
      const users = await db.user.findMany({ where: { email: { in: [fixture + '@example.com', 'browser-' + fixture + '@example.com'] } }, select: { id: true } });
      const owner = { userId: { in: users.map(user => user.id) } };
      await db.$transaction(async tx => {
        await tx.inventoryMovement.deleteMany({ where: { order: owner } });
        await tx.payment.deleteMany({ where: { order: owner } });
        await tx.orderItem.deleteMany({ where: { order: owner } });
        await tx.order.deleteMany({ where: owner });
        await tx.user.deleteMany({ where: { id: owner.userId } });
        if (product) {
          await tx.inventory.deleteMany({ where: { variant: { productId: product.id } } });
          await tx.productVariant.deleteMany({ where: { productId: product.id } });
          await tx.product.delete({ where: { id: product.id } });
        }
        if (category) await tx.category.delete({ where: { id: category.id } });
        if (brand) await tx.brand.delete({ where: { id: brand.id } });
      });
    } finally { await app.close(); }
  }
}
const deadline = setTimeout(() => { console.error('Integration verification exceeded 10 minutes.'); process.exit(1); }, 600000);
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
