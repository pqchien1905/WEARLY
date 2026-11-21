// Local acceptance with disposable customers, inventory and orders. No mail or
// payment-provider requests; cleanup only uses IDs created by this run.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID, randomInt } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const { customerSession } = require('./customer-account-session.cjs');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(5173|8080)$/.test(base)) throw Error('Local frontend required');
const output = path.resolve(__dirname, '../.tools/customers-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), customers = [], orders = [];
  const report = { passed: [], errors: [], unexpectedResponses: [] };
  let staff, product, category, brand, variant, session, browser, page, expectedConflict = false;
  try {
    const marker = 'customers-qa-' + randomUUID().slice(0, 8), password = randomUUID() + '-Aa1';
    const passwordHash = await argon2.hash(password);
    const usedPhone = '09' + randomInt(10000000, 99999999), ownPhone = '08' + randomInt(10000000, 99999999);
    assert.equal(await db.user.count({ where: { phone: { in: [usedPhone, ownPhone] } } }), 0);
    staff = await db.user.create({ data: { username: marker, email: marker + '@example.invalid', name: 'Quản trị kiểm thử', role: 'ADMIN', passwordHash } });
    for (let i = 0; i < 22; i++) customers.push(await db.user.create({ data: {
      name: i === 0 ? 'Nguyễn Minh Anh' : `Khách kiểm thử ${i}`, email: `${marker}-${i}@example.invalid`, passwordHash,
      phone: i === 1 ? usedPhone : '', active: i !== 21, createdAt: new Date(Date.now() - i * 3 * 86400000),
    } }));
    category = await db.category.create({ data: { name: marker, slug: marker } });
    brand = await db.brand.create({ data: { name: marker, slug: marker } });
    product = await db.product.create({ data: { name: 'Áo linen kiểm thử', slug: marker, active: false, description: '', material: '', style: '', categoryId: category.id, brandId: brand.id,
      variants: { create: { sku: marker, size: 'M', color: 'Trắng', colorHex: '#ffffff', price: '320000', inventory: { create: { quantity: 20 } } } },
    }, include: { variants: true } }); variant = product.variants[0];
    for (let i = 0; i < 12; i++) {
      const paid = i === 0, orderId = randomUUID();
      const states = paid ? ['PENDING', 'CONFIRMED', 'SHIPPED', 'DELIVERED'] : ['PENDING'];
      const order = await db.order.create({ data: { id: orderId, userId: customers[0].id, idempotencyKey: randomUUID(), requestHash: marker,
        status: paid ? 'DELIVERED' : 'PENDING', version: paid ? 3 : 0, createdAt: new Date(Date.now() - i * 86400000),
        addressSnapshot: { recipient: 'Nguyễn Minh Anh', phone: ownPhone, address: '123 Nguyễn Huệ, TP. Hồ Chí Minh' }, subtotal: '320000', shipping: '0', total: '320000',
        items: { create: { variantId: variant.id, name: product.name, slug: marker, sku: marker, size: 'M', color: 'Trắng', image: '', unitPrice: '320000', quantity: 1 } },
        payment: { create: { provider: 'cod', amount: '320000', status: paid ? 'PAID' : 'PENDING', ...(paid ? { settlement: { create: { actorId: staff.id, amount: '320000', reference: marker } } } : {}) } },
        history: { create: states.map((status, version) => ({ status, version, actorId: staff.id })) },
        ...(paid ? { shipment: { create: { status: 'DELIVERED', trackingCode: 'LOCAL-' + orderId.toUpperCase(), events: { create: [
          { status: 'IN_TRANSIT', orderVersion: 2, actorId: staff.id, eventKey: randomUUID() },
          { status: 'DELIVERED', orderVersion: 3, actorId: staff.id, eventKey: randomUUID() },
        ] } } } } : {}),
      } }); orders.push(order.id);
    }
    session = await customerSession(customers[0].email);
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, timezoneId: 'Asia/Bangkok', reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]); page = await context.newPage(); page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (/\/api\/v1\/(admin|users)/.test(r.url()) && r.status() >= 400 && !(expectedConflict && r.status() === 409)) report.unexpectedResponses.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    const snapshot = () => page.locator('body').ariaSnapshot();
    const button = name => page.getByRole('button', { name, exact: typeof name === 'string' });
    const passed = text => { report.passed.push(text); console.log(text); };
    async function contains(text) { for (let i = 0; i < 130; i++) { if ((await snapshot()).includes(text)) return; await page.waitForTimeout(100); } throw Error('Missing UI: ' + text); }
    async function semantics() { await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics')); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 60; i++) {
        const box = await node.boundingBox(), v = page.viewportSize(), inset = page.url().includes('#/account') ? 220 : 85;
        if (box && box.y >= inset && box.y + box.height < v.height - 20) return;
        await page.mouse.move(v.width * .8, v.height * .7); await page.mouse.wheel(0, box?.y < inset ? -450 : 450); await page.waitForTimeout(90);
      } throw Error('Control outside viewport: ' + node);
    }
    async function click(name) { const node = button(name); await reveal(node); await node.click(); await page.waitForTimeout(150); }
    async function fill(label, value) { const node = page.getByRole('textbox', { name: new RegExp('^' + label) }); await reveal(node); await node.click(); await page.waitForTimeout(130); await node.fill(value); await page.waitForTimeout(130); }
    async function route(route, text) { await page.evaluate(route => { location.hash = route; }, route); await contains(text); await page.waitForTimeout(350); }
    async function select(label, option) { const node = button(new RegExp('^' + label)); await reveal(node); await node.click(); await page.getByRole('menuitem', { name: option, exact: true }).click(); await page.waitForTimeout(350); }
    async function capture(name) { await page.screenshot({ path: path.join(output, name + '.png') }); fs.writeFileSync(path.join(output, name + '.txt'), await snapshot()); }
    async function customer(index = 0) { await route('/admin/customers/' + customers[index].id, 'Hồ sơ khách hàng'); await contains('Sao chép mã'); }
    await page.goto(base + '/#/admin/customers'); await semantics(); await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', marker); await fill('Mật khẩu', password); await click('Đăng nhập quản trị');
    await route('/admin/customers', 'Tìm kiếm khách hàng'); await fill('Tìm kiếm khách hàng', marker); await click('Tìm kiếm'); await contains('22 khách hàng phù hợp bộ lọc');
    await capture('customers-desktop');
    await click('Trang sau'); await contains('Trang 2/2'); await page.reload(); await semantics(); await contains('Trang 2/2');
    await select('Sắp xếp', 'Nhiều đơn hàng nhất'); assert(!page.url().includes('page=2'));
    await select('Lịch sử mua hàng', 'Đã có đơn hàng'); await contains('1 khách hàng phù hợp bộ lọc');
    const first = button('Xem khách hàng').first(); await reveal(first); await first.click(); await contains('Hồ sơ khách hàng'); await contains('320.000');
    await click('Trang đơn sau'); await contains('Trang 2/2 · 12 đơn hàng');
    const orderLink = button('Xem đơn hàng').first(); await reveal(orderLink); await orderLink.click(); await contains('Chi tiết đơn hàng');
    await click('Về khách hàng'); await contains('Trang 2/2 · 12 đơn hàng');
    await click('Về danh sách khách hàng'); await contains('1 khách hàng phù hợp bộ lọc'); assert(page.url().includes('orders=has_orders'));
    await click('Xóa bộ lọc'); await fill('Tìm kiếm khách hàng', marker); await click('Tìm kiếm'); await contains('22 khách hàng phù hợp bộ lọc');
    await page.getByRole('checkbox', { name: 'Đã khóa', exact: true }).click(); await contains('1 khách hàng phù hợp bộ lọc');
    await select('Ngày đăng ký', '30 ngày gần nhất'); await contains('Không tìm thấy khách hàng');
    passed('Real login; search, sort, status/new/order filters, pagination, reload and customer → order → customer navigation');

    for (const width of [1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1050 }); await route('/admin/customers?q=' + marker, '22 khách hàng phù hợp bộ lọc');
      await page.mouse.move(width * .8, 700); await page.mouse.wheel(0, -20000); await page.waitForTimeout(250); await capture('customers-' + width);
      await reveal(button('Xem khách hàng').first()); await capture('customers-list-' + width);
      await customer(); await reveal(button('Chỉnh sửa thông tin')); await capture('customer-detail-' + width);
      await click('Chỉnh sửa thông tin'); await contains('Chỉnh sửa khách hàng'); await capture('customer-edit-' + width); await click('Đóng');
    }
    passed('Customer list, detail and editor fit 1440 / 768 / 375 pixel viewports');

    await page.setViewportSize({ width: 1440, height: 1050 });
    await route('/account', 'Thông tin cá nhân');
    expectedConflict = true;
    await fill('Điện thoại', '+84 ' + usedPhone.slice(1)); await click('Lưu hồ sơ'); await contains('Số điện thoại đã được tài khoản khác sử dụng');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customers[0].id } })).phone, '');
    await fill('Điện thoại', '+84 ' + ownPhone.slice(1)); await click('Lưu hồ sơ'); await contains('Thông tin mới đã được lưu.'); expectedConflict = false;
    assert.equal((await session.request('users/me')).phone, ownPhone);
    passed('Customer self-service blocks a duplicate international-format number and saves a unique normalized number');

    await customer(); await click('Chỉnh sửa thông tin'); expectedConflict = true;
    await fill('Số điện thoại', usedPhone); await click('Lưu thay đổi'); await contains('Số điện thoại đã được tài khoản khác sử dụng');
    await fill('Số điện thoại', ownPhone); await fill('Email', customers[1].email); await click('Lưu thay đổi'); await contains('Email đã được tài khoản khác sử dụng');
    await fill('Họ và tên', 'Nguyễn Minh Anh đã cập nhật'); await fill('Email', `updated-${marker}@example.invalid`); await click('Lưu thay đổi'); await contains('Đã lưu thông tin khách hàng.'); expectedConflict = false;
    const updated = await db.user.findUniqueOrThrow({ where: { id: customers[0].id } });
    assert.equal(updated.name, 'Nguyễn Minh Anh đã cập nhật'); assert.equal(updated.phone, ownPhone); assert.equal(updated.email, `updated-${marker}@example.invalid`);
    await session.request('users/me', { expected: 401 });
    assert.equal((await db.order.findUniqueOrThrow({ where: { id: orders[0] } })).addressSnapshot.recipient, 'Nguyễn Minh Anh');
    await page.reload(); await semantics(); await contains('Nguyễn Minh Anh đã cập nhật'); await contains('12 đơn hàng');
    passed('Admin contact validation, normalized edits, persistence, session revocation and unchanged historical recipients');

    await click('Khóa tài khoản'); await contains('Khóa tài khoản khách hàng'); await click('Lưu thay đổi'); await contains('Đã khóa tài khoản khách hàng.');
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customers[0].id } })).active, false);
    await click('Mở khóa tài khoản'); await click('Lưu thay đổi'); await contains('Đã mở khóa tài khoản khách hàng.');
    await session.request('users/me', { expected: 401 });
    await click('Chỉnh sửa thông tin'); await fill('Họ và tên', 'Bản nháp cũ');
    await db.user.update({ where: { id: customers[0].id }, data: { name: 'Tên từ phiên khác', updatedAt: new Date(Date.now() + 5) } });
    expectedConflict = true; await click('Lưu thay đổi'); await contains('Tải lại dữ liệu'); assert.equal(await button('Lưu thay đổi').count(), 0);
    await click('Tải lại dữ liệu'); await contains('Tên từ phiên khác'); expectedConflict = false;
    assert.equal((await db.user.findUniqueOrThrow({ where: { id: customers[0].id } })).name, 'Tên từ phiên khác');
    passed('Lock/unlock preserves orders and revoked sessions; stale edits cannot overwrite newer changes');
    assert.deepEqual(report.errors, []); assert.deepEqual(report.unexpectedResponses, []);
  } catch (error) {
    report.failure = error.message;
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); }
    throw error;
  } finally {
    await browser?.close(); await session?.close();
    try {
      const users = [...customers.map(c => c.id), ...(staff ? [staff.id] : [])];
      await db.adminAuditEvent.deleteMany({ where: { targetId: { in: users } } });
      await db.orderItem.deleteMany({ where: { orderId: { in: orders } } });
      await db.payment.deleteMany({ where: { orderId: { in: orders } } });
      await db.order.deleteMany({ where: { id: { in: orders } } });
      if (variant) { await db.inventory.deleteMany({ where: { variantId: variant.id } }); await db.productVariant.delete({ where: { id: variant.id } }); }
      if (product) await db.product.delete({ where: { id: product.id } });
      if (category) await db.category.delete({ where: { id: category.id } });
      if (brand) await db.brand.delete({ where: { id: brand.id } });
      await db.user.deleteMany({ where: { id: { in: users } } }); report.cleaned = true;
    } finally { await db.$disconnect(); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
