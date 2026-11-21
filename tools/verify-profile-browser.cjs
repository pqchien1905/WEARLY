// Real local API acceptance. Mutations belong only to a disposable customer.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, randomInt } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, '.tools/profile-redesign');
const origin = process.env.PROFILE_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const email = `profile-${randomUUID().slice(0, 8)}@example.invalid`;
  const report = { origin, passed: [], errors: [] };
  let browser, page, session, userId, releaseSave;
  let writes = 0;
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Khách kiểm thử', email, password: randomUUID() + '-Aa1' }),
    });
    assert.equal(registered.status, 201);
    userId = (await registered.json()).user.id;
    session = await customerSession(email);
    let fixturePhone;
    do { fixturePhone = '09' + randomInt(10000000, 99999999); }
    while (await session.db.user.count({ where: { phone: fixturePhone } }));
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]);
    page = await context.newPage();
    page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('request', r => { if (r.method() === 'PATCH' && new URL(r.url()).pathname === '/api/v1/users/me') writes++; });
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
      for (let i = 0; i < 50; i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height;
        const inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 12) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 12 - b.height) / 2 : 250);
        await page.waitForTimeout(90);
      }
      throw Error('Cannot reveal ' + await node.getAttribute('aria-label'));
    }
    const button = name => page.getByRole('button', { name, exact: typeof name === 'string' });
    const field = name => page.getByRole('textbox', { name, exact: true });
    async function click(name) { const n = button(name); await reveal(n); await n.click(); await page.waitForTimeout(120); }
    async function fill(name, value) { const n = field(name); await reveal(n); await n.click(); await n.fill(value); await page.waitForTimeout(80); }
    async function valueIs(name, value) {
      // Flutter refreshes the editable DOM input from its controller on focus.
      // An unfocused semantics input may still contain its last editing value.
      await reveal(field(name)); await field(name).click();
      for (let i = 0; i < 50; i++) {
        if (await field(name).inputValue() === value) return;
        await page.waitForTimeout(100);
      }
      assert.equal(await field(name).inputValue(), value);
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
    async function profile() {
      await page.evaluate(() => { location.hash = '/account'; });
      await includes('Thông tin cá nhân');
    }
    await page.goto(origin + '/#/account'); await semantics();
    await includes('Thông tin cá nhân');
    assert(await button('Lưu hồ sơ').isDisabled());
    assert(await button('Hoàn tác thay đổi').isDisabled());
    await fill('Họ và tên', 'Bản nháp'); await includes('Bạn có thay đổi chưa lưu.');
    await click('Hoàn tác thay đổi');
    await valueIs('Họ và tên', 'Khách kiểm thử');
    assert.equal(writes, 0);
    report.passed.push('Unchanged data disables saving; undo restores the saved profile without API writes');

    await fill('Họ và tên', ' '); await fill('Điện thoại (không bắt buộc)', '123');
    await click('Lưu hồ sơ'); await includes('Nhập số điện thoại 7–15 chữ số hoặc để trống.');
    assert.equal(writes, 0);
    await click('Hoàn tác thay đổi');
    assert(!(await page.locator('body').ariaSnapshot()).includes('Nhập số điện thoại 7–15 chữ số'));
    report.passed.push('Invalid names and phone numbers remain local; undo clears validation errors');

    await fill('Họ và tên', '  Nguyễn An  ');
    await fill('Điện thoại (không bắt buộc)', fixturePhone);
    const saved = page.waitForResponse(r => r.request().method() === 'PATCH' && r.url().endsWith('/users/me'));
    await page.keyboard.press('Enter');
    assert.equal((await saved).status(), 200);
    await includes('Thông tin mới đã được lưu.');
    await valueIs('Họ và tên', 'Nguyễn An');
    assert.equal((await session.request('users/me')).phone, fixturePhone);
    await page.reload(); await semantics(); await includes('Thông tin cá nhân');
    await valueIs('Họ và tên', 'Nguyễn An');
    await valueIs('Điện thoại (không bắt buộc)', fixturePhone);
    assert(await button('Lưu hồ sơ').isDisabled());
    report.passed.push('Keyboard submit trims and persists real profile data across browser reload');

    await fill('Điện thoại (không bắt buộc)', ''); await click('Lưu hồ sơ');
    await includes('Thông tin mới đã được lưu.');
    assert.equal((await session.request('users/me')).phone, '');
    report.passed.push('Optional phone can be removed and remains empty in the API');

    await page.route('**/api/v1/users/me', route => route.request().method() === 'PATCH'
      ? route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'SERVICE_UNAVAILABLE' } }) })
      : route.continue());
    await fill('Họ và tên', 'Tên thử lại'); await click('Lưu hồ sơ');
    await includes('Chưa lưu được hồ sơ.'); await capture('profile-save-error');
    assert.equal(await field('Họ và tên').inputValue(), 'Tên thử lại');
    assert.equal((await session.request('users/me')).name, 'Nguyễn An');
    await page.unroute('**/api/v1/users/me'); await click('Lưu hồ sơ');
    await includes('Thông tin mới đã được lưu.');
    assert.equal((await session.request('users/me')).name, 'Tên thử lại');
    report.passed.push('Failed save retains draft and retry succeeds without claiming a false save');

    const gate = new Promise(resolve => { releaseSave = resolve; });
    let saveStarted;
    const started = new Promise(resolve => { saveStarted = resolve; });
    await page.route('**/api/v1/users/me', async route => {
      if (route.request().method() === 'PATCH') { saveStarted(); await gate; }
      await route.continue();
    });
    await fill('Họ và tên', 'Nguyễn An');
    const before = writes;
    await reveal(button('Lưu hồ sơ'));
    const saveBox = await button('Lưu hồ sơ').boundingBox();
    await page.mouse.click(saveBox.x + saveBox.width / 2, saveBox.y + saveBox.height / 2);
    await started;
    await page.waitForTimeout(300);
    await capture('profile-pending');
    assert(await button('Đang lưu hồ sơ').isDisabled());
    assert(await button('Hoàn tác thay đổi').isDisabled());
    assert.equal(await button(/^Xem lịch sử thử đồ /).count(), 0);
    assert.equal(writes, before + 1);
    releaseSave(); await includes('Thông tin mới đã được lưu.');
    await page.unroute('**/api/v1/users/me');
    report.passed.push('Pending request locks editing, account shortcuts and duplicate saving');

    for (const [label, route] of [
      [/^Theo dõi đơn hàng /, '/account/orders'],
      [/^Quản lý địa chỉ nhận hàng /, '/account/addresses'],
      [/^Phong cách của tôi Chọn/, '/account/style'],
      [/^Xem lịch sử thử đồ /, '/account/try-ons'],
      [/^Tủ đồ yêu thích Trở/, '/wishlist'],
      [/^Bảo mật và cài đặt /, '/account/settings'],
    ]) {
      await click(label); await page.waitForURL('**/#' + route);
      await profile();
    }
    report.passed.push('All six account shortcuts open the correct real destination');

    for (const width of [2560, 1920, 1440, 768, 375, 320]) {
      await page.setViewportSize({ width, height: 1080 }); await top();
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      await capture(`profile-${width}-top`);
      await reveal(button('Lưu hồ sơ')); await capture(`profile-${width}-actions`);
      await reveal(button(/^Bảo mật và cài đặt /)); await capture(`profile-${width}-shortcuts`);
    }
    report.passed.push('Six viewport widths from 320 to 2560px render without overflow and retain all controls');

    await page.setViewportSize({ width: 375, height: 812 });
    await fill('Điện thoại (không bắt buộc)', '0987654321');
    await click('Lưu hồ sơ'); await includes('Thông tin mới đã được lưu.');
    assert.equal((await session.request('users/me')).phone, '0987654321');
    await top();
    await button(/Hồ sơ Menu tài khoản/).click();
    await click('Sổ địa chỉ'); await page.waitForURL('**/#/account/addresses');
    await profile(); await page.setViewportSize({ width: 812, height: 375 });
    await reveal(button('Lưu hồ sơ')); await capture('profile-landscape');
    report.passed.push('Mobile save, account menu and landscape controls work');
    assert.deepEqual(report.errors, []);
    console.log(JSON.stringify(report, null, 2));
  } catch (error) {
    report.errors.push(error.message);
    if (page) {
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
      await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    }
    throw error;
  } finally {
    releaseSave?.();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    await browser?.close(); await session?.close();
    if (userId) {
      const db = localDatabase();
      try { await db.user.deleteMany({ where: { id: userId, email } }); }
      finally { await db.$disconnect(); }
    }
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
