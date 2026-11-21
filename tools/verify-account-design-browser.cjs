// Local acceptance: creates one disposable customer; deletes only that customer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { createStaticServer } = require('./serve.cjs');
const root = path.resolve(__dirname, '..');
const backend = createRequire(path.join(root, 'backend/package.json'));
const output = path.join(root, '.tools/account-design-acceptance');
const api = 'http://localhost:3000/api/v1';
const base = process.env.ACCOUNT_TEST_BASE || 'http://localhost:5173';
const destinations = [
  ['profile', '/account', 'Thông tin cá nhân'],
  ['orders', '/account/orders', 'Tìm mã đơn hoặc tên sản phẩm'],
  ['reviews', '/account/reviews', 'Bạn chưa viết đánh giá nào'],
  ['addresses', '/account/addresses', 'Thêm địa chỉ'],
  ['style', '/account/style', 'Lưu hồ sơ phong cách'],
  ['try-ons', '/account/try-ons', 'Đến phòng thử'],
  ['wishlist', '/wishlist', 'Tủ đồ yêu thích còn trống'],
  ['settings', '/account/settings', 'Thông tin đăng nhập'],
];

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const server = process.env.ACCOUNT_TEST_BASE ? null : createStaticServer(path.join(root, 'frontend/build/web'));
  if (server) await new Promise((resolve, reject) => { server.once('error', reject); server.listen(5173, '127.0.0.1', resolve); });
  const email = `design-${randomUUID().slice(0, 8)}@example.invalid`;
  const password = randomUUID() + '-Aa1';
  let userId, browser, page;
  const errors = [], passed = [];
  try {
    const registered = await fetch(api + '/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Quang Chiến', email, password }),
    });
    assert.equal(registered.status, 201);
    userId = (await registered.json()).user.id;
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, hasTouch: true, reducedMotion: 'reduce' });
    page = await context.newPage();
    page.setDefaultTimeout(15000);
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(message.text())) errors.push(message.text()); });
    async function includes(text) {
      for (let i = 0; i < 100; i++) {
        const snapshot = await page.locator('body').ariaSnapshot();
        if (snapshot.includes(text)) return snapshot;
        await page.waitForTimeout(100);
      }
      throw Error('Missing content: ' + text);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 50; i++) {
        const box = await node.boundingBox();
        const height = page.viewportSize().height;
        const topInset = page.viewportSize().width < 600 ? 235 : 180;
        if (box && box.y >= topInset && box.y + box.height < height - 12) return;
        await page.mouse.move(page.viewportSize().width * .75, height * .7);
        const target = (topInset + height - 12 - (box?.height || 48)) / 2;
        await page.mouse.wheel(0, box ? box.y - target : 200);
        await page.waitForTimeout(80);
      }
      throw Error('Cannot reveal control');
    }
    async function click(name) {
      const node = page.getByRole('button', { name, exact: true }).last();
      await reveal(node); await node.click();
    }
    async function fill(name, value) {
      const node = page.getByRole('textbox', { name, exact: name !== 'Tên gợi nhớ' });
      await reveal(node); await node.click(); await node.fill(value);
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -20000);
      await page.waitForTimeout(250);
    }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 16);
      await page.waitForTimeout(100);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await page.goto(base + '/#/login');
    await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await includes('Đăng nhập khách hàng');
    await fill('Email', email); await fill('Mật khẩu', password); await click('Đăng nhập');
    await includes('Thông tin cá nhân');
    await fill('Điện thoại (không bắt buộc)', '0901234567');
    await click('Lưu hồ sơ'); await includes('Đã lưu hồ sơ.');
    passed.push('Profile form saves through the live API');
    await top();
    await click('Đơn hàng');
    await page.waitForURL('**/#/account/orders');
    passed.push('Desktop sidebar opens orders');
    await page.evaluate(() => { location.hash = '/account/addresses'; });
    await includes('Thêm địa chỉ'); await click('Thêm địa chỉ');
    await includes('Địa chỉ mới');
    await fill('Tên gợi nhớ', 'Nhà riêng');
    await fill('Người nhận', 'Quang Chiến');
    await fill('Điện thoại nhận hàng', '0901234567');
    await fill('Địa chỉ nhận hàng', '12 Nguyễn Huệ, Phường Sài Gòn, TP. Hồ Chí Minh');
    await click('Lưu địa chỉ'); await includes('Mặc định');
    passed.push('Address dialog creates the default delivery address');
    await page.evaluate(() => { location.hash = '/account/style'; });
    await includes('Lưu hồ sơ phong cách'); await click('Lưu hồ sơ phong cách');
    await includes('Đã lưu hồ sơ phong cách.');
    passed.push('Style form saves successfully');
    const dismiss = page.getByRole('button', { name: 'Đóng', exact: true });
    if (await dismiss.count()) await dismiss.click();
    for (const width of [2560, 1920, 1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1080 });
      for (const [name, route, ready] of destinations) {
        await page.evaluate(route => { location.hash = route; }, route);
        await includes(ready); await top();
        assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1, `${name} needs one page heading`);
        await capture(`${name}-${width}`);
        const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
        assert.equal(horizontalOverflow, false, `${name} overflows at ${width}`);
      }
      passed.push(`All eight destinations render at ${width}px with reduced motion`);
    }
    await page.evaluate(() => { location.hash = '/account'; });
    await includes('Thông tin cá nhân'); await top();
    const menu = page.getByRole('button').filter({ hasText: 'Menu tài khoản' }).first();
    await menu.click();
    await capture('mobile-menu-expanded');
    await click('Sổ địa chỉ');
    await page.waitForURL('**/#/account/addresses');
    await includes('Nhà riêng');
    passed.push('Mobile account menu expands and navigates to saved addresses');
    await page.setViewportSize({ width: 812, height: 375 });
    await page.evaluate(() => { location.hash = '/account/style'; });
    await includes('Lưu hồ sơ phong cách');
    await reveal(page.getByRole('button', { name: 'Lưu hồ sơ phong cách', exact: true }));
    await capture('style-landscape');
    passed.push('Landscape phone can reach the style save action');
    assert.deepEqual(errors, []);
    console.log(passed.map(value => 'PASS ' + value).join('\n'));
  } catch (error) {
    if (page) {
      await page.screenshot({ path: path.join(output, 'failure.png') });
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot());
    }
    throw error;
  } finally {
    await browser?.close();
    if (server) await new Promise(resolve => server.close(resolve));
    if (userId) {
      backend('dotenv').config({ path: path.join(root, '.env'), quiet: true });
      const db = new (backend('pg').Pool)({ connectionString: process.env.DATABASE_URL });
      try { await db.query('DELETE FROM "User" WHERE id = $1 AND email = $2 AND role = $3', [userId, email, 'CUSTOMER']); }
      finally { await db.end(); }
    }
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({ passed, errors }, null, 2));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
