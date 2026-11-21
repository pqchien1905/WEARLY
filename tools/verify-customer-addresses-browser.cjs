// Local acceptance. Only a temporary address is created/edited/deleted;
// the customer's original default is restored even if a browser check fails.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession, customerEmail } = require('./customer-account-session.cjs');
const output = path.resolve(__dirname, '../.tools/addresses-redesign');
const origin = process.argv[2] || 'http://localhost:5173';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const session = await customerSession(customerEmail());
  const report = { origin, passed: [], errors: [], requests: [] };
  const before = await session.request('users/me/addresses');
  const originalDefault = before.find(a => a.isDefault);
  assert(originalDefault);
  const prefix = 'Kiểm tra địa chỉ ' + Date.now();
  let browser, page, temporaryId;
  const addressFields = rows => rows.map(({ id, label, recipient, phone, address, isDefault }) =>
    ({ id, label, recipient, phone, address, isDefault })).sort((a, b) => a.id.localeCompare(b.id));
  try {
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce', hasTouch: true });
    await context.addCookies([session.cookie]);
    page = await context.newPage(); page.setDefaultTimeout(15000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => {
      if (r.url().includes('/api/v1/')) report.requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() });
    });
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function includes(text) {
      for (let i = 0; i < 150; i++) {
        const snapshot = await page.locator('body').ariaSnapshot();
        if (snapshot.includes(text)) return snapshot;
        await page.waitForTimeout(100);
      }
      throw Error('Missing content: ' + text);
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -20000); await page.waitForTimeout(200);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 45; i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height;
        const inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 12) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 12 - b.height) / 2 : 200);
        await page.waitForTimeout(80);
      }
      throw Error('Cannot reach control');
    }
    async function click(name, last = false) {
      const nodes = page.getByRole('button', { name, exact: true });
      const node = last ? nodes.last() : nodes.first();
      await reveal(node); await node.click();
    }
    async function fill(name, value) {
      const node = page.getByRole('textbox', { name, exact: name !== 'Tên gợi nhớ' });
      await reveal(node); await node.click(); await node.fill(value);
    }
    async function capture(name) {
      const close = page.getByRole('button', { name: 'Đóng', exact: true });
      if (await close.count()) await close.last().click();
      await page.mouse.move(8, page.viewportSize().height - 16); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await page.goto(origin + '/#/account/addresses'); await semantics(); await includes(`${before.length} địa chỉ đã lưu`);
    for (const width of [2560, 1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1080 }); await top();
      for (const address of before) await includes(address.address);
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      if (width >= 1440) await includes('Thao tác');
      await capture(`addresses-${width}`);
      await click('Sửa ' + originalDefault.label); await includes('Chỉnh sửa địa chỉ');
      await capture(`address-editor-${width}`); await click('Đóng địa chỉ');
      report.passed.push(`Address columns, long text and editor render at ${width}px`);
    }
    await page.setViewportSize({ width: 1440, height: 1080 }); await top();
    await click('Thêm địa chỉ'); await includes('Địa chỉ mới');
    await click('Lưu địa chỉ'); await includes('Nhập số điện thoại 10 chữ số.');
    await capture('address-validation');
    await fill('Tên gợi nhớ', prefix); await fill('Người nhận', session.user.name);
    await fill('Điện thoại nhận hàng', '0901234567');
    await fill('Địa chỉ nhận hàng', 'Địa chỉ kiểm thử tạm thời, sẽ được xóa sau khi kiểm tra');
    await click('Lưu địa chỉ'); await includes(`${before.length + 1} địa chỉ đã lưu`);
    temporaryId = (await session.request('users/me/addresses')).find(a => a.label === prefix)?.id;
    assert(temporaryId);
    await click('Sửa ' + prefix); await includes('Chỉnh sửa địa chỉ');
    await fill('Tên gợi nhớ', prefix + ' edited'); await click('Lưu địa chỉ'); await includes(prefix + ' edited');
    assert.equal((await session.request('users/me/addresses')).find(a => a.id === temporaryId).label, prefix + ' edited');
    report.passed.push('Required fields validate; a temporary address is created and edited through the real API');
    await click('Đặt làm mặc định', true); await includes('Đã đổi địa chỉ mặc định.');
    assert.equal((await session.request('users/me/addresses')).find(a => a.isDefault).id, temporaryId);
    await page.reload(); await semantics(); await includes(`${before.length + 1} địa chỉ đã lưu`);
    assert.equal((await session.request('users/me/addresses')).find(a => a.isDefault).id, temporaryId);
    // The API sorts the default first, then creation time: the original default
    // is the first non-default row in this existing customer's address book.
    await click('Đặt làm mặc định'); await includes('Đã đổi địa chỉ mặc định.');
    assert.equal((await session.request('users/me/addresses')).find(a => a.isDefault).id, originalDefault.id);
    report.passed.push('Default address persists after reload and the original default is restored');
    await click('Xóa ' + prefix + ' edited'); await includes('Xóa địa chỉ ' + prefix + ' edited?');
    await capture('address-delete-confirmation'); await click('Giữ lại');
    assert.equal((await session.request('users/me/addresses')).length, before.length + 1);
    await click('Xóa ' + prefix + ' edited'); await click('Xác nhận'); await includes(`${before.length} địa chỉ đã lưu`);
    temporaryId = undefined;
    assert.deepEqual(addressFields(await session.request('users/me/addresses')), addressFields(before));
    report.passed.push('Delete can be cancelled or confirmed; all original address fields and default are preserved');
    await top(); await capture('addresses-final');
    assert.deepEqual(report.errors, []);
    assert(report.requests.every(r => r.status < 400 ||
      (r.status === 401 && r.path === '/api/v1/auth/browser/admin/refresh' && r.method === 'POST')));
    console.log(JSON.stringify({ passed: report.passed, errors: report.errors }, null, 2));
  } catch (error) {
    report.errors.push(error.message);
    if (page) {
      await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
    }
    throw error;
  } finally {
    try {
      const current = await session.request('users/me/addresses');
      if (current.find(a => a.isDefault)?.id !== originalDefault.id) {
        await session.request('users/me/addresses/' + originalDefault.id, { method: 'PATCH', body: { isDefault: true } });
      }
      for (const address of current.filter(a => a.id === temporaryId || a.label === prefix || a.label === prefix + ' edited')) {
        await session.request('users/me/addresses/' + address.id, { method: 'DELETE' });
      }
    } finally {
      fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
      await browser?.close(); await session.close();
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
