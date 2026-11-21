// All writes target disposable local fixtures created in this run.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const argon2 = require('../backend/node_modules/argon2');
const { localDatabase } = require('./seed-customer-account.cjs');
const base = 'http://localhost:8080';
const output = path.resolve(__dirname, '../.tools/product-deletion-acceptance');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), marker = 'delete-qa-' + randomUUID(), password = randomUUID();
  const fixtures = [], report = { passed: [], errors: [], writes: [], cleaned: false };
  let staff, browser, page;
  const pass = value => { report.passed.push(value); console.log(value); };
  try {
    const category = await db.category.findFirstOrThrow(), brand = await db.brand.findFirstOrThrow();
    staff = await db.user.create({ data: { name: 'Kiểm thử xóa sản phẩm', username: marker, email: marker + '@example.invalid', role: 'ADMIN', passwordHash: await argon2.hash(password) } });
    for (let i = 0; i < 2; i++) {
      fixtures.push(await db.product.create({ data: {
        name: i ? 'Sản phẩm kiểm thử có lịch sử kho' : 'Sản phẩm kiểm thử xóa', slug: marker + '-' + i,
        description: '', material: '', style: '', categoryId: category.id, brandId: brand.id, active: false,
        images: { create: [{ url: 'assets/images/shirt.jpg', alt: 'Ảnh kiểm thử', position: 0 }] },
        variants: { create: { sku: marker + '-' + i, size: 'M', color: 'Trắng', colorHex: '#ffffff', price: '100000', inventory: { create: { quantity: 3 } } } },
      }, include: { variants: { include: { inventory: true } } } }));
    }
    await db.inventoryMovement.create({ data: { inventoryId: fixtures[1].variants[0].inventory.id, delta: 3, reason: 'Fixture stock history' } });
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, reducedMotion: 'reduce' });
    const login = await context.request.post('http://localhost:3000/api/v1/auth/browser/admin/login', { headers: { Origin: base, 'X-Wearly-Browser': '1' }, data: { username: marker, password } });
    assert.equal(login.status(), 201);
    page = await context.newPage(); page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('request', r => { if (/\/api\/v1\/admin\//.test(r.url()) && !['GET', 'OPTIONS'].includes(r.method())) report.writes.push({ path: new URL(r.url()).pathname, method: r.method() }); });
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
        const box = await node.boundingBox(), v = page.viewportSize();
        if (box && box.y >= 80 && box.y + box.height < v.height - 20) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, box?.y < 80 ? -400 : 400); await page.waitForTimeout(80);
      }
      throw Error('Control outside viewport');
    }
    async function click(name) {
      const node = page.getByRole(name === 'Xóa sản phẩm' ? 'menuitem' : 'button', { name, exact: true });
      if (name !== 'Xóa sản phẩm') await reveal(node);
      await node.click(); await page.waitForTimeout(180);
    }
    async function route(fixture) {
      await page.goto(base + '/#/admin/products?q=' + fixture.slug);
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await contains(fixture.name);
    }
    async function capture(name) {
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    await route(fixtures[0]);
    await click('Thao tác sản phẩm'); await capture('desktop-menu');
    await click('Xóa sản phẩm'); await capture('desktop-confirm'); await click('Đóng');
    assert(await db.product.findUnique({ where: { id: fixtures[0].id } }));
    assert.equal(report.writes.length, 0);
    pass('Cancel confirmation leaves the product untouched');
    await click('Thao tác sản phẩm'); await click('Xóa sản phẩm'); await click('Xác nhận xóa');
    await contains('Đã xóa sản phẩm.'); await contains('Không có sản phẩm phù hợp');
    assert.equal(await db.product.findUnique({ where: { id: fixtures[0].id } }), null);
    assert.equal(await db.productVariant.count({ where: { productId: fixtures[0].id } }), 0);
    assert.equal(await db.adminAuditEvent.count({ where: { action: 'PRODUCT_DELETED', targetId: fixtures[0].id } }), 1);
    pass('Confirmed deletion removes the row and its variants, with one audit event');
    await page.setViewportSize({ width: 375, height: 900 }); await route(fixtures[1]);
    await click('Thao tác sản phẩm'); await click('Xóa sản phẩm'); await capture('mobile-confirm');
    await click('Xác nhận xóa'); await contains('Hãy dùng “Ẩn sản phẩm”'); await capture('mobile-protected');
    assert(await db.product.findUnique({ where: { id: fixtures[1].id } }));
    assert.equal(await db.inventoryMovement.count({ where: { inventoryId: fixtures[1].variants[0].inventory.id } }), 1);
    pass('Mobile deletion protects stock history and shows the hide-product guidance');
    assert(report.writes.every(w => w.method === 'DELETE' && fixtures.some(f => w.path === '/api/v1/admin/products/' + f.id)));
    assert.deepEqual(report.errors, []);
  } catch (e) {
    report.errors.push(e.stack || String(e)); process.exitCode = 1;
    if (page) await captureFailure();
  } finally {
    await browser?.close();
    if (staff) await db.adminAuditEvent.deleteMany({ where: { actorId: staff.id } });
    const ids = fixtures.map(f => f.id);
    await db.inventoryMovement.deleteMany({ where: { inventory: { variant: { productId: { in: ids } } } } });
    await db.inventory.deleteMany({ where: { variant: { productId: { in: ids } } } });
    await db.productVariant.deleteMany({ where: { productId: { in: ids } } });
    await db.product.deleteMany({ where: { id: { in: ids } } });
    if (staff) await db.user.delete({ where: { id: staff.id } });
    report.cleaned = true;
    await db.$disconnect();
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  }
  async function captureFailure() {
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot().catch(() => ''));
  }
})();
