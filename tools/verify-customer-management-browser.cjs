// Uses disposable local accounts only; never alters existing customer records.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:5173';
if (!/^http:\/\/localhost:(5173|8080)$/.test(base)) throw Error('Local frontend required');
const output = path.resolve(__dirname, '../.tools/customer-management-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), marker = 'customer-crud-' + randomUUID();
  const password = randomUUID() + '-Aa1', email = marker + '@example.invalid';
  const report = { passed: [], errors: [] };
  const privilegedEmail = 'access-' + email;
  let staff, customer, privileged, browser, page;
  const pass = text => { report.passed.push(text); console.log(text); };
  try {
    staff = await db.user.create({ data: { username: marker, email: 'admin-' + email, name: 'Quản trị kiểm thử', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    page = await browser.newPage({ viewport: { width: 1440, height: 1050 }, reducedMotion: 'reduce' });
    page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function contains(text) {
      for (let i = 0; i < 150; i++) {
        if ((await page.locator('body').ariaSnapshot()).includes(text)) return;
        await page.waitForTimeout(100);
      }
      throw Error('Missing UI: ' + text);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 60; i++) {
        const b = await node.boundingBox(), v = page.viewportSize();
        if (b && b.y > 80 && b.y + b.height < v.height - 15) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, b?.y < 80 ? -350 : 350);
        await page.waitForTimeout(80);
      }
      throw Error('Control not visible');
    }
    async function click(name) {
      const node = page.getByRole('button', { name, exact: true });
      await reveal(node); await node.click(); await page.waitForTimeout(200);
    }
    async function fill(label, value) {
      const node = page.getByRole('textbox', { name: new RegExp('^' + label + '(?:$| )') }).first();
      await reveal(node); await node.click(); await page.waitForTimeout(100); await node.fill(value);
    }
    async function route(value, text) {
      await page.evaluate(value => { location.hash = value; }, value);
      await contains(text); await page.waitForTimeout(300);
    }
    async function capture(name) {
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await page.goto(base + '/#/admin/customers'); await semantics();
    await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', marker); await fill('Mật khẩu', password); await click('Đăng nhập quản trị');
    await contains('Thêm khách hàng'); await click('Thêm khách hàng');
    await fill('Họ và tên', 'Khách hàng kiểm thử'); await fill('Email', email);
    await fill('Mật khẩu', password); await fill('Nhập lại mật khẩu', password);
    await capture('create-desktop'); await click('Tạo tài khoản'); await contains('Hồ sơ khách hàng');
    customer = await db.user.findUniqueOrThrow({ where: { email } });
    assert.equal(customer.role, 'CUSTOMER'); assert.equal(customer.active, true);
    pass('Created customer through browser form');
    await route('/admin/customers?q=' + encodeURIComponent(email), '1 khách hàng phù hợp bộ lọc');
    await click('Chỉnh sửa khách hàng'); await fill('Họ và tên', 'Khách đã chỉnh sửa'); await click('Lưu thay đổi');
    await contains('Khách đã chỉnh sửa');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customer.id } })).name, 'Khách đã chỉnh sửa');
    const api = 'http://localhost:3000/api/v1';
    const authenticate = value => fetch(api + '/auth/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: value }),
    });
    const previousSession = await authenticate(password);
    assert.equal(previousSession.status, 201);
    const oldAccess = (await previousSession.json()).accessToken;
    const replacement = randomUUID() + '-Aa1';
    await click('Đặt lại mật khẩu');
    await contains('Đặt lại mật khẩu khách hàng');
    await fill('Mật khẩu mới', replacement);
    await fill('Nhập lại mật khẩu mới', replacement);
    await capture('reset-password-desktop');
    const resetResponse = page.waitForResponse(r => r.url().endsWith('/reset-password') && r.request().method() === 'POST');
    await click('Xác nhận đặt lại');
    assert.equal((await resetResponse).status(), 201);
    await contains('Đã đặt lại mật khẩu. Khách hàng cần đăng nhập lại.');
    assert.equal((await authenticate(password)).status, 401);
    assert.equal((await authenticate(replacement)).status, 201);
    assert.equal((await fetch(api + '/users/me', { headers: { Authorization: 'Bearer ' + oldAccess } })).status, 401);
    const resetUser = await db.user.findUniqueOrThrow({ where: { id: customer.id } });
    assert(await argon2.verify(resetUser.passwordHash, replacement));
    const resetAudit = await db.adminAuditEvent.findMany({ where: { targetId: customer.id } });
    assert(resetAudit.some(e => e.details?.after?.passwordChanged === true));
    assert(!JSON.stringify(resetAudit).includes(replacement));
    pass('Reset customer password from desktop list; new password works and old password/session are rejected');
    await click('Khóa tài khoản'); await click('Lưu thay đổi'); await contains('Mở khóa tài khoản');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customer.id } })).active, false);
    await click('Mở khóa tài khoản'); await click('Lưu thay đổi'); await contains('Khóa tài khoản');
    pass('Edited, locked and unlocked directly from desktop list');
    await capture('list-desktop');
    await page.setViewportSize({ width: 375, height: 900 }); await page.waitForTimeout(400);
    await capture('list-mobile');
    await click('Đặt lại mật khẩu'); await contains('Đặt lại mật khẩu khách hàng');
    await capture('reset-password-mobile'); await click('Đóng');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customer.id } })).passwordHash, resetUser.passwordHash);
    pass('Password reset dialog fits mobile and cancellation preserves the password');
    await click('Xóa tài khoản'); await capture('delete-mobile'); await click('Đóng');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customer.id } })).deletedAt, null);
    await click('Xóa tài khoản'); await click('Xác nhận xóa'); await contains('Không tìm thấy khách hàng');
    const removed = await db.user.findUniqueOrThrow({ where: { id: customer.id } });
    assert(removed.deletedAt); assert.equal(removed.active, false);
    pass('Cancelled and confirmed deletion from mobile list');
    await click('Thêm khách hàng');
    await fill('Họ và tên', 'Quản lý được cấp quyền'); await fill('Email', privilegedEmail);
    await fill('Mật khẩu', password); await fill('Nhập lại mật khẩu', password);
    const access = page.getByRole('checkbox', { name: 'Có quyền truy cập trang quản trị', exact: true });
    await reveal(access); await access.click();
    await fill('Tên đăng nhập quản trị', 'access-' + marker);
    await capture('admin-access-mobile');
    await click('Tạo tài khoản'); await contains('Nhân sự & quyền truy cập');
    privileged = await db.user.findUniqueOrThrow({ where: { email: privilegedEmail } });
    assert.equal(privileged.role, 'MANAGER');
    assert.equal(privileged.username, 'access-' + marker);
    await contains('Quản lý được cấp quyền');
    pass('Access checkbox creates manager and opens filtered staff list on mobile');
    const loginContext = await browser.newContext({ viewport: { width: 1440, height: 1050 } });
    page = await loginContext.newPage();
    await page.goto(base + '/#/admin'); await semantics(); await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', privileged.username); await fill('Mật khẩu', password); await click('Đăng nhập quản trị');
    await contains('Tổng quan');
    assert(!(await page.locator('body').ariaSnapshot()).includes('Đăng nhập quản trị'));
    await capture('granted-manager-login');
    pass('Granted manager signs in to admin using the chosen username');
    assert.deepEqual(report.errors, []);
  } catch (e) {
    report.errors.push(e.stack || String(e));
    if (page) {
      await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
    }
    process.exitCode = 1;
  } finally {
    await browser?.close();
    customer ||= await db.user.findUnique({ where: { email } });
    privileged ||= await db.user.findUnique({ where: { email: privilegedEmail } });
    const ids = [staff?.id, customer?.id, privileged?.id].filter(Boolean);
    await db.adminAuditEvent.deleteMany({ where: { OR: [{ actorId: { in: ids } }, { targetId: { in: ids } }] } });
    await db.user.deleteMany({ where: { id: { in: ids } } });
    await db.$disconnect();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  }
})();
