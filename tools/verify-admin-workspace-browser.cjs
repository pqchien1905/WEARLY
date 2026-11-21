// Uses a disposable staff identity and the real API. No business data is changed.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { localDatabase } = require('./seed-customer-account.cjs');
const argon2 = require('../backend/node_modules/argon2');
const root = path.resolve(__dirname, '..');
const output = path.join(root, '.tools/admin-redesign');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:8080';
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase();
  let user, browser, page;
  const report = { passed: [], errors: [], failedRequests: [] };
  try {
    const username = `qa-admin-${randomUUID().slice(0, 8)}`, password = randomUUID() + '-Aa1';
    user = await db.user.create({ data: { email: `${username}@example.invalid`, username, name: 'Quản trị kiểm thử', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce' });
    page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/admin/') && r.status() >= 400) report.failedRequests.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    const button = name => page.getByRole('button', { name, exact: true });
    async function fill(name, value) {
      const field = page.getByRole('textbox', { name: new RegExp('^' + name) });
      await field.click(); await page.waitForTimeout(150);
      await field.fill(value); await page.waitForTimeout(150);
    }
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function contains(text) {
      for (let i = 0; i < 100; i++) {
        if ((await page.locator('body').ariaSnapshot()).includes(text)) return;
        await page.waitForTimeout(150);
      }
      throw Error('Missing UI: ' + text);
    }
    async function route(route, text) {
      await page.evaluate(route => { location.hash = route; }, route);
      await contains(text); await page.waitForTimeout(450);
      const snapshot = await page.locator('body').ariaSnapshot();
      assert(!snapshot.includes('Chưa tải được dữ liệu'), `Failed load at ${route}`);
    }
    async function reveal(locator) {
      await locator.waitFor({ state: 'attached' });
      for (let i = 0; i < 30; i++) {
        const b = await locator.boundingBox(), v = page.viewportSize();
        if (b && b.y >= 85 && b.y + b.height <= v.height - 25) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, b?.y < 85 ? -400 : 400); await page.waitForTimeout(100);
      }
      throw Error('Control outside viewport');
    }
    await page.goto(base + '/#/admin'); await semantics();
    await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', username);
    await fill('Mật khẩu', password);
    await button('Đăng nhập quản trị').click();
    await contains('Đơn hàng mới nhất');
    await page.screenshot({ path: path.join(output, 'dashboard-desktop.png') });
    report.passed.push('Real staff login and API dashboard');
    await page.reload(); await semantics(); await contains('Đơn hàng mới nhất');
    report.passed.push('Session persists on refresh');
    const destinations = [
      ['products', 'Tìm kiếm Sản phẩm'], ['inventory', 'Tìm kiếm Biến thể & kho'],
      ['orders', 'Tìm kiếm đơn hàng'], ['customers', 'Tìm kiếm khách hàng'],
      ['categories', 'Thêm danh mục'], ['brands', 'Thêm thương hiệu'],
      ['collections', 'Thêm bộ sưu tập'], ['promotions', 'Khuyến mãi'],
      ['content', 'Xuất bản'], ['support', 'Hỗ trợ'],
      ['mail', 'Theo dõi thư'], ['ai-monitoring', 'Vận hành'], ['staff', 'Nhân sự'],
    ];
    for (const width of [1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1000 });
      await route('/admin', 'Đơn hàng mới nhất');
      await page.screenshot({ path: path.join(output, `dashboard-${width}.png`) });
      for (const [pathName, heading] of destinations) {
        await route('/admin/' + pathName, heading);
        await page.screenshot({ path: path.join(output, `${pathName}-${width}.png`) });
      }
      report.passed.push(`13 admin pages and dashboard at ${width}px`);
      console.log(`Admin browser: reviewed ${width}px.`);
    }
    await button('Mở menu quản trị').click(); await contains('Không gian quản trị');
    await button('Tổng quan').click(); await contains('Đơn hàng mới nhất');
    report.passed.push('Mobile drawer navigation');
    await page.setViewportSize({ width: 1440, height: 1000 });
    await route('/admin/products', 'Tìm kiếm Sản phẩm');
    await fill('Tìm kiếm Sản phẩm', 'no-product-' + randomUUID().slice(0, 8));
    await button('Tìm kiếm').click(); await contains('Không tìm thấy kết quả');
    assert(new URL(page.url().split('#')[1], base).searchParams.has('q'));
    await button('Xóa bộ lọc').first().click(); await contains('Chỉnh sửa sản phẩm');
    const next = button('Trang sau'); await reveal(next); await next.click();
    await contains('Trang 2/');
    await page.reload(); await semantics(); await contains('Trang 2/');
    await route('/admin/products', 'Tìm kiếm Sản phẩm');
    await page.getByRole('checkbox', { name: 'Đã ẩn', exact: true }).click();
    await page.waitForFunction(() => location.hash.includes('status=hidden'));
    await contains('kết quả');
    await page.reload(); await semantics(); await contains('Chỉnh sửa sản phẩm');
    assert(page.url().includes('status=hidden'));
    report.passed.push('Server search, empty results, reset and persistent status filter');
    const edit = button('Chỉnh sửa sản phẩm').first(); await reveal(edit); await edit.click();
    await contains('Tên sản phẩm');
    await page.screenshot({ path: path.join(output, 'product-editor-desktop.png') });
    await page.setViewportSize({ width: 375, height: 1000 });
    await page.screenshot({ path: path.join(output, 'product-editor-mobile.png') });
    report.passed.push('Product editor opens with real API data');
    await route('/admin/orders?status=PENDING', 'Xem đơn hàng');
    const detail = button('Xem đơn hàng').first(); await reveal(detail); await detail.click();
    await contains('Chi tiết đơn hàng');
    await page.screenshot({ path: path.join(output, 'order-detail-mobile.png') });
    report.passed.push('Filtered order list opens real order detail');
    await route('/admin/inventory?status=low', 'Điều chỉnh kho');
    const adjust = button('Điều chỉnh kho').first(); await reveal(adjust); await adjust.click();
    await contains('Số lượng thay đổi');
    await page.screenshot({ path: path.join(output, 'inventory-dialog-mobile.png') });
    await button('Đóng').click();
    report.passed.push('Stock adjustment dialog opens and cancels without a write');
    await (async()=>{await page.getByRole('button',{name:'Tài khoản quản trị',exact:true}).click();await page.getByRole('menuitem',{name:'Đăng xuất',exact:true}).or(page.getByRole('button',{name:'Đăng xuất',exact:true})).first().click();})(); await contains('Đăng nhập quản trị');
    report.passed.push('Staff logout');
    assert.deepEqual(report.errors, []); assert.deepEqual(report.failedRequests, []);
    console.log(JSON.stringify(report));
  } catch (e) {
    report.failure = e.message;
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); }
    throw e;
  } finally {
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    await browser?.close();
    if (user) await db.user.delete({ where: { id: user.id } });
    await db.$disconnect();
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
