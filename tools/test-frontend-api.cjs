// Bounded real API verification. Only unique synthetic rows in the dedicated
// *_test database are created/deleted; the normal development API stays running.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { randomUUID, createHmac } = require('node:crypto');
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
process.env.PASSWORD_RECOVERY_ENABLED = 'false';
process.env.VNPAY_ENABLED = 'false';
process.chdir(backend);
requireBackend('reflect-metadata');
const { NestFactory } = requireBackend('@nestjs/core');
const { PrismaService } = requireBackend('./dist/database/prisma.service');
const { configureApp } = requireBackend('./dist/bootstrap');
const fixture = 'flutter-test-' + randomUUID();
const browser = process.argv.includes('--browser');
const admin = process.argv.includes('--admin');
const wishlist = process.argv.includes('--wishlist');
const reviews = process.argv.includes('--reviews');
const style = process.argv.includes('--style');
const recovery = process.argv.includes('--recovery');
const payments = process.argv.includes('--payments');
const promotions = process.argv.includes('--promotions');
const shipments = process.argv.includes('--shipments');
const returns = process.argv.includes('--returns');
const promotionCode = 'BROWSER' + fixture.replaceAll('-', '').slice(-12).toUpperCase();
if (admin) {
  process.env.S3_BUCKET = test.TEST_S3_BUCKET || normal.S3_BUCKET + '-test';
  if (!process.env.S3_BUCKET.endsWith('-test') || process.env.S3_BUCKET === normal.S3_BUCKET)
    throw new Error('Catalog browser upload requires a dedicated test bucket.');
}
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
  let smtp, recoveryWorker, recoveryQueue;
  const mails = [];
  if (recovery) {
    const { SMTPServer } = requireBackend('smtp-server');
    smtp = new SMTPServer({ authOptional: true, disabledCommands: ['AUTH', 'STARTTLS'], logger: false,
      onData(stream, _session, callback) {
        let text = '';
        stream.on('data', chunk => { text += chunk.toString(); });
        stream.on('end', () => { mails.push(text); callback(); });
      },
    });
    await new Promise(resolve => smtp.listen(0, '127.0.0.1', resolve));
    Object.assign(process.env, { PASSWORD_RECOVERY_ENABLED: 'true', SMTP_HOST: '127.0.0.1',
      SMTP_PORT: String(smtp.server.address().port), SMTP_SECURE: 'false', SMTP_ALLOW_INSECURE_LOCAL: 'true',
      SMTP_FROM: 'store@example.test', SMTP_USER: '', SMTP_PASSWORD: '',
      PASSWORD_RESET_WEB_URL: 'http://127.0.0.1:4183/#/reset-password',
    });
  }
  const fixtureSecret = randomUUID()+randomUUID();
  if(payments) Object.assign(process.env,{ VNPAY_ENABLED:'true',VNPAY_TMN_CODE:'TEST0001',VNPAY_HASH_SECRET:fixtureSecret,
    VNPAY_RETURN_URL:'http://127.0.0.1:3000/api/v1/payments/vnpay/return',VNPAY_WEB_RETURN_URL:'http://127.0.0.1:4183/#/payments/return' });
  let fixturePaid = false;
  const fixtureHttp = async (_url, init) => {
    const body=JSON.parse(init.body);
    const fields = ['vnp_ResponseId','vnp_Command','vnp_ResponseCode','vnp_Message','vnp_TmnCode','vnp_TxnRef','vnp_Amount','vnp_BankCode','vnp_PayDate','vnp_TransactionNo','vnp_TransactionType','vnp_TransactionStatus','vnp_OrderInfo','vnp_PromotionCode','vnp_PromotionAmount'];
    const reply = {vnp_ResponseId:randomUUID().replaceAll('-',''),vnp_Command:'querydr',vnp_ResponseCode:'00',vnp_Message:'Signed local fixture',vnp_TmnCode:'TEST0001',vnp_TxnRef:body.vnp_TxnRef,vnp_Amount:'52000000',vnp_BankCode:'NCB',vnp_PayDate:'20261021120000',vnp_TransactionNo:String(Date.now()),vnp_TransactionType:'01',vnp_TransactionStatus:fixturePaid?'00':'01',vnp_OrderInfo:'Test',vnp_PromotionCode:'',vnp_PromotionAmount:''};
    reply.vnp_SecureHash=createHmac('sha512',fixtureSecret).update(fields.map(k=>reply[k]).join('|')).digest('hex');
    return Response.json(reply);
  };
  const { AppModule } = requireBackend('./dist/app.module');
  const app = payments
    ? (await requireBackend('@nestjs/testing').Test.createTestingModule({imports:[AppModule]}).overrideProvider('VNPAY_HTTP').useValue(fixtureHttp).compile()).createNestApplication({logger:false})
    : await NestFactory.create(AppModule, { logger: false });
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
    if(payments) app.get(requireBackend('@nestjs/config').ConfigService).set('VNPAY_RETURN_URL',url+'/payments/vnpay/return');
    if (recovery) {
      const { ConfigService } = requireBackend('@nestjs/config');
      const { RecoveryService } = requireBackend('./dist/modules/recovery/recovery.service');
      const { RecoveryWorker } = requireBackend('./dist/worker/recovery.worker');
      const { Queue } = requireBackend('bullmq');
      recoveryWorker = new RecoveryWorker(app.get(ConfigService), app.get(RecoveryService));
      recoveryWorker.onModuleInit();
      recoveryQueue = new Queue('wearly-password-recovery', { prefix: process.env.AI_QUEUE_PREFIX,
        connection: { host: process.env.REDIS_HOST, port: Number(process.env.REDIS_PORT) } });
      const email = fixture + '@example.com', password = 'Browser-original-Password-2026';
      const registered = await fetch(url + '/auth/register', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, name: 'Khôi phục kiểm thử' }) });
      if (registered.status !== 201) throw new Error('Recovery fixture registration failed');
      const account = await registered.json();
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-recovery-browser.cjs')({ root, email, password, url, nextPassword: 'Browser-replaced-Password-2026',
        getLink: async () => {
          for (let i = 0; i < 100; i++) {
            for (const mail of mails) {
              const split = mail.indexOf('\r\n\r\n'), headers = mail.slice(0, split), body = mail.slice(split + 4);
              const decoded = /Content-Transfer-Encoding: base64/i.test(headers)
                ? Buffer.from(body.replace(/\s/g, ''), 'base64').toString()
                : body.replace(/=\r\n/g, '').replace(/=([0-9A-F]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
              const link = decoded.match(/http:\/\/127\.0\.0\.1:4183\/#\/reset-password\?token=[A-Za-z0-9_-]{43}/)?.[0];
              if (link) return link;
            }
            await new Promise(resolve => setTimeout(resolve, 50));
          }
          throw new Error('Local SMTP reset link did not arrive');
        },
      });
      const oldSession = await fetch(url + '/auth/me', { headers: { Authorization: 'Bearer ' + account.accessToken } });
      if (oldSession.status !== 401) throw new Error('Pre-reset session remained active');
      if (await db.passwordResetToken.count({ where: { userId: account.user.id, consumedAt: null } }) !== 0)
        throw new Error('Unconsumed reset token remained');
      console.log('PASS recovery database: token consumed and original session revoked.');
    } else if (returns) {
      const password = 'Browser-only-Password-2026', email = 'admin-' + fixture + '@example.com', customerEmail = 'browser-' + fixture + '@example.com';
      const send = async (method, endpoint, body, token, headers = {}) => {
        const response = await fetch(url + '/' + endpoint, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw Error('Return fixture failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const staff = await send('POST', 'auth/register', { name: 'Returns admin', email, password });
      await db.user.update({ where: { id: staff.user.id }, data: { role: 'ADMIN' } });
      const customer = await send('POST', 'auth/register', { name: 'Returns customer', email: customerEmail, password });
      const address = await send('POST', 'users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      await send('POST', 'admin/promotions', { code: promotionCode, kind: 'FIXED', amount: '50000', active: true }, staff.accessToken);
      await send('POST', 'cart/items', { sku: fixture, quantity: 2 }, customer.accessToken);
      let order = await send('POST', 'orders', { addressId: address.id, expectedSubtotal: '980000', couponCode: promotionCode, expectedDiscount: '50000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      for (const status of ['CONFIRMED', 'SHIPPED', 'DELIVERED']) order = await send('PATCH', 'admin/orders/' + order.id + '/status', { status, expectedVersion: order.version }, staff.accessToken);
      order = await send('POST', 'admin/orders/' + order.id + '/settle-cod', { amount: '960000', reference: 'COD-RETURN-FIXTURE', expectedVersion: order.version }, staff.accessToken);
      await send('POST', 'cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
      let cancelled = await send('POST', 'orders', { addressId: address.id, expectedSubtotal: '490000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      // Explicit synthetic prepaid snapshot; no claim of real gateway acceptance.
      await db.payment.update({ where: { orderId: cancelled.id }, data: { provider: 'vnpay', status: 'PAID', providerTransactionId: 'FIXTURE-' + fixture } });
      cancelled = await send('PATCH', 'admin/orders/' + cancelled.id + '/status', { status: 'CONFIRMED', expectedVersion: cancelled.version }, staff.accessToken);
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-returns-browser.cjs')({ root, email, customerEmail, password, orderId: order.id, cancelId: cancelled.id });
      const returned = await db.order.findUniqueOrThrow({ where: { id: order.id }, include: { returns: { include: { items: true } }, payment: true } });
      if (returned.status !== 'DELIVERED' || returned.payment.status !== 'PAID' || returned.returns.length !== 1 || returned.returns[0].status !== 'RECEIVED' || returned.returns[0].amount.toString() !== '465000' || returned.returns[0].items[0].quantity !== 1) throw Error('Partial return entitlement/state mismatch');
      const stopped = await db.order.findUniqueOrThrow({ where: { id: cancelled.id }, include: { payment: true } });
      if (stopped.status !== 'CANCELLED' || stopped.payment.status !== 'PAID') throw Error('Paid cancellation lost its refund obligation');
      const inventory = await db.inventory.findFirstOrThrow({ where: { variant: { productId: product.id } } });
      if (inventory.quantity !== 9) throw Error('Return/cancellation stock compensation mismatch');
      console.log('PASS partial discounted return, one receipt/restock, paid cancellation retains money; no refund/provider call fabricated.');
    } else if (shipments) {
      const password = 'Browser-only-Password-2026';
      const post = async (endpoint, body, token, headers = {}) => {
        const response = await fetch(url + '/' + endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw Error('Shipment fixture failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const email = 'admin-' + fixture + '@example.com', customerEmail = 'browser-' + fixture + '@example.com';
      const staff = await post('auth/register', { name: 'Shipment admin', email, password });
      await db.user.update({ where: { id: staff.user.id }, data: { role: 'ADMIN' } });
      const customer = await post('auth/register', { name: 'Shipment customer', email: customerEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      const orders = [];
      for (let i = 0; i < 2; i++) {
        await post('cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
        orders.push(await post('orders', { addressId: address.id, expectedSubtotal: '490000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() }));
      }
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-shipment-browser.cjs')({ root, email, customerEmail, password, returnedId: orders[0].id, deliveredId: orders[1].id });
      for (const [index, expected] of [[0, 'RETURNED'], [1, 'DELIVERED']]) {
        const row = await db.order.findUniqueOrThrow({ where: { id: orders[index].id }, include: { shipment: { include: { events: true } }, payment: true, history: true } });
        if (row.status !== expected || row.shipment?.status !== expected || row.shipment.carrier !== 'local_simulator') throw Error('Persisted shipment mismatch');
        if (row.payment.status !== (index === 0 ? 'CANCELLED' : 'PENDING')) throw Error('Shipment incorrectly altered payment');
        if (row.shipment.events.length !== (index === 0 ? 6 : 2)) throw Error('Shipment event history mismatch');
      }
      const inventory = await db.inventory.findFirstOrThrow({ where: { variant: { productId: product.id } } });
      if (inventory.quantity !== 9) throw Error('Returned stock was not restored exactly once');
      console.log('PASS persisted shipment events, return stock compensation, delivered COD unpaid; no external carrier call.');
    } else if (admin) {
      if (await db.storeContent.count() !== 0) throw new Error('Admin content verification requires no pre-existing content; refusing to overwrite it.');
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
      const delivered = await db.order.findUniqueOrThrow({ where: { id: order.id }, include: { payment: { include: { settlement: true } } } });
      if (delivered.status !== 'DELIVERED' || delivered.shippingMethod !== 'standard' || delivered.payment.status !== 'PAID') throw new Error('Persisted order/COD state mismatch');
      if (delivered.payment.settlement?.reference !== 'COD-BROWSER-001' || delivered.payment.settlement?.actorId !== adminUser.user.id || delivered.payment.settlement?.amount.toString() !== '520000') throw new Error('Persisted COD receipt mismatch');
      const activity = await db.adminAuditEvent.findMany({ where: { actorId: adminUser.user.id } });
      if (!saved.images[0].url.startsWith('catalog/images/')) throw new Error('Uploaded catalog image did not persist as the cover');
      const catalog = await db.catalogAsset.findMany({ where: { productId: saved.id } });
      if (catalog.length !== 1 || !catalog[0].verifiedAt || catalog[0].deletedAt) throw new Error('Catalog asset was not verified exactly once');
      for (const action of ['PRODUCT_CREATED', 'PRODUCT_UPDATED', 'PRODUCT_IMAGE_UPLOADED', 'SKU_CREATED', 'SKU_UPDATED', 'CATEGORY_CREATED', 'CATEGORY_RENAMED', 'BRAND_CREATED', 'BRAND_RENAMED', 'INVENTORY_ADJUSTED', 'ORDER_STATUS_CHANGED', 'CONTENT_DRAFT_SAVED', 'CONTENT_PUBLISHED']) {
        if (!activity.some(event => event.action === action)) throw new Error('Missing persisted admin activity: ' + action);
      }
      if (activity.filter(event => event.action === 'ORDER_STATUS_CHANGED' && event.targetId === order.id).length !== 3) throw new Error('Order activity cardinality mismatch');
      const content = await db.storeContent.findUniqueOrThrow({ where: { key: 'storefront' } });
      if (content.version !== 3 || content.publishedVersion !== 2 || content.banner !== 'Bản nháp tiếp theo' || content.publishedBanner !== 'Campaign kiểm thử' || content.publishedPolicy !== 'Chính sách kiểm thử đã xuất bản.') throw new Error('Draft/public content isolation mismatch');
      console.log('PASS persistent admin history: authenticated actor and all thirteen action categories; draft/public content isolation and verified catalog cover.');
      console.log('PASS database assertions: product, SKU, gallery, stock, delivered COD with explicit collection receipt.');
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
    } else if (browser || payments || promotions) {
      const promotion = promotions ? {code:promotionCode,adminEmail:'admin-'+fixture+'@example.com',password:'Browser-only-Password-2026'} : null;
      if(promotion) {
        const response=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:promotion.adminEmail,password:promotion.password,name:'Promotion admin'})});
        if(response.status!==201)throw Error('Promotion admin fixture failed');
        const account=await response.json();await db.user.update({where:{id:account.user.id},data:{role:'ADMIN'}});
      }
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-api-browser.cjs')({ root, url, fixture, payments, promotion, markFixturePaid:()=>{fixturePaid=true;} });
      if(promotions) {
        const order=await db.order.findFirstOrThrow({where:{user:{email:'browser-'+fixture+'@example.com'}},include:{payment:true,redemption:true}});
        if(order.total.toString()!=='470000'||order.discount.toString()!=='50000'||order.couponCode!==promotionCode||order.status!=='CANCELLED'||!order.redemption?.releasedAt)throw Error('Promotion snapshot or release mismatch');
        const coupon=await db.coupon.findUniqueOrThrow({where:{code:promotionCode}});
        if(coupon.usageLimit!==1 || await db.couponRedemption.count({where:{couponId:coupon.id,releasedAt:null}})!==0)throw Error('Coupon quota was not released');
        console.log('PASS promotion: browser admin creation, server quote, order discount snapshot and quota released on cancellation.');
      }
      if(payments) {
        const order=await db.order.findFirstOrThrow({where:{user:{email:'browser-'+fixture+'@example.com'}},include:{payment:{include:{attempts:true}}}});
        if(order.payment.provider!=='vnpay' || order.payment.status!=='PAID' || order.payment.attempts.length!==1 || order.payment.attempts[0].status!=='PAID')throw Error('VNPay fixture persistence mismatch');
        console.log('PASS persisted VNPay state from signed LOCAL FIXTURE, not a real provider response.');
      }
    } else {
      await flutter(['test', 'test/live_shopping_test.dart', '--reporter', 'expanded', '--dart-define=LIVE_SHOPPING_API_URL=' + url, '--dart-define=LIVE_SHOPPING_FIXTURE=' + fixture]);
    }
    console.log('PASS real PostgreSQL shopping; normal development database untouched.');
  } finally {
    await recoveryWorker?.onModuleDestroy();
    if (recoveryQueue) { await recoveryQueue.obliterate({ force: true }); await recoveryQueue.close(); }
    // Restrict every cleanup to this run's exact account emails/product IDs.
    try {
      const users = await db.user.findMany({ where: { email: { in: [fixture + '@example.com', 'browser-' + fixture + '@example.com', 'admin-' + fixture + '@example.com'] } }, select: { id: true } });
      const owner = { userId: { in: users.map(user => user.id) } };
      if (admin) {
        const { StorageService } = requireBackend('./dist/integrations/storage/storage.service');
        const assets = await db.catalogAsset.findMany({ where: { actorId: owner.userId } });
        await app.get(StorageService).deleteObjects(assets.map(asset => asset.objectKey));
        await db.catalogAsset.deleteMany({ where: { id: { in: assets.map(asset => asset.id) } } });
      }
      await db.$transaction(async tx => {
        const contentEvents = await tx.adminAuditEvent.findMany({
          where: { actorId: owner.userId, action: 'CONTENT_DRAFT_SAVED' }, select: { targetId: true },
        });
        await tx.storeContent.deleteMany({ where: { id: { in: contentEvents.map(event => event.targetId) } } });
        await tx.adminAuditEvent.deleteMany({ where: { actorId: owner.userId } });
        await tx.review.deleteMany({ where: owner });
        await tx.inventoryMovement.deleteMany({ where: { order: owner } });
        await tx.paymentAttempt.deleteMany({ where: { payment: { order: owner } } });
        await tx.couponRedemption.deleteMany({where:{order:owner}});
        if(promotions || returns) await tx.coupon.deleteMany({where:{code:promotionCode}});
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
    } finally {
      await app.close();
      if (smtp) await new Promise(resolve => smtp.close(resolve));
    }
  }
}
const deadline = setTimeout(() => { console.error('Integration verification exceeded 10 minutes.'); process.exit(1); }, 600000);
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
