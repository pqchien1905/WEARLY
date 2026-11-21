// Read-only acceptance against the actual running shop and PostgreSQL API.
// It does not replace responses, create accounts, or modify inventory/orders.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const base = 'http://localhost:8080';
const api = 'http://localhost:3000/api/v1/';
const output = path.resolve(__dirname, '../.tools/shop-acceptance');
async function json(route) {
  const response = await fetch(api + route);
  assert.equal(response.status, 200, route);
  return response.json();
}
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const errors = [], views = [];
  try {
    const first = await json('products?limit=12');
    assert(first.total > 0);
    for (const width of [1440, 768, 375]) {
      const context = await browser.newContext({ viewport: { width, height: 1000 } });
      const page = await context.newPage();
      page.setDefaultTimeout(15000);
      page.on('pageerror', e => errors.push(e.message));
      page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) errors.push(m.text()); });
      async function textIncludes(text) {
        for (let i = 0; i < 80; i++) {
          const snapshot = await page.locator('body').ariaSnapshot();
          if (snapshot.includes(text)) return snapshot;
          await page.waitForTimeout(150);
        }
        throw Error('Content missing: ' + text);
      }
      async function reveal(node) {
        await node.waitFor({ state: 'attached' });
        for (let i = 0; i < 35; i++) {
          const box = await node.boundingBox();
          if (box && box.y >= 110 && box.y + box.height <= 995) return;
          await page.mouse.move(width * .78, 700);
          await page.mouse.wheel(0, box && box.y < 120 ? -350 : 350);
          await page.waitForTimeout(120);
        }
        throw Error('Control not visible: ' + await node.getAttribute('aria-label'));
      }
      async function click(name) {
        const node = page.getByRole('button', { name, exact: true }).last();
        await reveal(node); await node.click();
      }
      async function open(route) {
        await page.goto(base + '/#' + route);
        await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
        await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      }
      async function capture(name) {
        // Allow Flutter's route/sheet transition to finish before screenshots.
        await page.waitForTimeout(400);
        await page.screenshot({ path: path.join(output, name + '-' + width + '.png') });
        fs.writeFileSync(path.join(output, name + '-' + width + '.txt'), await page.locator('body').ariaSnapshot());
        views.push(name + '-' + width);
      }
      await open('/shop');
      const initial = await textIncludes(first.total + ' thiết kế');
      assert(!/demo|Payment fixture|Coupon test/i.test(initial));
      assert(initial.includes('Tìm trong cửa hàng'));
      await capture('shop');
      if (width === 1440) {
        const seen = new Set();
        for (let n = 1; n <= Math.ceil(first.total / 12); n++) {
          const data = await json('products?limit=12&page=' + n);
          await textIncludes(data.items[0].name);
          for (const product of data.items) {
            assert(!seen.has(product.id), 'Repeated product between pages');
            seen.add(product.id);
            assert.equal(await page.getByRole('button', { name: product.name, exact: true }).count(), 1);
          }
          if (n * 12 < first.total) await click('Trang sau');
        }
        assert.equal(seen.size, first.total);
      }
      await open('/shop?category=ao&page=2');
      const field = page.getByRole('textbox', { name: /Tìm trong cửa hàng/ });
      await reveal(field); await field.click(); await field.fill('ao so mi'); await field.press('Enter');
      await page.waitForURL(url => {
        const params = new URL(url.hash.slice(1), url.origin).searchParams;
        return params.get('q') === 'ao so mi' && !params.has('page');
      });
      const results = await json('products?category=ao&q=ao%20so%20mi');
      await textIncludes(results.total ? results.items[0].name : 'Chưa có thiết kế phù hợp');
      assert(page.url().includes('category=ao'));
      await capture('search');
      await open('/shop'); await textIncludes(first.total + ' thiết kế');
      if (width < 1024) await click('Bộ lọc');
      const size = page.getByRole('checkbox', { name: '37', exact: true });
      await reveal(size); await size.click();
      if (width < 1024) await click('Xem kết quả');
      await page.waitForURL(url => url.hash.includes('size=37'));
      const shoes = await json('products?size=37');
      await textIncludes(shoes.total + ' thiết kế');
      await capture('shoe-filter');
      await open('/shop?page=999&size=37');
      await textIncludes('Trang này không còn sản phẩm');
      await click('Về trang đầu');
      await page.waitForURL(url => !url.hash.includes('page=') && url.hash.includes('size=37'));
      await textIncludes(shoes.total + ' thiết kế');
      await open('/shop'); await textIncludes(first.total + ' thiết kế');
      await click('Chọn size ' + first.items[0].name);
      await textIncludes('Chọn nhanh');
      assert(!(await page.locator('body').ariaSnapshot()).includes('demo'));
      await capture('quick-add');
      await context.close();
      console.log('PASS live shop ' + width + 'px: search, pagination, size, recovery, quick add.');
    }
    assert.deepEqual(errors, []);
  } catch (error) {
    const page = browser.contexts().flatMap(context => context.pages()).at(-1);
    if (page) {
      await page.screenshot({path: path.join(output, 'failure.png')});
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot());
    }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({ views, errors }, null, 2));
    await browser.close();
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
