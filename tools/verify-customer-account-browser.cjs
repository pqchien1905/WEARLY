const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession, customerEmail } = require('./customer-account-session.cjs');
const output = path.resolve(__dirname, '../.tools/order-redesign');
const routes = [
  ['profile', '/account', 'Thông tin cá nhân'],
  ['orders', '/account/orders', '3 đơn hàng'],
  ['reviews', '/account/reviews', '2 đánh giá'],
  ['addresses', '/account/addresses', '2 địa chỉ đã lưu'],
  ['style', '/account/style', 'Lưu hồ sơ phong cách'],
  ['try-ons', '/account/try-ons', 'lượt thử đồ'],
  ['wishlist', '/wishlist', '6 sản phẩm đã lưu'],
  ['settings', '/account/settings', 'Mật khẩu và bảo mật'],
];
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const session = await customerSession(customerEmail());
  const report = { account: session.user.email, passed: [], errors: [], requests: [] };
  let browser, page, temporaryAddressId;
  try {
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, hasTouch: true, reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]);
    page = await context.newPage();
    page.setDefaultTimeout(15000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) report.requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function includes(text) {
      for (let i = 0; i < 100; i++) {
        const snapshot = await page.locator('body').ariaSnapshot();
        if (snapshot.includes(text)) return snapshot;
        await page.waitForTimeout(100);
      }
      throw Error('Missing content: ' + text);
    }
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -20000); await page.waitForTimeout(200);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 45; i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height, inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 12) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 12 - b.height) / 2 : 200);
        await page.waitForTimeout(80);
      }
      throw Error('Cannot reach control');
    }
    async function click(name, first = false) {
      const nodes = page.getByRole('button', { name, exact: true }), node = first ? nodes.first() : nodes.last();
      await reveal(node); await node.click();
    }
    async function fill(name, text) {
      const node = page.getByRole('textbox', { name, exact: !['Nội dung đánh giá', 'Tên gợi nhớ'].includes(name) });
      await reveal(node); await node.click(); await node.fill(text);
    }
    async function route(value, ready) { await page.evaluate(value => { location.hash = value; }, value); await includes(ready); await top(); }
    async function capture(name) {
      const toastClose = page.getByRole('button', { name: 'Đóng', exact: true });
      if (await toastClose.count()) await toastClose.last().click();
      await page.mouse.move(8, page.viewportSize().height - 16); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await page.goto(session.origin + '/#/account'); await semantics(); await includes('Thông tin cá nhân');
    await fill('Họ và tên', session.user.name); await fill('Điện thoại (không bắt buộc)', session.user.phone); await click('Lưu hồ sơ'); await includes('Đã lưu hồ sơ.');
    await page.reload(); await semantics(); await includes(session.user.name);
    assert.equal(await page.getByRole('textbox', { name: 'Email đăng nhập', exact: true }).count(), 1);
    report.passed.push('Existing account restores its session; profile saves and persists after reload');
    await route('/account/style', 'Lưu hồ sơ phong cách');
    await click('Lưu hồ sơ phong cách'); await includes('Đã lưu hồ sơ phong cách.');
    await click('Tải lại hồ sơ'); await includes('Size thường chọn M');
    report.passed.push('Style saves to API and reloads the selected preferences');
    await route('/account/addresses', '2 địa chỉ đã lưu');
    const savedAddresses = await session.request('users/me/addresses');
    const label = 'QA browser ' + Date.now();
    await click('Thêm địa chỉ'); await includes('Địa chỉ mới');
    await fill('Tên gợi nhớ', label); await fill('Người nhận', session.user.name);
    await fill('Điện thoại nhận hàng', session.user.phone);
    await fill('Địa chỉ nhận hàng', 'Địa chỉ kiểm thử tạm thời, sẽ được xóa sau kiểm tra');
    await click('Lưu địa chỉ'); await includes('3 địa chỉ đã lưu');
    const addressData = await session.request('users/me/addresses');
    temporaryAddressId = addressData.find(a => a.label === label).id;
    await click('Sửa ' + label); await includes('Chỉnh sửa địa chỉ');
    await fill('Tên gợi nhớ', label + ' edited'); await click('Lưu địa chỉ');
    await includes(label + ' edited');
    await click('Xóa ' + label + ' edited'); await click('Xác nhận');
    await includes('2 địa chỉ đã lưu'); temporaryAddressId = undefined;
    assert.deepEqual(await session.request('users/me/addresses'), savedAddresses);
    report.passed.push('Address create, edit and confirmed delete work in the browser and preserve the original addresses');
    await route('/account/reviews', '2 đánh giá');
    const before = await session.request('users/me/reviews');
    const comment = before.items[0].comment;
    await click('Sửa đánh giá', true); await includes('Nội dung đánh giá');
    await fill('Nội dung đánh giá', comment); await click('Lưu đánh giá');
    await includes('2 đánh giá');
    assert.equal((await session.request('users/me/reviews')).items[0].comment, comment);
    report.passed.push('An owned review opens, saves and persists through the actual editor');
    await route('/account/orders', '3 đơn hàng');
    const orders = await session.request('orders?limit=100');
    for (const order of orders.items) assert.match(order.code, /^WR[A-F0-9]{6,16}$/);
    assert.equal(new Set(orders.items.map(o => o.code)).size, orders.items.length);
    await fill('Tìm mã đơn hoặc tên sản phẩm', orders.items[0].code.toLowerCase());
    await includes('1 đơn hàng'); await click('Xóa bộ lọc'); await includes('3 đơn hàng');
    await click('Xem chi tiết', true); await includes('Thông tin nhận hàng');
    await capture('order-detail-1440');
    report.passed.push('Populated orders search, clear filters and open a real detail with tracking');
    await route('/account/settings', 'Mật khẩu và bảo mật'); await click('Đổi mật khẩu');
    await includes('Trở về cài đặt tài khoản');
    const email = page.getByRole('textbox', { name: 'Email', exact: true });
    await reveal(email); await email.click(); assert.equal(await email.inputValue(), session.user.email);
    await click('Trở về cài đặt tài khoản');
    report.passed.push('Password recovery opens with the correct email; no password is changed');
    const latestStylist = await session.request('ai/stylist/requests/latest');
    if (latestStylist.receipt?.status === 'completed') {
      await route('/ai-stylist', 'Tổng trang phục:');
      for (const pick of latestStylist.receipt.result.picks) await includes(pick.product.name);
      await capture('stylist-live-1440');
      report.passed.push('The live Gemini Stylist result restores in the browser with the selected catalog products');
    }
    for (const width of [2560, 1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1080 });
      for (const [name, value, ready] of routes) {
        await route(value, ready);
        const content = await page.locator('body').ariaSnapshot();
        assert(!/dữ liệu mẫu|địa chỉ minh họa|Mô phỏng vận chuyển local/i.test(content));
        if (name === 'orders') {
          for (const order of orders.items) {
            assert(content.includes(order.code));
            assert(!content.includes(order.id));
          }
        }
        assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
        await capture(`${name}-${width}`);
      }
      await route('/account/orders/' + orders.items[0].id, 'Thông tin nhận hàng');
      await capture('order-detail-' + width);
      await reveal(page.getByRole('heading', { name: 'Thông tin thanh toán', exact: true }));
      await capture('order-payment-' + width);
      for (const order of orders.items.slice(1)) {
        await route('/account/orders/' + order.id, 'Thông tin nhận hàng');
        const content = await page.locator('body').ariaSnapshot();
        assert(content.includes(order.code));
        assert(!/dữ liệu mẫu|Mô phỏng vận chuyển local/i.test(content));
        await capture(`order-${order.status.toLowerCase()}-${width}`);
      }
      report.passed.push(`All eight account pages and pending/shipped/delivered order details render at ${width}px with short codes and no sample notices`);
    }
    await page.setViewportSize({ width: 1440, height: 1080 });
    await route('/account/try-ons', 'lượt thử đồ');
    const jobs = await session.request('ai/try-on/jobs');
    if (jobs.items.some(j => j.resultAvailable)) {
      await click('Xem ảnh thử đồ', true); await includes('Ảnh thử đồ riêng tư');
      await capture('try-on-result'); report.passed.push('Live generated private result opens from customer history');
    }
    await route('/account', 'Thông tin cá nhân'); await click('Đăng xuất');
    await includes('Đăng nhập khách hàng');
    assert(!(await context.cookies()).some(c => c.name === 'wearly_customer_session'));
    report.passed.push('Logout revokes only the dedicated QA browser session');
    assert.deepEqual(report.errors, []);
    const unexpected = report.requests.filter(r => r.status >= 400 && !(r.status === 401 && r.path.includes('/auth/browser/admin/')));
    assert.deepEqual(unexpected, []);
    console.log(report.passed.map(p => 'PASS ' + p).join('\n'));
  } catch (error) {
    report.failure = error.message;
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot()); }
    throw error;
  } finally {
    if (temporaryAddressId) await session.request('users/me/addresses/' + temporaryAddressId, { method: 'DELETE' });
    await browser?.close(); await session.close();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
