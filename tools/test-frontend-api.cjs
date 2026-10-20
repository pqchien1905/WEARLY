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
const admin = process.argv.includes('--admin');
const wishlist = process.argv.includes('--wishlist');
const reviews = process.argv.includes('--reviews');
const style = process.argv.includes('--style');
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
    if (admin) {
      const password = 'Browser-only-Password-2026';
      const post = async (path, body, token, headers = {}) => {
        const res = await fetch(url + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!res.ok) throw new Error('Admin fixture request failed: ' + path + ' ' + res.status);
        return res.json();
      };
      const email = 'admin-' + fixture + '@example.com';
      const adminUser = await post('auth/register', { name: 'Quản trị kiểm thử', email, password });
      await db.user.update({ where: { id: adminUser.user.id }, data: { role: 'ADMIN' } });
      const customerEmail = 'browser-' + fixture + '@example.com';
      const customer = await post('auth/register', { name: 'Khách kiểm thử', email: customerEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      await post('cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
      const order = await post('orders', { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: '490000' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-admin-browser.cjs')({ root, fixture, email, customerEmail, password, orderId: order.id });
      const saved = await db.product.findUniqueOrThrow({ where: { slug: fixture + '-admin' }, include: { variants: { include: { inventory: true } }, images: true, category: true, brand: true } });
      if (!saved.active || saved.variants.length !== 1 || saved.variants[0].inventory.quantity !== 8 || saved.variants[0].price.toString() !== '700000' || saved.images.length !== 1) throw new Error('Persisted admin product does not match browser operations');
      if (saved.category.slug !== fixture + '-taxonomy' || saved.category.name !== 'BST thu đông kiểm thử' || saved.brand.slug !== fixture + '-taxonomy' || saved.brand.name !== 'Studio thu đông kiểm thử') throw new Error('Product taxonomy assignment did not persist');
      const delivered = await db.order.findUniqueOrThrow({ where: { id: order.id }, include: { payment: true } });
      if (delivered.status !== 'DELIVERED' || delivered.payment.status !== 'PENDING') throw new Error('Persisted order/COD state mismatch');
      const activity = await db.adminAuditEvent.findMany({ where: { actorId: adminUser.user.id } });
      for (const action of ['PRODUCT_CREATED', 'PRODUCT_UPDATED', 'SKU_CREATED', 'SKU_UPDATED', 'CATEGORY_CREATED', 'CATEGORY_RENAMED', 'BRAND_CREATED', 'BRAND_RENAMED', 'INVENTORY_ADJUSTED', 'ORDER_STATUS_CHANGED']) {
        if (!activity.some(event => event.action === action)) throw new Error('Missing persisted admin activity: ' + action);
      }
      if (activity.filter(event => event.action === 'ORDER_STATUS_CHANGED' && event.targetId === order.id).length !== 3) throw new Error('Order activity cardinality mismatch');
      console.log('PASS persistent admin history: authenticated actor and all ten action categories.');
      console.log('PASS database assertions: product, SKU, gallery, stock, order delivered with COD pending.');
    } else if (style) {
      const password = 'Browser-only-Password-2026';
      const send = async (method, endpoint, body, token) => {
        const response = await fetch(url + '/' + endpoint, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
        if (!response.ok) throw new Error('Style fixture request failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const email = fixture + '@example.com', otherEmail = 'browser-' + fixture + '@example.com';
      const buyer = await send('POST', 'auth/register', { name: 'Khách hồ sơ phong cách', email, password });
      const other = await send('POST', 'auth/register', { name: 'Khách hồ sơ mới', email: otherEmail, password });
      const address = await send('POST', 'users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, buyer.accessToken);
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-style-browser.cjs')({ root, email, otherEmail, password,
        changeStyle: async () => {
          const before = await send('GET', 'users/me/style', null, buyer.accessToken);
          await send('PUT', 'users/me/style', { size: 'XS', style: 'Thanh lịch', color: 'Đen', budget: '2500000', expectedVersion: before.version }, buyer.accessToken);
        },
      });
      const saved = await db.stylePreference.findUniqueOrThrow({ where: { userId: buyer.user.id } });
      if (saved.size !== 'XL' || saved.style !== 'Thanh lịch' || saved.color !== 'Đen' || saved.budget.toFixed(0) !== '2500000' || saved.version !== 4) throw new Error('Style profile persistence mismatch');
      if (await db.stylePreference.count({ where: { userId: other.user.id } }) !== 0) throw new Error('Reading defaults created a profile');
      if (!(await db.address.findFirst({ where: { id: address.id, userId: buyer.user.id } }))) throw new Error('Style write altered address data');
      console.log('PASS database assertions: version4 exact preferences, other account remains default, address preserved.');
    } else if (reviews) {
      const password = 'Browser-only-Password-2026';
      const post = async (path, body, token, headers = {}) => {
        const response = await fetch(url + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw new Error('Review fixture request failed: ' + path + ' ' + response.status);
        return response.json();
      };
      const buyerEmail = fixture + '@example.com', otherEmail = 'browser-' + fixture + '@example.com';
      const buyer = await post('auth/register', { name: 'Khách đã nhận hàng', email: buyerEmail, password });
      await post('auth/register', { name: 'Khách chưa mua', email: otherEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, buyer.accessToken);
      await post('cart/items', { sku: fixture, quantity: 1 }, buyer.accessToken);
      const order = await post('orders', { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: '490000' }, buyer.accessToken, { 'Idempotency-Key': randomUUID() });
      // Synthetic fixture only: delivery is the eligibility precondition under test.
      await db.order.update({ where: { id: order.id }, data: { status: 'DELIVERED' } });
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-reviews-browser.cjs')({ root, fixture, buyerEmail, otherEmail, password,
        // Only this run's synthetic product can be hidden/restored by the browser scenario.
        setProductAvailable: active => db.product.update({ where: { id: product.id }, data: { active } }),
      });
      const saved = await db.review.findMany({ where: { productId: product.id } });
      if (saved.length !== 1 || saved[0].userId !== buyer.user.id || saved[0].rating !== 5 || saved[0].comment !== 'Mặc rất thoải mái.') throw new Error('Review persistence/ownership mismatch');
      console.log('PASS database assertions: one verified buyer review, exact edited content and rating.');
    } else if (wishlist) {
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-wishlist-browser.cjs')({ root, fixture });
      const saved = await db.wishlistItem.findMany({ where: { user: { email: 'browser-' + fixture + '@example.com' } } });
      if (saved.length !== 1 || saved[0].productId !== product.id) throw new Error('Wishlist was not persisted for first customer');
      if (await db.wishlistItem.count({ where: { user: { email: fixture + '@example.com' } } }) !== 0) throw new Error('Wishlist crossed customer accounts');
      console.log('PASS database assertions: first customer saved product, second customer empty.');
    } else if (browser) {
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-api-browser.cjs')({ root, url, fixture });
    } else {
      await flutter(['test', 'test/live_shopping_test.dart', '--reporter', 'expanded', '--dart-define=LIVE_SHOPPING_API_URL=' + url, '--dart-define=LIVE_SHOPPING_FIXTURE=' + fixture]);
    }
    console.log('PASS real PostgreSQL shopping; normal development database untouched.');
  } finally {
    // Restrict every cleanup to this run's exact account emails/product IDs.
    try {
      const users = await db.user.findMany({ where: { email: { in: [fixture + '@example.com', 'browser-' + fixture + '@example.com', 'admin-' + fixture + '@example.com'] } }, select: { id: true } });
      const owner = { userId: { in: users.map(user => user.id) } };
      await db.$transaction(async tx => {
        await tx.adminAuditEvent.deleteMany({ where: { actorId: owner.userId } });
        await tx.review.deleteMany({ where: owner });
        await tx.inventoryMovement.deleteMany({ where: { order: owner } });
        await tx.payment.deleteMany({ where: { order: owner } });
        await tx.orderItem.deleteMany({ where: { order: owner } });
        await tx.order.deleteMany({ where: owner });
        await tx.user.deleteMany({ where: { id: owner.userId } });
        const products = await tx.product.findMany({ where: { slug: { in: [fixture, fixture + '-admin'] } }, select: { id: true } });
        const productIds = { in: products.map(p => p.id) };
        await tx.inventoryMovement.deleteMany({ where: { inventory: { variant: { productId: productIds } } } });
        await tx.inventory.deleteMany({ where: { variant: { productId: productIds } } });
        await tx.productVariant.deleteMany({ where: { productId: productIds } });
        await tx.product.deleteMany({ where: { id: productIds } });
        if (category) await tx.category.delete({ where: { id: category.id } });
        if (brand) await tx.brand.delete({ where: { id: brand.id } });
        await tx.category.deleteMany({ where: { slug: fixture + '-taxonomy' } });
        await tx.brand.deleteMany({ where: { slug: fixture + '-taxonomy' } });
      });
    } finally { await app.close(); }
  }
}
const deadline = setTimeout(() => { console.error('Integration verification exceeded 10 minutes.'); process.exit(1); }, 600000);
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
