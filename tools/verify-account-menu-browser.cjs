// Live browser acceptance. Creates one temporary customer and removes only that
// customer in finally. Never sends recovery email or creates orders.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { createStaticServer } = require('./serve.cjs');
const root = path.resolve(__dirname, '..');
const backend = createRequire(path.join(root, 'backend/package.json'));
const output = path.join(root, '.tools/account-menu-acceptance');
const base = process.env.ACCOUNT_TEST_BASE || 'http://localhost:5173';
const api = 'http://localhost:3000/api/v1';

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const server = process.env.ACCOUNT_TEST_BASE ? null : createStaticServer(path.join(root, 'frontend/build/web'));
  if (server) await new Promise((resolve, reject) => { server.once('error', reject); server.listen(5173, '127.0.0.1', resolve); });
  const email = `account-menu-${randomUUID()}@example.invalid`;
  const password = randomUUID() + '-Aa1';
  let userId, browser, page;
  const errors = [], passed = [];
  try {
    const registered = await fetch(api + '/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Nguyễn Văn Chiến', email, password }),
    });
    assert.equal(registered.status, 201);
    userId = (await registered.json()).user.id;
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, hasTouch: true });
    page = await context.newPage();
    page.setDefaultTimeout(15000);
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(message.text())) errors.push(message.text()); });
    const button = name => name === 'Tài khoản'
      ? page.getByRole('button', { name: /^Tài khoản(?:\s|$)/ }).and(page.locator('[aria-expanded]'))
      : page.getByRole('button', { name, exact: true });
    const menuItem = name => page.getByRole('group').filter({ has: page.getByRole('heading', { name: 'Tài khoản', exact: true }) }).getByRole('button', { name, exact: true });
    async function includes(text) {
      for (let n = 0; n < 80; n++) {
        const snapshot = await page.locator('body').ariaSnapshot();
        if (snapshot.includes(text)) return snapshot;
        await page.waitForTimeout(150);
      }
      throw Error('Missing content: ' + text);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let n = 0; n < 45; n++) {
        const box = await node.boundingBox();
        if (box && box.y >= 145 && box.y + box.height <= 995) return;
        await page.mouse.move(page.viewportSize().width * .75, 750);
        await page.mouse.wheel(0, box && box.y < 145 ? -320 : 320);
        await page.waitForTimeout(100);
      }
      throw Error('Cannot reveal control');
    }
    async function click(name) { const node = button(name).last(); await reveal(node); await node.click(); }
    async function fill(name, value) {
      const node = page.getByRole('textbox', { name, exact: true });
      await reveal(node); await node.click(); await node.fill(value);
    }
    async function openMenu() {
      await page.mouse.move(10, 600);
      await page.waitForTimeout(400);
      const node = button('Tài khoản');
      await node.hover();
      await menuItem('Hồ sơ').waitFor();
    }
    async function navigate(name, route) {
      await openMenu(); await menuItem(name).click();
      await page.waitForURL(url => url.hash.split('?')[0] === '#' + route);
      await page.mouse.move(10, 600);
    }
    async function capture(name) {
      await page.waitForTimeout(450);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await page.goto(base + '/#/login');
    await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await includes('Đăng nhập khách hàng');
    for (const label of ['Tìm cửa hàng', 'Trợ giúp', 'Đăng ký', 'Đăng nhập']) assert((await button(label).count()) >= 1);
    assert.equal(await button('Tài khoản').count(), 0);
    await capture('header-guest-desktop');
    await page.setViewportSize({ width: 375, height: 1000 });
    await capture('header-guest-mobile');
    await page.setViewportSize({ width: 1440, height: 1000 });
    await fill('Email', email); await fill('Mật khẩu', password); await click('Đăng nhập');
    await includes('Chào Nguyễn Văn Chiến.');
    await openMenu();
    assert.equal(await menuItem('Đăng xuất').count(), 1);
    assert.equal(await page.getByText('Kinh nghiệm', { exact: true }).count(), 0);
    const target = await button('Tài khoản').boundingBox();
    await page.mouse.move(target.x + target.width / 2, target.y + target.height + 4);
    await page.waitForTimeout(100);
    await menuItem('Cài đặt tài khoản').hover();
    await page.waitForTimeout(600);
    assert.equal(await menuItem('Hồ sơ').count(), 1);
    await capture('account-menu-desktop');
    passed.push('Guest utility links; authenticated greeting, hover and gap crossing');
    await menuItem('Hồ sơ').click();
    await fill('Họ và tên', 'Nguyễn An');
    await fill('Điện thoại (không bắt buộc)', '0901234567');
    await click('Lưu hồ sơ'); await includes('Đã lưu hồ sơ.');
    await page.reload();
    await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await includes('Chào Nguyễn An.');
    passed.push('Profile saves to API and survives reload');
    await navigate('Đơn đặt hàng', '/account/orders'); await includes('Tìm mã đơn hoặc tên sản phẩm');
    await navigate('Yêu thích', '/wishlist'); await includes('Tủ đồ yêu thích còn trống');
    passed.push('Order and wishlist menu destinations load from API');
    await navigate('Cài đặt tài khoản', '/account/settings'); await includes('Mật khẩu và bảo mật');
    await capture('account-settings-desktop');
    await click('Đổi mật khẩu'); await includes('Trở về cài đặt tài khoản');
    const recoveryEmail = page.getByRole('textbox', { name: 'Email', exact: true });
    await reveal(recoveryEmail); await recoveryEmail.click();
    assert.equal(await recoveryEmail.inputValue(), email);
    await click('Trở về cài đặt tài khoản');
    passed.push('Settings links to password recovery with current email; no email sent');
    for (const width of [768, 375]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.waitForTimeout(350);
      await page.mouse.move(10, 700);
      await page.waitForTimeout(350);
      // A real touch event avoids generating desktop hover before the tap.
      const box = await button('Tài khoản').boundingBox();
      await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
      await menuItem('Hồ sơ').waitFor();
      const bounds = await menuItem('Cài đặt tài khoản').boundingBox();
      assert(bounds.x >= 0 && bounds.x + bounds.width <= width);
      await capture('account-menu-' + width);
      await menuItem('Cài đặt tài khoản').click();
      await includes('Thông tin đăng nhập');
      await capture('account-settings-' + width);
    }
    passed.push('Tablet and phone menu and settings fit viewport');
    await page.setViewportSize({ width: 1440, height: 1000 });
    await navigate('Đăng xuất', '/login');
    await includes('Đăng nhập khách hàng');
    assert(!(await context.cookies()).some(cookie => cookie.name === 'wearly_customer_session'));
    assert((await button('Đăng nhập').count()) >= 1);
    await page.evaluate(() => { location.hash = '/account/settings'; });
    await includes('Đăng nhập để tiếp tục');
    passed.push('Logout revokes browser cookie and protects account settings');
    assert.deepEqual(errors, []);
    console.log(passed.map(value => 'PASS ' + value).join('\n'));
  } catch (error) {
    if (page) await captureFailure(page);
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
  async function captureFailure(page) {
    await page.screenshot({ path: path.join(output, 'failure.png') });
    fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot());
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
