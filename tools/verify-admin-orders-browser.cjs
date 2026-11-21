// Real local API + browser acceptance. All mutations target disposable fixtures.
// Suppress fixture mail by pre-recording SENT outbox keys; never deliver mail.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { localDatabase } = require('./seed-customer-account.cjs');
const argon2 = require('../backend/node_modules/argon2');
const output = path.resolve(__dirname, '../.tools/orders-acceptance');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:8080';
if (!['localhost', '127.0.0.1'].includes(new URL(base).hostname)) throw Error('Local browser only');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), ids = [];
  const report = { passed: [], errors: [], unexpectedResponses: [] };
  let staff, buyer, category, brand, product, variant, browser, page;
  let allowConflict = false;
  try {
    const marker = `orders-qa-${randomUUID().slice(0, 8)}`, password = randomUUID() + '-Aa1';
    staff = await db.user.create({ data: { username: marker, email: marker + '@example.invalid', name: 'Quản trị kiểm thử', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    buyer = await db.user.create({ data: { email: 'buyer-' + marker + '@example.invalid', name: 'Khách kiểm thử', passwordHash: 'disabled-fixture' } });
    category = await db.category.create({ data: { slug: marker, name: marker } });
    brand = await db.brand.create({ data: { slug: marker, name: marker } });
    product = await db.product.create({ data: { slug: marker, name: 'Áo sơ mi linen · kiểm thử', active: false, description: '', material: 'Linen', style: 'Tối giản', categoryId: category.id, brandId: brand.id,
      variants: { create: { sku: marker, size: 'M', color: 'Trắng', colorHex: '#ffffff', price: '320000', inventory: { create: { quantity: 40 } } } },
    }, include: { variants: true } });
    variant = product.variants[0];
    for (let i = 0; i < 22; i++) {
      const total = String(320000 + i * 1000);
      const order = await db.order.create({ data: { userId: buyer.id, idempotencyKey: randomUUID(), requestHash: marker,
        addressSnapshot: { recipient: 'Nguyễn Minh Anh', phone: '0901234567', address: '123 Nguyễn Huệ, phường Bến Nghé, TP. Hồ Chí Minh' },
        subtotal: total, shipping: '0', total, createdAt: new Date(Date.now() - i * 3600000),
        items: { create: { variantId: variant.id, name: product.name, sku: marker, slug: marker, size: 'M', color: 'Trắng', image: '', unitPrice: total, quantity: 1 } },
        payment: { create: { provider: i === 21 ? 'vnpay' : 'cod', amount: total } },
        history: { create: { status: 'PENDING', version: 0, actorId: buyer.id } },
      }, include: { payment: true } });
      ids.push(order.id);
      await db.mailOutbox.createMany({ data: [...[1, 2, 3, 4, 5].map(v => `order:${order.id}:${v}`), `cod-settled:${order.payment.id}`].map(eventKey => ({ orderId: order.id, eventKey, recipient: buyer.email, subject: 'Browser fixture — suppressed', body: '', status: 'SENT', sentAt: new Date() })) });
    }
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, timezoneId: 'Asia/Bangkok', reducedMotion: 'reduce' });
    page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/admin/') && r.status() >= 400 && !(allowConflict && r.status() === 409)) report.unexpectedResponses.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    const button = name => page.getByRole('button', { name, exact: true });
    const snapshot = () => page.locator('body').ariaSnapshot();
    const passed = text => { report.passed.push(text); console.log(text); };
    async function contains(text) {
      for (let i = 0; i < 120; i++) { if ((await snapshot()).includes(text)) return; await page.waitForTimeout(100); }
      throw Error('Missing UI: ' + text);
    }
    async function semantics() { await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics')); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function fill(label, value) {
      const field = page.getByRole('textbox', { name: new RegExp('^' + label) });
      await reveal(field); await field.click(); await page.waitForTimeout(150); await field.fill(value); await page.waitForTimeout(150);
    }
    async function reveal(locator) {
      await locator.waitFor({ state: 'attached' });
      for (let i = 0; i < 55; i++) {
        const b = await locator.boundingBox(), v = page.viewportSize();
        if (b && b.y >= 85 && b.y + b.height < v.height - 25) return;
        await page.mouse.move(v.width * .8, v.height * .7); await page.mouse.wheel(0, b?.y < 85 ? -500 : 500); await page.waitForTimeout(80);
      }
      throw Error('Control outside viewport: ' + locator);
    }
    async function click(name) { const b = button(name); await reveal(b); await b.click(); }
    async function route(route, text) { await page.evaluate(route => { location.hash = route; }, route); await contains(text); await page.waitForTimeout(350); }
    async function select(label, option) {
      const control = page.getByRole('button', { name: new RegExp('^' + label) });
      await reveal(control); await control.click(); await page.waitForTimeout(150); await page.getByRole('menuitem', { name: option, exact: true }).click(); await page.waitForTimeout(300);
    }
    async function screenshot(name) { await page.screenshot({ path: path.join(output, name + '.png') }); fs.writeFileSync(path.join(output, name + '.txt'), await snapshot()); }
    async function detail(index) { await route('/admin/orders/' + ids[index], 'Chi tiết đơn hàng'); await contains('Sao chép mã đơn'); }
    async function transition(label, state, version) {
      await click(label); await contains('Lưu thay đổi'); await click('Lưu thay đổi');
      await contains('Đã cập nhật đơn');
      const row = await db.order.findUniqueOrThrow({ where: { id: ids[0] }, include: { payment: true } });
      assert.equal(row.status, state); assert.equal(row.version, version); assert.equal(row.payment.status, 'PENDING');
      await page.waitForTimeout(400);
    }
    await page.goto(base + '/#/admin/orders'); await semantics(); await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', marker); await fill('Mật khẩu', password); await click('Đăng nhập quản trị');
    await route('/admin/orders', 'Tìm kiếm đơn hàng');
    await fill('Tìm kiếm đơn hàng', marker); await click('Tìm kiếm'); await contains('22 đơn hàng phù hợp bộ lọc');
    await screenshot('orders-desktop');
    passed('Real staff login and SKU search return exactly the 22 isolated orders');
    await click('Trang sau'); await contains('Trang 2/2'); assert(page.url().includes('page=2'));
    await page.reload(); await semantics(); await contains('Trang 2/2');
    await select('Sắp xếp', 'Giá trị cao nhất'); assert(!page.url().includes('page=2'));
    await select('Phương thức', 'COD'); await contains('21 đơn hàng phù hợp bộ lọc');
    await select('Thanh toán', 'COD chờ đối soát'); await contains('Không tìm thấy đơn hàng');
    await click('Xóa bộ lọc'); await fill('Tìm kiếm đơn hàng', marker); await click('Tìm kiếm'); await contains('22 đơn hàng phù hợp bộ lọc');
    await click('Ngày đặt · UTC+7'); await contains('Lọc theo ngày đặt'); await screenshot('date-range');
    await button('Chuyển sang chế độ nhập').click();
    await fill('Ngày bắt đầu', '01/01/2026'); await fill('Ngày kết thúc', '31/12/2026');
    await click('Áp dụng'); await contains('22 đơn hàng phù hợp bộ lọc');
    assert(page.url().includes('from=2026-01-01')); assert(page.url().includes('to=2026-12-31'));
    await page.getByRole('checkbox', { name: /^Chờ xác nhận/ }).click();
    await contains('22 đơn hàng phù hợp bộ lọc');
    const listUrl = page.url();
    const firstDetail = button('Xem đơn hàng').first(); await reveal(firstDetail); await firstDetail.click();
    await contains('Chi tiết đơn hàng'); await click('Về danh sách đơn'); assert.equal(page.url(), listUrl);
    passed('Pagination persists after refresh; sort, payment filters, date picker, status and detail back link work');
    for (const width of [1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1000 }); await route('/admin/orders?q=' + marker, '22 đơn hàng phù hợp bộ lọc');
      await reveal(page.getByRole('textbox', { name: /^Tìm kiếm đơn hàng/ })); await screenshot('orders-' + width);
      await detail(0); await reveal(button('Xác nhận đơn')); await screenshot('detail-' + width);
    }
    passed('List and detail render at 1440, 768 and 375 pixels without browser exceptions');
    await page.setViewportSize({ width: 1440, height: 1000 }); await detail(0);
    await transition('Xác nhận đơn', 'CONFIRMED', 1); await transition('Bắt đầu giao hàng', 'SHIPPED', 2); await transition('Đánh dấu đã giao', 'DELIVERED', 3);
    await click('Đối soát COD'); await fill('Số tiền đã thu', '319999'); await fill('Mã đối soát', marker); await click('Lưu thay đổi'); await contains('Số tiền phải bằng tổng đơn');
    await fill('Số tiền đã thu', '320000'); await click('Lưu thay đổi'); await contains('Đã ghi nhận tiền thu COD.');
    const paid = await db.payment.findUniqueOrThrow({ where: { orderId: ids[0] }, include: { settlement: true } });
    assert.equal(paid.status, 'PAID'); assert.equal(paid.settlement.reference, marker); assert.equal(paid.settlement.amount.toString(), '320000');
    assert.equal(await db.orderEvent.count({ where: { orderId: ids[0] } }), 4);
    assert.equal(await db.adminAuditEvent.count({ where: { targetId: ids[0], action: 'COD_SETTLED' } }), 1);
    await screenshot('cod-settled'); passed('Confirm → ship → deliver keeps COD pending; validated settlement records one payment and audit');
    await detail(1); await click('Hủy đơn trước khi gửi'); await fill('Lý do hủy đơn', 'Khách đề nghị hủy đơn kiểm thử'); await click('Lưu thay đổi'); await contains('Đã hủy đơn hàng');
    assert.equal((await db.order.findUniqueOrThrow({ where: { id: ids[1] } })).status, 'CANCELLED');
    assert.equal((await db.inventory.findUniqueOrThrow({ where: { variantId: variant.id } })).quantity, 41);
    assert.equal((await db.payment.findUniqueOrThrow({ where: { orderId: ids[1] } })).status, 'CANCELLED');
    passed('Cancellation saves the reason and returns inventory exactly once');
    await detail(2); await click('Xác nhận đơn');
    // Simulate another operator while the confirmation modal has version 0.
    await db.order.update({ where: { id: ids[2] }, data: { version: 1, status: 'CONFIRMED', history: { create: { status: 'CONFIRMED', version: 1, actorId: staff.id } } } });
    allowConflict = true; await click('Lưu thay đổi'); await contains('Tải lại dữ liệu');
    assert(!(await snapshot()).includes('button "Lưu thay đổi"'));
    await click('Tải lại dữ liệu'); await contains('Bắt đầu giao hàng'); allowConflict = false;
    assert.equal((await db.order.findUniqueOrThrow({ where: { id: ids[2] } })).version, 1);
    await detail(21); await contains('Chưa đủ điều kiện thanh toán'); assert.equal(await button('Xác nhận đơn').count(), 0);
    passed('A stale version requires reload; unpaid VNPay orders cannot advance');
    assert.equal(await db.mailOutbox.count({ where: { orderId: { in: ids }, status: { not: 'SENT' } } }), 0);
    assert.deepEqual(report.errors, []); assert.deepEqual(report.unexpectedResponses, []);
  } catch (e) {
    report.failure = e.message;
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); }
    throw e;
  } finally {
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    await browser?.close();
    try {
      await db.adminAuditEvent.deleteMany({ where: { targetId: { in: ids } } });
      await db.inventoryMovement.deleteMany({ where: { orderId: { in: ids } } });
      await db.orderItem.deleteMany({ where: { orderId: { in: ids } } });
      await db.payment.deleteMany({ where: { orderId: { in: ids } } });
      await db.order.deleteMany({ where: { id: { in: ids } } });
      if (variant) { await db.inventory.deleteMany({ where: { variantId: variant.id } }); await db.productVariant.delete({ where: { id: variant.id } }); }
      if (product) await db.product.delete({ where: { id: product.id } });
      if (category) await db.category.delete({ where: { id: category.id } });
      if (brand) await db.brand.delete({ where: { id: brand.id } });
      for (const user of [staff, buyer].filter(Boolean)) await db.user.delete({ where: { id: user.id } });
      report.cleaned = true;
    } finally { await db.$disconnect(); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
