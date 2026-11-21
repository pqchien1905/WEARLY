// Disposable local fixtures exercise history and private storage without calling AI.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const { createRequire } = require('node:module');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const root = path.resolve(__dirname, '..');
const backend = createRequire(path.join(root, 'backend/package.json'));
const output = path.join(root, '.tools/tryon-history-redesign');
const origin = process.env.TRYON_HISTORY_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const email = `history-design-${randomUUID()}@example.invalid`;
  const report = { origin, fixture: 'Bundled catalog photo, no AI generation', passed: [], errors: [], requests: [] };
  let userId, session, storage, browser, page;
  const keys = [];
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Khách kiểm thử', email, password: randomUUID() + '-Aa1' }),
    });
    assert.equal(registered.status, 201); userId = (await registered.json()).user.id;
    session = await customerSession(email);
    const env = backend('dotenv').parse(fs.readFileSync(path.join(root, 'backend/.env')));
    const { ConfigService } = backend('@nestjs/config');
    const { StorageService } = backend('./dist/integrations/storage/storage.service');
    storage = new StorageService(new ConfigService(env));
    const garment = await session.db.productVariant.findFirst({ where: { active: true, product: { active: true, tryOnSupported: true } }, include: { product: true } });
    assert(garment);
    const form = new FormData(); form.set('consent', 'true');
    form.set('file', new Blob([fs.readFileSync(path.join(root, 'frontend/assets/images/shirt.jpg'))], { type: 'image/jpeg' }), 'history-fixture.jpg');
    const uploaded = await session.request('uploads/images', { method: 'POST', body: form, headers: { 'Idempotency-Key': randomUUID() }, expected: 201 });
    const source = await session.db.imageAsset.findUnique({ where: { id: uploaded.id } }); keys.push(source.objectKey);
    const resultId = randomUUID(), resultKey = `results/${userId}/${resultId}`; keys.push(resultKey);
    await storage.putResult(resultKey, fs.readFileSync(path.join(root, 'frontend/assets/images/shirt.jpg')), 'image/jpeg');
    const resultBytes = await storage.readImage(resultKey);
    const completed = await session.db.aIJob.create({ data: { id: resultId, userId, variantId: garment.id, imageId: uploaded.id,
      consentAt: new Date(), status: 'COMPLETED', result: { create: { objectKey: resultKey, expiresAt: source.expiresAt } } } });
    await session.db.aIJob.create({ data: { userId, variantId: garment.id, imageId: uploaded.id, consentAt: new Date(), status: 'FAILED', errorCode: 'AI_PROVIDER_UNAVAILABLE' } });
    const otherImage = await session.db.imageAsset.create({ data: { userId, objectKey: `history-fixture/${userId}/${randomUUID()}`,
      mimeType: 'image/jpeg', size: 100, consentAt: new Date(), verifiedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
    const pending = await session.db.aIJob.create({ data: { userId, variantId: garment.id, imageId: otherImage.id, consentAt: new Date(), status: 'PENDING' } });
    const expired = await session.db.imageAsset.create({ data: { userId, objectKey: `history-fixture/${userId}/${randomUUID()}`,
      mimeType: 'image/jpeg', size: 100, consentAt: new Date(), verifiedAt: new Date(), expiresAt: new Date(Date.now() + 3600000) } });
    await session.db.aIJob.create({ data: { userId, variantId: garment.id, imageId: expired.id, consentAt: new Date(), status: 'COMPLETED' } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true,
      args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce', acceptDownloads: true });
    await context.addCookies([session.cookie]); page = await context.newPage(); page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) report.requests.push({ path: new URL(r.url()).pathname, method: r.request().method(), status: r.status() }); });
    async function semantics() { await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics')); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function includes(value) {
      for (let i = 0; i < 150; i++) { if ((await page.locator('body').ariaSnapshot()).includes(value)) return; await page.waitForTimeout(100); }
      throw Error('Missing content: ' + value);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 50; i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height, inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 10) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 10 - b.height) / 2 : 250); await page.waitForTimeout(80);
      }
      throw Error('Cannot reveal ' + await node.getAttribute('aria-label'));
    }
    const button = name => page.getByRole('button', { name, exact: true }).first();
    async function click(name) { const n = button(name); await reveal(n); await n.click(); await page.waitForTimeout(120); }
    async function filter(label) {
      const n = page.getByRole('checkbox', { name: label, exact: true });
      await reveal(n); await n.click(); await page.waitForTimeout(150);
    }
    async function top() { await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7); await page.mouse.wheel(0, -30000); await page.waitForTimeout(200); }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 12); await page.waitForTimeout(120);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    async function history() { await page.evaluate(() => { location.hash = '/account/try-ons'; }); await includes('4 lượt thử đồ'); }
    await page.goto(origin + '/#/account/try-ons'); await semantics(); await includes('4 lượt thử đồ');
    await includes(garment.product.name);
    assert.equal(report.requests.filter(r => r.path.endsWith('/result')).length, 0);
    await includes('Có ảnh (1)'); await includes('Đang xử lý (1)'); await includes('Chưa thành công (1)'); await includes('Không còn ảnh (1)');
    report.passed.push('Real product, size, color, all four states and counts; private images are not fetched automatically');
    await filter('Có ảnh (1)'); await click('Xem ảnh thử đồ');
    const image = page.getByRole('img', { name: 'Ảnh thử đồ riêng tư', exact: true }); await image.waitFor({ state: 'attached' });
    await reveal(button('Tải ảnh xuống')); await capture('private-result');
    const downloadEvent = page.waitForEvent('download'); await click('Tải ảnh xuống');
    const download = await downloadEvent; assert.equal(download.suggestedFilename(), `wearly-thu-do-${completed.id}.jpg`);
    const file = path.join(output, 'fixture-download.jpg'); await download.saveAs(file);
    assert.equal(createHash('sha256').update(fs.readFileSync(file)).digest('hex'), createHash('sha256').update(resultBytes).digest('hex'));
    await click('Ẩn ảnh'); assert.equal(await image.count(), 0);
    report.passed.push('Private result opens on demand, downloads exact image bytes, and can be hidden');
    await filter('Chưa thành công (1)'); await click('Xóa ảnh và các kết quả');
    await includes('đang được dùng trong 2 lượt thử'); await capture('delete-confirmation');
    await button('Giữ lại').click(); assert.equal((await session.request('ai/try-on/jobs')).items.length, 4);
    await click('Xem trang phục'); assert(new URL(page.url()).hash.includes('/products/' + garment.product.slug));
    await history(); await filter('Chưa thành công (1)'); await click('Thử lại trang phục');
    assert(new URL(page.url()).hash.includes('/virtual-try-on?product=' + garment.product.slug));
    assert(!report.requests.some(r => r.method === 'POST' && r.path.endsWith('/ai/try-on/jobs')));
    await history(); await filter('Tất cả (4)');
    report.passed.push('Delete cancellation, product link and retry navigation work without creating an AI request');
    // No outbox is created for the pending fixture. Settle it without a provider call.
    await session.db.aIJob.update({ where: { id: pending.id }, data: { status: 'FAILED', errorCode: 'AI_PROVIDER_RATE_LIMIT' } });
    await includes('Chưa thành công (2)');
    report.passed.push('Pending history refreshes automatically and displays the final status');
    for (const width of [2560, 1920, 1440, 768, 375, 320]) {
      await page.setViewportSize({ width, height: 1080 }); await top();
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      await capture(`history-${width}-top`); await reveal(button('Xóa ảnh và các kết quả')); await capture(`history-${width}-actions`);
      report.passed.push(`History, filters and actions fit ${width}px`);
    }
    await page.setViewportSize({ width: 375, height: 812 }); await filter('Có ảnh (1)'); await click('Xem ảnh thử đồ');
    await image.waitFor({ state: 'attached' }); await reveal(button('Tải ảnh xuống')); await capture('private-result-mobile');
    await click('Xóa ảnh và các kết quả'); await capture('delete-mobile'); await button('Xác nhận xóa').click();
    await includes('2 lượt thử đồ'); assert.equal((await session.request('ai/try-on/jobs')).items.length, 2);
    assert.equal(await image.count(), 0); await includes('Chưa có lượt thử ở trạng thái này'); await click('Xem tất cả');
    report.passed.push('Confirmed deletion removes all related jobs, hides private bytes and supports empty filtered results');
    await page.setViewportSize({ width: 812, height: 375 }); await reveal(button('Xóa ảnh và các kết quả')); await capture('history-landscape');
    await page.route('**/api/v1/ai/try-on/jobs', route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'UNAVAILABLE', message: 'Lịch sử tạm thời chưa tải được.' } }) }));
    await page.setViewportSize({ width: 1440, height: 1080 }); await click('Làm mới lịch sử');
    await includes('Danh sách bên dưới là dữ liệu đã tải trước đó.'); await capture('history-stale');
    await page.reload(); await semantics(); await includes('Chưa tải được lịch sử thử đồ');
    assert(!(await page.locator('body').ariaSnapshot()).includes('Góc thử đồ đang chờ bạn'));
    await page.unroute('**/api/v1/ai/try-on/jobs'); await click('Thử lại'); await includes('2 lượt thử đồ');
    await click('Xóa ảnh và các kết quả'); await button('Xác nhận xóa').click(); await includes('1 lượt thử đồ');
    await click('Xóa ảnh và các kết quả'); await button('Xác nhận xóa').click(); await includes('Góc thử đồ đang chờ bạn');
    await capture('history-empty');
    report.passed.push('Refresh failures, initial failures, retry and fully empty history have clear recoverable states');
    assert.deepEqual(report.errors, []);
    console.log(JSON.stringify({ passed: report.passed, errors: report.errors }, null, 2));
  } catch (error) {
    report.errors.push(error.message);
    if (page) { fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
    await browser?.close();
    if (storage) { try { if (keys.length) await storage.deleteObjects(keys); } finally { storage.onModuleDestroy(); } }
    await session?.close();
    if (userId) {
      const db = localDatabase();
      try {
        await db.tryOnResult.deleteMany({ where: { job: { userId } } });
        await db.aIJob.deleteMany({ where: { userId } }); await db.imageAsset.deleteMany({ where: { userId } });
        await db.user.deleteMany({ where: { id: userId, email } });
      } finally { await db.$disconnect(); }
    }
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
