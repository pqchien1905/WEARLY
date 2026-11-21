// Real local API acceptance. All writes belong to a disposable customer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, '.tools/style-redesign');
const origin = process.env.STYLE_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const email = `style-design-${randomUUID()}@example.invalid`;
  const report = { passed: [], errors: [], requests: [] };
  let browser, page, session, userId;
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Khách kiểm thử', email, password: randomUUID() + '-Aa1' }),
    });
    assert.equal(registered.status, 201);
    userId = (await registered.json()).user.id;
    session = await customerSession(email);
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]);
    page = await context.newPage();
    page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) report.requests.push({
      path: new URL(r.url()).pathname, method: r.request().method(), status: r.status(),
    }); });
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
        await page.waitForTimeout(90);
      }
      throw Error('Cannot reveal ' + await node.getAttribute('aria-label'));
    }
    const button = name => page.getByRole('button', { name, exact: true });
    async function click(name) { const n = button(name); await reveal(n); await n.click(); await page.waitForTimeout(120); }
    async function selected(name) {
      const n = button(name);
      await n.waitFor({ state: 'attached' });
      assert.equal(await n.getAttribute('aria-current'), 'true', `${name} must expose its selection`);
    }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 12); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -20000); await page.waitForTimeout(200);
    }
    await page.goto(origin + '/#/account/style'); await semantics();
    await includes('Lựa chọn của bạn');
    await selected('Size thường chọn: M');
    await click('Size thường chọn: L');
    await click('Phong cách yêu thích: Thanh lịch');
    await click('Màu ưu tiên: Đen');
    await click('Ngân sách mỗi outfit: 2.500.000 ₫');
    await includes('Bạn có thay đổi chưa lưu.');
    await click('Lưu hồ sơ phong cách'); await includes('Đã lưu hồ sơ phong cách.');
    const saved = await session.request('users/me/style');
    assert.deepEqual({ size: saved.size, style: saved.style, color: saved.color, budget: saved.budget },
      { size: 'L', style: 'Thanh lịch', color: 'Đen', budget: '2500000' });
    assert.equal(saved.version, 1);
    await page.reload(); await semantics(); await includes('Lựa chọn của bạn');
    for (const name of ['Size thường chọn: L', 'Phong cách yêu thích: Thanh lịch', 'Màu ưu tiên: Đen', 'Ngân sách mỗi outfit: 2.500.000 ₫']) await selected(name);
    report.passed.push('All four preferences persist through the real API and browser reload');

    await click('Size thường chọn: XS'); await click('Hoàn tác thay đổi'); await selected('Size thường chọn: L');
    await click('Size thường chọn: XXL'); await click('Tải lại hồ sơ'); await includes('Tải lại hồ sơ?');
    await button('Tiếp tục chỉnh sửa').click(); await selected('Size thường chọn: XXL');
    await click('Tải lại hồ sơ'); await button('Bỏ thay đổi và tải lại').click();
    await includes('Đang hiển thị hồ sơ đã lưu.'); await selected('Size thường chọn: L');
    assert.equal((await session.request('users/me/style')).version, 1);
    report.passed.push('Undo and reload confirmation preserve drafts and do not write to the server');

    const keyboardChoice = button('Size thường chọn: S');
    await reveal(keyboardChoice); await keyboardChoice.focus(); await page.keyboard.press('Enter');
    await selected('Size thường chọn: S'); await click('Lưu hồ sơ phong cách'); await includes('Đã lưu hồ sơ phong cách.');
    assert.equal((await session.request('users/me/style')).version, 2);
    report.passed.push('Choices support keyboard activation and expose selected state');

    await session.request('users/me/style', { method: 'PUT', body: { size: 'XL', style: '', color: '', budget: '800000', expectedVersion: 2 } });
    await click('Size thường chọn: M'); await click('Lưu hồ sơ phong cách');
    await includes('Tải lại hồ sơ để kiểm tra kết quả trước khi lưu tiếp.');
    assert(await button('Lưu hồ sơ phong cách').isDisabled());
    await click('Tải lại hồ sơ'); await includes('Đang hiển thị hồ sơ đã lưu.');
    await selected('Size thường chọn: XL'); await selected('Phong cách yêu thích: Linh hoạt');
    await selected('Màu ưu tiên: Không giới hạn màu'); await selected('Ngân sách mỗi outfit: 800.000 ₫');
    report.passed.push('Concurrent update is rejected safely; reload restores the latest server profile');

    for (const width of [2560, 1920, 1440, 768, 375, 320]) {
      await page.setViewportSize({ width, height: 1080 }); await top();
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      await capture(`style-${width}-top`);
      await reveal(button('Lưu hồ sơ phong cách')); await capture(`style-${width}-actions`);
      assert.equal(await button('Lưu hồ sơ phong cách').isEnabled(), true);
      report.passed.push(`Layout and save action fit ${width}px`);
    }
    await page.setViewportSize({ width: 375, height: 812 });
    await click('Cách chọn size phù hợp'); await includes('Chọn size vừa với bạn');
    await capture('size-guide-mobile'); await button('Đã hiểu').click();
    await click('Size thường chọn: S'); await click('Lưu hồ sơ phong cách'); await includes('Đã lưu hồ sơ phong cách.');
    assert.equal((await session.request('users/me/style')).size, 'S');
    await page.setViewportSize({ width: 812, height: 375 });
    await reveal(button('Lưu hồ sơ phong cách')); await capture('style-landscape');
    report.passed.push('Mobile save, size guidance dialog, and landscape controls work');

    await page.setViewportSize({ width: 1440, height: 1080 });
    await page.route('**/api/v1/users/me/style', route => route.request().method() === 'GET'
      ? route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'UNAVAILABLE', message: 'Hồ sơ tạm thời chưa tải được.' } }) })
      : route.continue());
    await page.reload(); await semantics(); await includes('Chưa mở được hồ sơ phong cách');
    assert.equal(await button('Size thường chọn: M').count(), 0);
    await capture('style-load-error'); await page.unroute('**/api/v1/users/me/style');
    await click('Thử lại'); await includes('Lựa chọn của bạn'); await selected('Size thường chọn: S');
    report.passed.push('Load failure never presents false defaults; retry recovers saved data');
    assert.deepEqual(report.errors, []);
    console.log(JSON.stringify({ passed: report.passed, errors: report.errors }, null, 2));
  } catch (error) {
    report.errors.push(error.message);
    if (page) {
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
      await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
    await browser?.close(); await session?.close();
    if (userId) {
      const db = localDatabase();
      try { await db.user.deleteMany({ where: { id: userId, email } }); }
      finally { await db.$disconnect(); }
    }
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
