// Inspect the requested real product read-only; exercise mutations on a disposable copy.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const base = process.env.ADMIN_TEST_BASE || 'http://localhost:5173';
if (!/^http:\/\/localhost:(5173|8080)$/.test(base)) throw Error('Local frontend required');
const target = 'ade2971b-5aa4-4ad8-9596-90690c88a63c';
const output = path.resolve(__dirname, '../.tools/product-editor-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), marker = 'editor-qa-' + randomUUID(), password = randomUUID();
  const report = { passed: [], errors: [], writes: [] };
  let staff, fixture, browser, page;
  const pass = text => { report.passed.push(text); console.log(text); };
  try {
    const source = await db.product.findUniqueOrThrow({ where: { id: target }, include: { variants: { include: { inventory: true } } } });
    staff = await db.user.create({ data: { name: 'Kiểm thử giao diện', username: marker, email: marker + '@example.invalid', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    fixture = await db.product.create({ data: {
      name: 'Sản phẩm kiểm thử ' + marker, slug: marker, description: source.description,
      material: source.material, style: source.style, categoryId: source.categoryId, brandId: source.brandId, active: false,
      images: { create: [
        { url: 'assets/images/shirt.jpg', alt: 'Ảnh trước', position: 0 },
        { url: 'assets/images/coat.jpg', alt: 'Ảnh sau', position: 1 },
      ] },
      variants: { create: source.variants.map((v, i) => ({ sku: marker + '-' + i, size: v.size, color: v.color,
        colorHex: v.colorHex, price: v.price, active: true, inventory: { create: { quantity: i + 3 } } })) },
    } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, reducedMotion: 'reduce' });
    const login = await context.request.post('http://localhost:3000/api/v1/auth/browser/admin/login', {
      headers: { Origin: base, 'X-Wearly-Browser': '1' }, data: { username: marker, password },
    });
    assert.equal(login.status(), 201);
    page = await context.newPage(); page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('request', r => { if (/\/api\/v1\/admin\//.test(r.url()) && !['GET', 'OPTIONS'].includes(r.method())) report.writes.push({ path: new URL(r.url()).pathname, method: r.method() }); });
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
      for (let i = 0; i < 70; i++) {
        const b = await node.boundingBox(), v = page.viewportSize();
        if (b && b.y >= 80 && b.y + b.height < v.height - 25) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, b?.y < 80 ? -400 : 400); await page.waitForTimeout(80);
      }
      throw Error('Control not visible');
    }
    const button = name => page.getByRole('button', { name, exact: true }).first();
    async function click(name) { const node = button(name); await reveal(node); await node.click(); await page.waitForTimeout(180); }
    async function fill(label, value) {
      const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const node = page.getByRole('textbox', { name: new RegExp('^' + escaped + '(?:$| )') }).first();
      await reveal(node); await node.click(); await page.waitForTimeout(100); await node.fill(value); await page.waitForTimeout(100);
    }
    async function route(id) {
      await page.goto(base + '/#/admin/products/' + id + '/edit?from=/admin/products');
      await semantics(); await contains('Xem trước sản phẩm'); await page.waitForTimeout(300);
      const viewport = page.viewportSize();
      await page.mouse.move(viewport.width * .8, viewport.height * .7);
      await page.mouse.wheel(0, -100000); await page.waitForTimeout(250);
    }
    async function capture(name) {
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await route(target); await capture('after-desktop');
    await click('Biến thể (' + source.variants.length + ')'); await capture('variants-desktop');
    await page.setViewportSize({ width: 375, height: 900 }); await route(target); await capture('after-mobile');
    await click('Trạng thái bán'); await capture('settings-mobile');
    pass('Inspected real product at desktop and mobile sizes without saving');
    await page.setViewportSize({ width: 1440, height: 1050 }); await route(fixture.id);
    const newName = 'Tên được lưu ' + marker;
    await fill('Tên sản phẩm', newName); await contains('Có thay đổi chưa lưu');
    await click('Về danh sách sản phẩm'); await contains('Rời trang khi chưa lưu?'); await click('Tiếp tục chỉnh sửa');
    await click('Lưu thông tin sản phẩm'); await contains('Đã lưu thông tin sản phẩm.');
    assert.equal((await db.product.findUniqueOrThrow({ where: { id: fixture.id } })).name, newName);
    await fill('Tên sản phẩm', 'Bản nháp sẽ bỏ'); await click('Hủy thay đổi'); await click('Bỏ thay đổi');
    assert.equal(await page.getByRole('textbox', { name: 'Tên sản phẩm', exact: true }).inputValue(), newName);
    pass('Saved draft, cancelled navigation, and discarded a later draft');
    await click('Hình ảnh (2)');
    const cover = page.getByRole('button', { name: 'Đặt làm ảnh bìa', exact: true }).last();
    await reveal(cover); await cover.click(); await click('Lưu thông tin sản phẩm');
    await contains('Đã lưu thông tin sản phẩm.');
    assert.equal((await db.productImage.findFirstOrThrow({ where: { productId: fixture.id }, orderBy: { position: 'asc' } })).url, 'assets/images/coat.jpg');
    pass('Selected and saved a new cover image');
    await click('Biến thể (' + source.variants.length + ')'); await click('Sửa giá / trạng thái');
    await fill('Giá bán (VND)', '1250000'); await click('Lưu thay đổi'); await contains('Đã lưu biến thể.');
    assert.equal(await db.productVariant.count({ where: { productId: fixture.id, price: '1250000' } }), 1);
    pass('Updated one SKU through the desktop variant table');
    await page.setViewportSize({ width: 375, height: 900 }); await route(fixture.id);
    await fill('Mô tả', 'Mô tả kiểm thử trên điện thoại.'); await click('Lưu thông tin sản phẩm');
    await contains('Đã lưu thông tin sản phẩm.');
    assert.equal((await db.product.findUniqueOrThrow({ where: { id: fixture.id } })).description, 'Mô tả kiểm thử trên điện thoại.');
    pass('Saved product details on mobile');
    assert(report.writes.every(w => !w.path.includes(target)));
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
    await db.$disconnect();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  }
})();
