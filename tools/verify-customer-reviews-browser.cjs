// Local browser acceptance against the customer's existing review history.
// Saves an unchanged review and cancels deletion; never deletes customer content.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession, customerEmail } = require('./customer-account-session.cjs');
const output = path.resolve(__dirname, '../.tools/reviews-redesign');
const origin = process.argv[2] || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const session = await customerSession(customerEmail());
  const report = { origin, passed: [], errors: [], requests: [] };
  let browser, page;
  try {
    const before = await session.request('users/me/reviews');
    assert(before.items.length > 0);
    assert(before.items.every(r => r.product?.image));
    browser = await chromium.launch({
      executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'],
    });
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1080 }, reducedMotion: 'reduce', hasTouch: true,
    });
    await context.addCookies([session.cookie]);
    page = await context.newPage();
    page.setDefaultTimeout(15000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => {
      if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text());
    });
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
    async function click(name) {
      const node = page.getByRole('button', { name, exact: true }).first();
      await reveal(node); await node.click();
    }
    async function capture(name) {
      await page.mouse.move(8, page.viewportSize().height - 16); await page.waitForTimeout(200);
      await page.screenshot({ path: path.join(output, name + '.png') });
      fs.writeFileSync(path.join(output, name + '.txt'), await page.locator('body').ariaSnapshot());
    }
    async function history() {
      await page.evaluate(() => { location.hash = '/account/reviews'; });
      await includes(`${before.total} đánh giá`); await top();
    }
    await page.goto(origin + '/#/account/reviews'); await semantics();
    await includes(`${before.total} đánh giá`);
    for (const item of before.items) await includes(item.product.name);
    for (const width of [2560, 1440, 768, 375]) {
      await page.setViewportSize({ width, height: 1080 }); await history();
      assert.equal(await page.getByRole('heading', { level: 1 }).count(), 1);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      const snapshot = await page.locator('body').ariaSnapshot();
      assert(!/dữ liệu mẫu/i.test(snapshot));
      if (width >= 1440) {
        for (const title of ['Sản phẩm', 'Đánh giá', 'Nội dung', 'Thao tác']) await includes(title);
      }
      await capture(`reviews-${width}`);
      if (width === 375) {
        await reveal(page.getByRole('button', { name: 'Sửa đánh giá', exact: true }).first());
        await capture('reviews-mobile-actions');
        await click('Sửa đánh giá'); await includes('Sửa đánh giá của bạn');
        await capture('review-editor-mobile'); await click('Đóng');
      }
      report.passed.push(`Review history and actions fit ${width}px`);
    }
    await page.setViewportSize({ width: 1440, height: 1080 }); await history();
    await click('Sửa đánh giá'); await includes('Sửa đánh giá của bạn');
    const field = page.getByRole('textbox', { name: 'Nội dung đánh giá', exact: false });
    await field.click(); assert.equal(await field.inputValue(), before.items[0].comment);
    await capture('review-editor');
    await field.fill(before.items[0].comment); await click('Lưu đánh giá');
    await includes(`${before.total} đánh giá`);
    const after = await session.request('users/me/reviews');
    assert.deepEqual(after.items.map(({ id, comment, rating }) => ({ id, comment, rating })),
      before.items.map(({ id, comment, rating }) => ({ id, comment, rating })));
    assert.notEqual(after.items[0].updatedAt, before.items[0].updatedAt);
    report.passed.push('Existing review saves through the real API and preserves its rating and content');
    await page.reload(); await semantics(); await includes(`${before.total} đánh giá`);
    await click('Tải lại'); await includes(before.items[0].product.name);
    report.passed.push('Refresh and browser reload restore the persisted review history');
    await click('Xóa đánh giá'); await includes('Xóa đánh giá?');
    await capture('review-delete-confirmation'); await click('Đóng');
    assert.equal((await session.request('users/me/reviews')).total, before.total);
    report.passed.push('Delete confirmation can be cancelled without changing customer content');
    await click('Xem sản phẩm'); await includes(before.items[0].product.name);
    assert(new URL(page.url()).hash.includes('/products/' + before.items[0].product.slug));
    report.passed.push('Product link opens the matching catalog product');
    await history(); await capture('reviews-final');
    assert.deepEqual(report.errors, []);
    // Customer and admin sessions are isolated; this browser has no staff cookie.
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
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2));
    await browser?.close(); await session.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
