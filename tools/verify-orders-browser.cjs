// Local acceptance with an isolated customer, hidden product and inventory.
// Never uses a real customer's orders or sends email.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, '.tools/orders-redesign');
const origin = process.env.ORDERS_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const email = `orders-${randomUUID().slice(0, 8)}@example.invalid`;
  const report = { origin, passed: [], errors: [] };
  const db = localDatabase();
  let browser, page, session, userId, productId, variantId, inventoryId, releaseRefresh;
  const ids = Array.from({ length: 101 }, () => randomUUID());
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Khách kiểm thử đơn', email, password: randomUUID() + '-Aa1' }),
    });
    assert.equal(registered.status, 201);
    userId = (await registered.json()).user.id;
    const source = await db.product.findFirstOrThrow({ where: { active: true }, include: { images: { take: 1 } } });
    const product = await db.product.create({ data: {
      slug: `orders-qa-${randomUUID()}`, name: 'Áo cotton kiểm thử', active: false,
      description: 'Disposable browser fixture', material: 'Cotton', style: 'QA',
      categoryId: source.categoryId, brandId: source.brandId,
      variants: { create: { sku: `ORDERS-QA-${randomUUID()}`, size: 'M', color: 'Trắng', colorHex: '#FFFFFF', price: '490000',
        inventory: { create: { quantity: 901 } } } },
    }, include: { variants: { include: { inventory: true } } } });
    productId = product.id; variantId = product.variants[0].id; inventoryId = product.variants[0].inventory.id;
    await db.$transaction(async tx => {
      await tx.order.createMany({ data: ids.map((id, i) => ({
        id, userId, idempotencyKey: `qa-${id}`, requestHash: 'orders-browser-fixture',
        status: ['PENDING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'RETURNED'][i] || 'CONFIRMED',
        addressSnapshot: { recipient: 'Nguyễn An', phone: '0901234567', address: '12 Nguyễn Huệ, Phường Sài Gòn, TP. Hồ Chí Minh' },
        subtotal: '490000', shipping: '30000', total: '520000',
        createdAt: new Date(Date.now() - i * 86400000),
      })) });
      await tx.orderItem.createMany({ data: ids.map((id, i) => ({
        orderId: id, variantId, name: i === 100 ? 'Áo linen cuối danh sách' : 'Áo cotton kiểm thử',
        sku: product.variants[0].sku, slug: product.slug, size: 'M', color: 'Trắng',
        image: source.images[0]?.url || 'assets/images/shirt.jpg', unitPrice: '490000', quantity: 1,
      })) });
      await tx.payment.createMany({ data: ids.map((id, i) => ({ orderId: id, provider: 'cod', amount: '520000', status: i === 3 ? 'CANCELLED' : 'PENDING' })) });
      await tx.orderEvent.createMany({ data: ids.map((id, i) => ({ orderId: id, actorId: userId, version: 0,
        status: ['PENDING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'RETURNED'][i] || 'CONFIRMED',
        note: 'Mốc kiểm thử giao diện.', createdAt: new Date(Date.now() - i * 86400000),
      })) });
      await tx.inventoryMovement.createMany({ data: ids.filter((_, i) => ![3, 4].includes(i)).map(id => ({
        inventoryId, orderId: id, delta: -1, reason: 'BROWSER_QA',
      })) });
      // Cancellation upserts this key without changing it. Pre-mark ONLY this
      // fixture event as handled so the running mail worker cannot send it.
      await tx.mailOutbox.create({ data: {
        eventKey: `order:${ids[0]}:1`, orderId: ids[0], recipient: email,
        subject: 'Suppressed QA fixture', body: 'No delivery requested', status: 'SENT', sentAt: new Date(),
      } });
    });
    session = await customerSession(email);
    const first = await session.request('orders/' + ids[0]);
    const last = await session.request('orders/' + ids[100]);
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]);
    page = await context.newPage(); page.setDefaultTimeout(15000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    let cancels = 0;
    page.on('request', r => { if (r.method() === 'POST' && r.url().endsWith('/cancel')) cancels++; });
    const button = name => page.getByRole('button', { name, exact: true });
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function includes(value) {
      for (let i = 0; i < 150; i++) {
        if ((await page.locator('body').ariaSnapshot()).includes(value)) return;
        await page.waitForTimeout(100);
      }
      throw Error('Missing content: ' + value);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 45; i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height;
        const inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 12) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 12 - b.height) / 2 : 250);
        await page.waitForTimeout(80);
      }
      throw Error('Cannot reveal control: ' + await node.getAttribute('aria-label'));
    }
    async function click(name) { const n = button(name); await reveal(n); await n.click(); await page.waitForTimeout(120); }
    async function chip(name) { const n = page.getByRole('checkbox', { name, exact: true }); await reveal(n); await n.click(); await page.waitForTimeout(150); }
    async function search(value) {
      const n = page.getByRole('textbox', { name: /Tìm mã đơn hoặc tên sản phẩm/ });
      await reveal(n); await n.click(); await n.fill(value); await page.waitForTimeout(200);
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -100000); await page.waitForTimeout(200);
    }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 12); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    async function list() {
      await page.evaluate(() => { location.hash = '/account/orders'; });
      await includes('Tìm mã đơn hoặc tên sản phẩm');
    }
    await page.goto(origin + '/#/account/orders'); await semantics();
    await includes('100 / 101 đơn đã tải');
    await search('linen cuoi'); await includes('Không có đơn phù hợp');
    await includes('Chưa thấy kết quả trong các đơn đã tải.');
    await click('Tải thêm đơn hàng'); await includes(last.code);
    assert.equal(await button('Xem chi tiết').count(), 1);
    await click('Xem chi tiết'); await page.waitForURL('**/#/account/orders/' + ids[100]);
    await includes('Sản phẩm trong đơn'); await includes(last.code);
    await page.reload(); await semantics(); await includes('Sản phẩm trong đơn'); await includes(last.code);
    report.passed.push('Real 101-order pagination, accentless search and direct reload of an older detail work');

    await list(); await chip('Chờ xác nhận (1)'); await includes(first.code);
    assert.equal(await button('Xem chi tiết').count(), 1);
    let started;
    const began = new Promise(r => { started = r; });
    const gate = new Promise(r => { releaseRefresh = r; });
    await page.route('**/api/v1/orders?*', async route => { started(); await gate; await route.continue(); });
    await reveal(button('Cập nhật đơn hàng'));
    const b = await button('Cập nhật đơn hàng').boundingBox();
    await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
    await began; await page.waitForTimeout(250);
    assert(await button('Cập nhật đơn hàng').isDisabled());
    await includes(first.code); await capture('orders-refreshing');
    releaseRefresh(); await page.waitForTimeout(400); await page.unroute('**/api/v1/orders?*');
    await page.route('**/api/v1/orders?*', route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'SERVICE_UNAVAILABLE' } }) }));
    await click('Cập nhật đơn hàng'); await includes('Chưa cập nhật được danh sách.'); await includes(first.code);
    await capture('orders-refresh-error'); await page.unroute('**/api/v1/orders?*');
    await click('Thử tải lại'); await includes(first.code);
    report.passed.push('Slow and failed refresh preserve filtered rows; retry restores live data');

    await click('Xem chi tiết'); await includes('Sản phẩm trong đơn');
    await click('Hủy đơn hàng'); await includes('Hủy đơn hàng này?');
    await button('Giữ đơn').click(); assert.equal(cancels, 0);
    await click('Hủy đơn hàng'); await button('Xác nhận hủy').click();
    await includes('Thanh toán đã hủy').catch(async () => includes('COD · Đã hủy'));
    assert.equal(cancels, 1);
    assert.equal((await session.request('orders/' + ids[0])).status, 'CANCELLED');
    assert.equal((await db.inventory.findUniqueOrThrow({ where: { id: inventoryId } })).quantity, 902);
    assert.equal((await db.mailOutbox.findUniqueOrThrow({ where: { eventKey: `order:${ids[0]}:1` } })).status, 'SENT');
    assert.equal(await button('Hủy đơn hàng').count(), 0);
    report.passed.push('Cancellation confirmation preserves on dismiss and cancels once through the real API; no mail is sent');

    await page.evaluate(id => { location.hash = '/account/orders/' + id; }, ids[1]);
    await includes('Sản phẩm trong đơn');
    assert.equal(await button('Hủy đơn hàng').count(), 0);
    await capture('orders-detail-desktop');
    await list(); await chip('Đã hủy (2)');
    for (const width of [2560, 1920, 1440, 768, 375, 320]) {
      await page.setViewportSize({ width, height: 1080 }); await top();
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      await capture(`orders-${width}-top`);
      await reveal(button('Xem chi tiết').first()); await capture(`orders-${width}-rows`);
    }
    report.passed.push('Filters and populated order rows fit six widths from 320 to 2560px');
    await reveal(button('Xem chi tiết').first()); await button('Xem chi tiết').first().click();
    await includes('Sản phẩm trong đơn'); await capture('orders-detail-mobile');
    await reveal(button('Cần hỗ trợ đơn hàng')); await capture('orders-detail-mobile-bottom');
    await page.setViewportSize({ width: 812, height: 375 }); await reveal(button('Về danh sách đơn')); await capture('orders-landscape');
    await page.evaluate(id => { location.hash = '/account/orders/' + id; }, randomUUID());
    await includes('Không tìm thấy đơn hàng'); await click('Về danh sách đơn');
    await includes('Tìm mã đơn hoặc tên sản phẩm');
    report.passed.push('Mobile details, landscape controls and a missing order offer working navigation');

    await page.route('**/api/v1/orders?*', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }));
    await page.reload(); await semantics(); await includes('Chưa tải được đơn hàng');
    assert.equal(await button('Khám phá cửa hàng').count(), 0);
    await page.unroute('**/api/v1/orders?*'); await click('Thử tải lại'); await includes('Tìm mã đơn hoặc tên sản phẩm');
    report.passed.push('Initial load failure is distinct from empty history and can be retried');
    assert.deepEqual(report.errors, []);
    console.log(JSON.stringify(report, null, 2));
  } catch (error) {
    report.errors.push(error.message);
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); }
    throw error;
  } finally {
    releaseRefresh?.();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    await browser?.close(); await session?.close();
    if (userId) {
      await db.$transaction(async tx => {
        await tx.inventoryMovement.deleteMany({ where: { order: { userId } } });
        await tx.orderItem.deleteMany({ where: { order: { userId } } });
        await tx.payment.deleteMany({ where: { order: { userId } } });
        await tx.order.deleteMany({ where: { userId } });
        if (inventoryId) await tx.inventory.deleteMany({ where: { id: inventoryId } });
        if (variantId) await tx.productVariant.deleteMany({ where: { id: variantId } });
        if (productId) await tx.product.deleteMany({ where: { id: productId } });
        await tx.user.deleteMany({ where: { id: userId, email } });
      });
    }
    await db.$disconnect();
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
