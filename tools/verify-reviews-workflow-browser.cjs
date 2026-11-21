// Local API acceptance. All writes belong to disposable fixtures and are cleaned.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, '.tools/reviews-workflow');
const origin = process.env.REVIEWS_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const db = localDatabase(), productIds = [], variantIds = [];
  const email = `reviews-${randomUUID().slice(0, 8)}@example.invalid`;
  const report = { origin, passed: [], errors: [] };
  let browser, page, session, userId, orderId, release;
  let writes = 0;
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Khách kiểm thử đánh giá', email, password: randomUUID() + '-Aa1' }),
    });
    assert.equal(registered.status, 201); userId = (await registered.json()).user.id;
    const source = await db.product.findFirstOrThrow({ where: { active: true }, include: { images: { take: 1 } } });
    for (let i = 0; i < 7; i++) {
      const product = await db.product.create({ data: {
        slug: `reviews-qa-${randomUUID()}`, name: `Áo cotton kiểm thử ${i + 1}`, active: i < 6,
        description: 'Disposable local acceptance fixture', material: 'Cotton', style: 'QA',
        categoryId: source.categoryId, brandId: source.brandId,
        images: { create: { url: source.images[0]?.url || 'assets/images/shirt.jpg', alt: 'Áo cotton', position: 0 } },
        variants: { create: { sku: `REVIEWS-QA-${randomUUID()}`, size: 'M', color: 'Trắng', colorHex: '#FFFFFF', price: '490000' } },
      }, include: { variants: true } });
      productIds.push(product.id); variantIds.push(product.variants[0].id);
    }
    orderId = (await db.order.create({ data: {
      userId, idempotencyKey: randomUUID(), requestHash: 'reviews-browser-fixture', status: 'DELIVERED',
      addressSnapshot: {}, subtotal: '3430000', shipping: '0', total: '3430000',
      items: { create: variantIds.map((variantId, i) => ({
        variantId, sku: `qa-${i}`, slug: `qa-${i}`, name: `Áo cotton kiểm thử ${i + 1}`,
        size: 'M', color: 'Trắng', image: '', unitPrice: '490000', quantity: 1,
      })) },
    } })).id;
    await db.review.createMany({ data: productIds.map((productId, i) => ({
      userId, productId, rating: i % 5 + 1,
      comment: i === 5 ? 'Linen mềm và thoáng, đường may đẹp.' : `Chất vải mềm, vừa vặn. Trải nghiệm số ${i + 1}.`,
      createdAt: new Date(Date.now() - (i + 1) * 86400000),
      updatedAt: new Date(Date.now() - (i + 1) * 86400000),
    })) });
    session = await customerSession(email);
    fs.writeFileSync(path.join(output, 'fixture.json'), JSON.stringify({userId,orderId,productIds,variantIds}));
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce' });
    await context.addCookies([session.cookie]);
    page = await context.newPage(); page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('request', r => { if (['PATCH','DELETE'].includes(r.method()) && /\/reviews\/me$/.test(r.url())) writes++; });
    const button = name => page.getByRole('button', { name, exact: true });
    const body = () => page.locator('body').ariaSnapshot();
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function includes(value) {
      for (let i=0;i<150;i++) { if ((await body()).includes(value)) return; await page.waitForTimeout(100); }
      throw Error('Missing content: ' + value);
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i=0;i<50;i++) {
        const b = await node.boundingBox(), h = page.viewportSize().height;
        const inset = page.viewportSize().width < 600 ? 235 : 180;
        if (b && b.y >= inset && b.y + b.height < h - 12) return;
        await page.mouse.move(page.viewportSize().width * .8, h * .7);
        await page.mouse.wheel(0, b ? b.y - (inset + h - 12 - b.height) / 2 : 250);
        await page.waitForTimeout(90);
      }
      throw Error('Cannot reveal control');
    }
    async function click(name) { const n = button(name); await reveal(n); await n.click(); await page.waitForTimeout(150); }
    async function search(value) {
      const n = page.getByRole('textbox', { name: /Tìm đánh giá/ });
      await reveal(n); await n.click(); await n.fill(value); await page.waitForTimeout(500);
    }
    async function chip(name) {
      const n = page.getByRole('checkbox', { name, exact: true });
      await reveal(n); await n.click(); await page.waitForTimeout(200);
    }
    async function top() {
      await page.mouse.move(page.viewportSize().width * .8, page.viewportSize().height * .7);
      await page.mouse.wheel(0, -100000); await page.waitForTimeout(200);
    }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 12); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await body());
    }
    const dialog = () => page.getByRole('alertdialog');
    async function dialogClick(name) { await dialog().getByRole('button', { name, exact: true }).click(); await page.waitForTimeout(150); }
    async function editComment(value) {
      const n = dialog().getByRole('textbox', { name: /Nội dung đánh giá/ });
      await n.click(); await n.fill(value); await page.waitForTimeout(120);
    }
    await page.goto(origin + '/#/account/reviews'); await semantics(); await includes('7 đánh giá');
    await capture('desktop');
    await search('LINEN'); await includes('1 đánh giá phù hợp'); await includes('Áo cotton kiểm thử 6');
    await chip('5 sao'); await includes('Không có đánh giá phù hợp');
    assert(!(await body()).includes('Bạn chưa viết đánh giá nào'));
    await click('Bỏ bộ lọc'); await includes('7 đánh giá');
    report.passed.push('Search spans all server pages; rating combines with search; reset restores all reviews');

    await click('Trang sau'); await includes('Trang 2 / 2');
    await click('Sửa đánh giá'); assert(await dialog().getByRole('button', { name: 'Lưu đánh giá', exact: true }).isDisabled());
    await dialogClick('Đóng'); await includes('Trang 2 / 2'); assert.equal(writes, 0);
    await click('Sửa đánh giá'); await editComment('Bản nháp chưa lưu');
    await dialogClick('Đóng'); await includes('Bỏ thay đổi chưa lưu?');
    await dialogClick('Tiếp tục viết');
    await dialogClick('Đóng'); await dialogClick('Bỏ thay đổi'); assert.equal(writes, 0);
    report.passed.push('Closing dialogs preserves page two; dirty drafts require discard confirmation');

    await click('Sửa đánh giá'); await editComment('Linen đã chỉnh sửa, mặc rất thoải mái.');
    await dialog().getByRole('button', { name: 'Chọn 5 sao', exact: true }).click();
    const writeRoute = '**/products/' + productIds[5] + '/reviews/me';
    await page.route(writeRoute, async route => {
      if (route.request().method() !== 'PATCH') return route.continue();
      await new Promise(resolve => { release = resolve; }); await route.continue();
    });
    await dialogClick('Lưu đánh giá'); await includes('Đang lưu đánh giá…');
    assert(await dialog().getByRole('button', { name: 'Đóng', exact: true }).isDisabled());
    assert.equal(writes, 1); release(); release = null;
    await includes('Đã lưu thay đổi đánh giá.'); await includes('Trang 2 / 2');
    await page.unroute(writeRoute);
    const saved = await session.request(`products/${productIds[5]}/reviews/me`);
    assert.equal(saved.review.rating, 5); assert.equal(saved.review.comment, 'Linen đã chỉnh sửa, mặc rất thoải mái.');
    await page.reload(); await semantics(); await search('Linen đã chỉnh sửa'); await includes('1 đánh giá phù hợp');
    report.passed.push('Single guarded PATCH persists rating/comment through browser reload; saving preserves page');

    const historyRoute = '**/users/me/reviews?*';
    await page.route(historyRoute, async route => {
      await new Promise(resolve => { release = resolve; });
      await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ code: 'TEMPORARY', message: 'Kết nối tạm gián đoạn.' }) })
        .catch(error => report.errors.push(String(error)));
    });
    await click('Tải lại'); await includes('Đang tải lại…'); await includes('Linen đã chỉnh sửa');
    release(); release = null; await includes('Chưa cập nhật được danh sách');
    await includes('Linen đã chỉnh sửa');
    assert(!await button('Sửa đánh giá').isEnabled());
    await capture('refresh-error');
    await page.unroute(historyRoute); await click('Thử lại'); await includes('1 đánh giá phù hợp');
    assert(await button('Sửa đánh giá').isEnabled());
    report.passed.push('Delayed/failed refresh retains rows and disables stale mutations; retry restores actions');

    for (const [width,height] of [[320,900],[375,900],[768,1024],[1440,1080],[2560,1200],[844,390]]) {
      await page.setViewportSize({width,height}); await top(); await includes('Tìm đánh giá');
      await capture(`width-${width}`);
      if (height > 600) {
        await click('Sửa đánh giá'); await capture(`editor-${width}`); await dialogClick('Đóng');
        await click('Xóa đánh giá'); await capture(`delete-${width}`); await dialogClick('Đóng');
      }
    }
    report.passed.push('Responsive list and both dialogs render at 320/375/768/1440/2560; landscape page checked');

    await page.setViewportSize({ width:1440,height:1080 }); await click('Đặt lại'); await includes('7 đánh giá');
    await click('Trang sau'); await includes('Trang 2 / 2');
    const deletes = button('Xóa đánh giá'); await reveal(deletes.last()); await deletes.last().click();
    await includes('Sản phẩm không còn mở bán'); await dialogClick('Xóa đánh giá');
    await includes('Đã xóa đánh giá.'); await includes('6 đánh giá'); await includes('Trang 2 / 2');
    await click('Xóa đánh giá'); await dialogClick('Xóa đánh giá');
    await includes('5 đánh giá'); assert(!(await body()).includes('Trang 2 / 2')); assert.equal(writes, 3);
    assert.equal((await session.request('users/me/reviews')).total, 5);
    report.passed.push('Hidden review is removable; deleting the final row automatically returns to the valid page');
    assert.deepEqual(report.errors, []);
    fs.writeFileSync(path.join(output,'report.json'), JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
  } catch (error) {
    report.failure = String(error);
    if (page) { await page.screenshot({ path:path.join(output,'failure.png') }).catch(()=>{}); fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>'')); }
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)); throw error;
  } finally {
    release?.(); await browser?.close(); await session?.close();
    if (userId) await db.review.deleteMany({where:{userId}});
    if (orderId) { await db.orderItem.deleteMany({where:{orderId}}); await db.order.deleteMany({where:{id:orderId}}); }
    if (userId) await db.user.deleteMany({where:{id:userId}});
    await db.productVariant.deleteMany({where:{id:{in:variantIds}}});
    await db.product.deleteMany({where:{id:{in:productIds}}});
    await db.$disconnect();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
