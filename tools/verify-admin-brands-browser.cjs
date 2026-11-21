// Chrome + API + PostgreSQL acceptance. Only this run's isolated fixtures change.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(base)) throw Error('Local frontend required');
const output = path.resolve(__dirname, '../.tools/brands-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), marker = 'brands-qa-' + randomUUID().slice(0, 8), password = randomUUID() + '-Aa1';
  const report = { passed: [], errors: [], unexpectedResponses: [] }, brandIds = [];
  let browser, page, staff, category, product, allowConflict = false;
  const createdSlug = marker + '-ui', name = 'Đầm mùa thu ' + marker, renamed = 'Bộ sưu tập mới ' + marker;
  try {
    staff = await db.user.create({ data: { username: marker, email: marker + '@example.invalid', name: 'Quản trị kiểm thử thương hiệu', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    for (let i = 0; i < 23; i++) brandIds.push((await db.brand.create({ data: { slug: marker + '-' + i, name: 'Áo Đầm ' + String(i).padStart(2, '0') + ' ' + marker } })).id);
    category = await db.category.create({ data: { name: marker, slug: marker } });
    product = await db.product.create({ data: {
      name: 'Sản phẩm kiểm thử ' + marker, slug: marker, description: 'Fixture kiểm thử', material: 'Cotton', style: 'Casual', brandId: brandIds[0], categoryId: category.id,
      images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo' } },
      variants: { create: { sku: marker, color: 'Trắng', colorHex: '#ffffff', size: 'M', price: '300000', inventory: { create: { quantity: 7 } } } },
    } });
    const stockBefore = await db.inventory.findFirstOrThrow({ where: { variant: { productId: product.id } } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, timezoneId: 'Asia/Bangkok', reducedMotion: 'reduce' });
    page = await context.newPage(); page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (/\/api\/v1\/admin\//.test(r.url()) && r.status() >= 400 && !(allowConflict && r.status() === 409)) report.unexpectedResponses.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    const snapshot = () => page.locator('body').ariaSnapshot();
    const button = name => page.getByRole('button', { name, exact: typeof name === 'string' });
    const passed = text => { report.passed.push(text); console.log(text); };
    async function contains(text) {
      for (let i = 0; i < 150; i++) { if ((await snapshot()).includes(text)) return; await page.waitForTimeout(100); }
      throw Error('Missing UI: ' + text);
    }
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 70; i++) {
        const box = await node.boundingBox(), v = page.viewportSize();
        if (box && box.y >= 85 && box.y + box.height < v.height - 20) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, box?.y < 85 ? -500 : 500); await page.waitForTimeout(80);
      }
      throw Error('Control outside viewport: ' + node);
    }
    async function click(name) { const node = name === 'Lưu thông tin sản phẩm' ? button(name).first() : button(name); await reveal(node); await node.click(); await page.waitForTimeout(250); }
    async function fill(label, value) {
      const node = page.getByRole('textbox', { name: new RegExp('^' + label) });
      await reveal(node); await node.click(); await page.waitForTimeout(100); await node.fill(value); await page.waitForTimeout(100);
    }
    async function select(label, option) {
      const node = button(new RegExp('^' + label + '\\s')).last(); await reveal(node); await node.click();
      await page.getByRole('menu').last().hover(); await page.mouse.wheel(0, -10000); await page.waitForTimeout(200);
      await page.getByRole('menuitem', { name: option, exact: true }).click(); await page.waitForTimeout(250);
    }
    async function route(target, text) { await page.evaluate(v => location.hash = '#' + v, target); await page.waitForTimeout(300); await contains(text); }
    async function capture(name) {
      await page.mouse.move(page.viewportSize().width * .75, 500); await page.mouse.wheel(0, -20000); await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(output, name + '.png') }); fs.writeFileSync(path.join(output, name + '.txt'), await snapshot());
    }
    await page.goto(base + '/#/admin/brands'); await semantics(); await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập', marker); await fill('Mật khẩu', password); await click('Đăng nhập quản trị');
    await contains('Tìm kiếm thương hiệu'); await fill('Tìm kiếm thương hiệu', marker); await click('Tìm kiếm');
    await contains('23 thương hiệu phù hợp bộ lọc'); await click('Trang sau'); await contains('Trang 2/2');
    await page.reload(); await semantics(); await contains('Trang 2/2');
    await select('Sắp xếp', 'Nhiều sản phẩm nhất'); await select('Phạm vi sản phẩm', 'Có ở cửa hàng'); await contains('1 thương hiệu phù hợp bộ lọc');
    await select('Phạm vi sản phẩm', 'Chưa có sản phẩm'); await contains('22 thương hiệu phù hợp bộ lọc');
    await select('Phạm vi sản phẩm', 'Tất cả thương hiệu');
    await fill('Tìm kiếm thương hiệu', 'ao dam 00 ' + marker); await click('Tìm kiếm'); await contains('1 thương hiệu phù hợp bộ lọc');
    await capture('desktop'); passed('Real login; Vietnamese search, coverage filters, sorting, pagination and reload retain URL');
    await click('Thêm thương hiệu'); await click('Lưu thay đổi'); await contains('Vui lòng nhập');
    await fill('Tên hiển thị', name);
    const slugInput = page.getByRole('textbox', { name: /^Đường dẫn/ });
    await slugInput.click(); await page.waitForTimeout(100);
    assert.equal(await slugInput.inputValue(), 'dam-mua-thu-' + marker);
    await fill('Đường dẫn', marker + '-0'); allowConflict = true; await click('Lưu thay đổi');
    await contains('Đường dẫn đã được sử dụng.');
    await fill('Đường dẫn', createdSlug); await click('Lưu thay đổi'); await contains('Đã thêm thương hiệu.'); allowConflict = false;
    const created = await db.brand.findUniqueOrThrow({ where: { slug: createdSlug } }); brandIds.push(created.id);
    assert.equal(created.name, name);
    await route('/admin/brands/' + created.id, 'Chi tiết thương hiệu');
    await contains('0 sản phẩm thuộc thương hiệu'); await click('Đổi tên thương hiệu'); await fill('Tên hiển thị', renamed); await click('Lưu thay đổi');
    await contains('Đã cập nhật thương hiệu.'); assert.equal((await db.brand.findUniqueOrThrow({ where: { id: created.id } })).name, renamed);
    assert.equal((await db.brand.findUniqueOrThrow({ where: { id: created.id } })).slug, createdSlug);
    passed('UI creation, Vietnamese auto slug, inline required/duplicate validation and rename persist in database');
    // The new brand is selectable through the existing product editor.
    await route('/admin/products/' + product.id + '/edit', 'Chỉnh sửa sản phẩm');
    await contains('Tên sản phẩm'); await capture('product-editor');
    await select('Thương hiệu', renamed); await click('Lưu thông tin sản phẩm'); await contains('Đã lưu thông tin sản phẩm.');
    assert.equal((await db.product.findUniqueOrThrow({ where: { id: product.id } })).brandId, created.id);
    await route('/admin/brands/' + created.id, '1 sản phẩm thuộc thương hiệu');
    await contains(product.name);
    await capture('detail-1440');
    await click('Xem tồn kho'); await contains('1 SKU phù hợp bộ lọc'); await contains(renamed);
    assert.equal(new URL(page.url().split('#')[1], base).searchParams.get('brandId'), created.id);
    assert.deepEqual(await db.inventory.findUnique({ where: { id: stockBefore.id } }), stockBefore);
    await route('/admin/brands/' + created.id, '1 sản phẩm thuộc thương hiệu');
    await click('Xem sản phẩm'); await contains(product.name);
    await route('/admin/brands/' + created.id, 'Chi tiết thương hiệu');
    await click('Xem tại cửa hàng'); await contains(renamed); await contains(product.name); await capture('storefront');
    passed('New brand selectable in product editor; brand/product/inventory/public storefront links agree, stock unchanged');
    for (const width of [768, 375]) {
      await page.setViewportSize({ width, height: 1000 });
      await route('/admin/brands?q=' + createdSlug, '1 thương hiệu phù hợp bộ lọc'); await capture('brands-' + width);
      await click('Xem chi tiết'); await contains('Chi tiết thương hiệu'); await capture('detail-' + width);
      await click('Đổi tên thương hiệu'); await capture('dialog-' + width); await click('Đóng');
    }
    // Simulate another administrator saving after the dialog opened.
    await click('Đổi tên thương hiệu');
    await db.brand.update({ where: { id: created.id }, data: { name: renamed + ' khác', updatedAt: new Date(Date.now() + 1000) } });
    await fill('Tên hiển thị', 'Không ghi đè'); allowConflict = true; await click('Lưu thay đổi');
    await contains('Tải lại dữ liệu'); await click('Tải lại dữ liệu'); allowConflict = false; await contains(renamed + ' khác');
    assert.equal((await db.brand.findUniqueOrThrow({ where: { id: created.id } })).name, renamed + ' khác');
    passed('375/768/1440 list/detail/dialog; stale edit rejected, reload reads winning change');
    // Populated brands explain protection and never send a destructive request.
    await click('Xóa thương hiệu'); await contains('Thương hiệu đang có sản phẩm'); await click('Đóng');
    assert.ok(await db.brand.findUnique({ where: { id: created.id } }));
    // The original brand is now empty after reassignment. Deletion preserves the return filter.
    const emptyId = brandIds[0];
    await route('/admin/brands/' + emptyId + '?from=' + encodeURIComponent('/admin/brands?q=' + marker + '&coverage=empty'), 'Chi tiết thương hiệu');
    await click('Xóa thương hiệu'); await contains('Xóa vĩnh viễn'); await click('Đóng');
    assert.ok(await db.brand.findUnique({ where: { id: emptyId } }));
    await click('Xóa thương hiệu'); await click('Xác nhận xóa'); await contains('Quản lý thương hiệu');
    await contains('Đã xóa thương hiệu.');
    assert.equal(await db.brand.findUnique({ where: { id: emptyId } }), null);
    assert.equal(new URL(page.url().split('#')[1], base).searchParams.get('coverage'), 'empty');
    assert.equal(await db.adminAuditEvent.count({ where: { targetId: emptyId, action: 'BRAND_DELETED' } }), 1);
    // A product attached after confirmation opens must be protected by the server as well.
    const racedId = brandIds[1];
    await route('/admin/brands/' + racedId, 'Chi tiết thương hiệu');
    await click('Xóa thương hiệu');
    await db.product.update({ where: { id: product.id }, data: { brandId: racedId } });
    allowConflict = true; await click('Xác nhận xóa');
    await contains('Thương hiệu đang có sản phẩm.'); await click('Tải lại dữ liệu'); allowConflict = false;
    await contains('1 sản phẩm thuộc thương hiệu');
    assert.ok(await db.brand.findUnique({ where: { id: racedId } }));
    assert.equal(await db.adminAuditEvent.count({ where: { targetId: racedId, action: 'BRAND_DELETED' } }), 0);
    passed('Mobile deletion cancellation/confirmation, exact audit and retained filters; populated and concurrently populated brands protected');
    assert.deepEqual(report.errors, []); assert.deepEqual(report.unexpectedResponses, []);
  } catch (e) {
    report.failure = e.message;
    if (page) { await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {}); fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => '')); }
    throw e;
  } finally {
    await browser?.close();
    try {
      if (staff) await db.adminAuditEvent.deleteMany({ where: { actorId: staff.id } });
      if (product) {
        await db.inventory.deleteMany({ where: { variant: { productId: product.id } } });
        await db.productVariant.deleteMany({ where: { productId: product.id } });
        await db.product.delete({ where: { id: product.id } });
      }
      await db.brand.deleteMany({ where: { OR: [{ id: { in: brandIds } }, { slug: createdSlug }] } });
      if (category) await db.category.delete({ where: { id: category.id } });
      if (staff) await db.user.delete({ where: { id: staff.id } });
      report.cleaned = true;
    } finally { await db.$disconnect(); fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2)); }
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
