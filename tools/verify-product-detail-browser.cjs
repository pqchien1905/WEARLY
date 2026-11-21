// Inspect the requested product read-only; mutate only fixtures owned by this run.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const base = 'http://localhost:8080', target = 'ade2971b-5aa4-4ad8-9596-90690c88a63c';
const output = path.resolve(__dirname, '../.tools/product-detail-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), marker = 'detail-qa-' + randomUUID(), password = randomUUID();
  const report = { passed: [], errors: [], writes: [], cleaned: false };
  let staff, fixture, browser, page;
  const pass = text => { report.passed.push(text); console.log(text); };
  try {
    const source = await db.product.findUniqueOrThrow({ where: { id: target } });
    staff = await db.user.create({ data: { name: 'Kiểm thử chi tiết sản phẩm', username: marker, email: marker + '@example.invalid', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    fixture = await db.product.create({ data: {
      name: 'Sản phẩm kiểm thử chi tiết', slug: marker, description: 'Thông tin kiểm thử riêng.',
      material: 'Cotton', style: '', categoryId: source.categoryId, brandId: source.brandId, active: false,
      images: { create: [{ url: 'assets/images/shirt.jpg', alt: 'Ảnh trước', position: 0 }, { url: 'assets/images/coat.jpg', alt: 'Ảnh sau', position: 1 }] },
      variants: { create: [0, 1, 2].map((n) => ({ sku: marker + '-' + n, size: ['S', 'M', 'L'][n], color: 'Trắng', colorHex: '#ffffff', price: String(100000 + n * 50000), active: n !== 2, inventory: { create: { quantity: [0, 3, 9][n] } } })) },
    }, include: { variants: { include: { inventory: true } } } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, reducedMotion: 'reduce' });
    const login = await context.request.post('http://localhost:3000/api/v1/auth/browser/admin/login', { headers: { Origin: base, 'X-Wearly-Browser': '1' }, data: { username: marker, password } });
    assert.equal(login.status(), 201);
    page = await context.newPage(); page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('request', r => { if (/\/api\/v1\/admin\//.test(r.url()) && !['GET', 'OPTIONS'].includes(r.method())) report.writes.push({ path: new URL(r.url()).pathname, method: r.method(), body: r.postDataJSON() }); });
    async function contains(text) {
      for (let i = 0; i < 150; i++) {
        if ((await page.locator('body').ariaSnapshot()).includes(text)) return;
        await page.waitForTimeout(100);
      }
      throw Error('Missing UI: ' + text);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      const top = await page.getByRole('dialog').count() ? 0 : 75;
      for (let i = 0; i < 70; i++) {
        const b = await node.boundingBox(), v = page.viewportSize();
        if (b && b.y >= top && b.y + b.height < v.height - 8) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, b?.y < top ? -400 : 400); await page.waitForTimeout(80);
      }
      throw Error('Control not visible: ' + node);
    }
    async function click(name) {
      const matches = page.getByRole('button', { name, exact: true });
      const node = name === 'Tổng quan' ? matches.last() : matches.first();
      await reveal(node); await node.click(); await page.waitForTimeout(180);
    }
    async function fill(label, value) {
      const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const node = page.getByRole('textbox', { name: new RegExp('^' + escaped + '(?:$| )') }).first();
      await reveal(node); await node.click(); await page.waitForTimeout(100); await node.fill(value); await page.waitForTimeout(200);
    }
    async function select(label, option) {
      const node = page.getByRole('button', { name: new RegExp(label) }).first();
      await reveal(node); await node.click(); await page.waitForTimeout(200);
      await page.getByRole('menuitem', { name: option, exact: true }).click(); await page.waitForTimeout(200);
    }
    async function route(id) {
      await page.goto(base + '/#/admin/products/' + id + '?from=/admin/products');
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await contains('Hồ sơ sản phẩm'); await page.waitForTimeout(300);
      const v = page.viewportSize(); await page.mouse.move(v.width * .8, v.height * .7); await page.mouse.wheel(0, -100000); await page.waitForTimeout(200);
    }
    async function capture(name) {
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await route(target); await capture('after-desktop');
    await click('Biến thể (5)'); await capture('variants-desktop');
    await page.setViewportSize({ width: 768, height: 1050 }); await route(target); await capture('after-tablet');
    await page.setViewportSize({ width: 375, height: 900 }); await route(target); await capture('after-mobile');
    await click('Xem ảnh 2'); await click('Phóng to ảnh sản phẩm'); await contains('Ảnh 2 / 2');
    await click('Phóng to'); await contains('150%'); await capture('mobile-gallery');
    await click('Ảnh trước'); await contains('Ảnh 1 / 2'); await click('Đóng ảnh lớn');
    pass('Real product inspected at 375/768/1440; mobile photo selection and zoom work without writes');
    assert.equal(report.writes.length, 0);
    await page.setViewportSize({ width: 1440, height: 1050 }); await route(fixture.id);
    await click('Biến thể (3)'); await select('Trạng thái biến thể', 'Đã ẩn'); await contains('Hiển thị 1/3 biến thể');
    await select('Tồn kho biến thể', 'Hết hàng'); await contains('Không có biến thể phù hợp.');
    await click('Xóa bộ lọc biến thể'); await fill('Tìm biến thể', marker + '-0'); await contains('Hiển thị 1/3 biến thể');
    await click('Sửa giá / trạng thái'); await fill('Giá bán (VND)', '125000'); await click('Lưu thay đổi'); await contains('Đã lưu biến thể.');
    const sku = fixture.variants.find(v => v.sku.endsWith('-0'));
    assert.equal(String((await db.productVariant.findUniqueOrThrow({ where: { id: sku.id } })).price), '125000');
    pass('Combined filters and empty state work; filtered price edit updates only the selected SKU');
    await click('Điều chỉnh kho'); await fill('Số lượng thay đổi', '2'); await fill('Lý do', 'Nhập kho kiểm thử giao diện'); await click('Lưu thay đổi'); await contains('Đã cập nhật tồn kho.');
    assert.equal((await db.inventory.findUniqueOrThrow({ where: { id: sku.inventory.id } })).quantity, 2);
    await route(fixture.id); await click('Bật sản phẩm'); await click('Lưu thay đổi'); await contains('Đã bật sản phẩm.');
    assert.equal((await db.product.findUniqueOrThrow({ where: { id: fixture.id } })).active, true);
    const published = await context.request.get('http://localhost:3000/api/v1/products/' + fixture.slug);
    assert.equal(published.status(), 200);
    pass('Inventory adjustment updates the actual stock and publishing exposes the product in the storefront');
    await click('Thao tác sản phẩm'); await page.getByRole('menuitem', { name: 'Xóa sản phẩm', exact: true }).click();
    await click('Xác nhận xóa'); await contains('Hãy dùng “Ẩn sản phẩm”');
    assert(await db.product.findUnique({ where: { id: fixture.id } }));
    await click('Đóng');
    pass('Detail delete action protects the product after inventory history exists');
    const allowed = new Set(['/api/v1/admin/products/' + fixture.id, ...fixture.variants.map(v => '/api/v1/admin/skus/' + v.id), ...fixture.variants.map(v => '/api/v1/admin/inventory/' + v.inventory.id + '/adjust')]);
    assert(report.writes.every(w => allowed.has(w.path)));
    assert.deepEqual(report.errors, []);
  } catch (e) {
    report.errors.push(e.stack || String(e)); process.exitCode = 1;
    if (page) {
      await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
    }
  } finally {
    await browser?.close();
    if (staff) await db.adminAuditEvent.deleteMany({ where: { actorId: staff.id } });
    if (fixture) {
      await db.inventoryMovement.deleteMany({ where: { inventory: { variant: { productId: fixture.id } } } });
      await db.inventory.deleteMany({ where: { variant: { productId: fixture.id } } });
      await db.productVariant.deleteMany({ where: { productId: fixture.id } });
      await db.product.delete({ where: { id: fixture.id } });
    }
    if (staff) await db.user.delete({ where: { id: staff.id } });
    report.cleaned = true; await db.$disconnect();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  }
})();
