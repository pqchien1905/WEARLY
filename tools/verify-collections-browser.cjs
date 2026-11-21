// Read-only acceptance against the running Flutter app and PostgreSQL API.
// No intercepted responses, test products, accounts, or inventory mutations.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const base = 'http://localhost:8080', api = 'http://localhost:3000/api/v1/';
const output = path.resolve(__dirname, '../.tools/collections-acceptance');
async function json(route) {
  const response = await fetch(api + route, { signal: AbortSignal.timeout(10000) });
  assert.equal(response.status, 200, route);
  return response.json();
}
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const collections = await json('collections?limit=100'), seen = new Set(), summaries = [];
  assert(collections.total > 0);
  assert.equal(collections.items.length, collections.total);
  const catalog = await json('products?limit=100');
  for (const collection of collections.items) {
    const ids = [];
    for (let page = 1; ; page++) {
      const detail = await json('collections/' + collection.slug + '?limit=12&page=' + page);
      assert.equal(detail.total, collection.productCount);
      for (const product of detail.items) {
        assert(!seen.has(product.id), 'Repeated product across collections or pages: ' + product.slug);
        assert(product.images.length > 0);
        assert.equal(product.style, collection.style);
        seen.add(product.id); ids.push(product.id);
      }
      if (ids.length >= detail.total) break;
      assert(detail.items.length > 0, 'Premature end of pagination');
    }
    assert(ids.includes(collection.cover.productId), 'Cover must belong to the collection');
    assert.equal(ids.length, collection.productCount);
    summaries.push({ slug: collection.slug, style: collection.style, products: ids.length, cover: collection.cover.url });
  }
  assert.equal(seen.size, catalog.total, 'Every current product belongs to exactly one collection');
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const errors = [], views = [];
  try {
    for (const width of [1440, 768, 375]) {
      const context = await browser.newContext({ viewport: { width, height: 1000 } });
      const page = await context.newPage();
      page.setDefaultTimeout(15000);
      page.on('pageerror', e => errors.push(e.message));
      page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) errors.push(m.text()); });
      page.on('response', r => { if (r.status() >= 400 && /catalog\/images\/|assets\/.*\.(?:png|jpg|webp)/.test(r.url())) errors.push('Image HTTP ' + r.status() + ': ' + r.url()); });
      async function includes(text) {
        for (let i = 0; i < 80; i++) {
          const snapshot = await page.locator('body').ariaSnapshot();
          if (snapshot.includes(text)) return snapshot;
          await page.waitForTimeout(150);
        }
        throw Error('Missing content: ' + text);
      }
      async function reveal(node) {
        await node.waitFor({ state: 'attached' });
        for (let i = 0; i < 40; i++) {
          const box = await node.boundingBox();
          if (box && box.y >= 110 && box.y + box.height <= 995) return;
          await page.mouse.move(width * .78, 700);
          await page.mouse.wheel(0, box && box.y < 120 ? -350 : 350);
          await page.waitForTimeout(100);
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
        await page.waitForTimeout(450);
        await page.screenshot({ path: path.join(output, name + '-' + width + '.png') });
        const snapshot = await page.locator('body').ariaSnapshot();
        assert(!snapshot.includes('Ảnh chưa có'), 'Image fallback visible');
        fs.writeFileSync(path.join(output, name + '-' + width + '.txt'), snapshot);
        views.push(name + '-' + width);
      }
      await open('/collections');
      const initial = await includes(collections.total + ' bộ sưu tập');
      for (const collection of collections.items) assert(initial.includes(collection.title));
      assert(!/demo|fixture/i.test(initial));
      await capture('index');
      const collection = collections.items.find(c => c.productCount > 12) ?? collections.items[0];
      await click('Khám phá ' + collection.style.toLowerCase());
      await page.waitForURL(u => u.hash === '#/collections/' + collection.slug);
      await includes(collection.productCount + ' thiết kế trong bộ sưu tập');
      await capture('detail');
      const detail = await json('collections/' + collection.slug + '?limit=12');
      for (const p of detail.items) assert.equal(await page.getByRole('button', { name: p.name, exact: true }).count(), 1);
      if (collection.productCount > 12) {
        await click('Trang sau');
        await page.waitForURL(u => u.hash.includes('page=2'));
        const next = await json('collections/' + collection.slug + '?limit=12&page=2');
        await includes(next.items[0].name);
        for (const p of detail.items) assert.equal(await page.getByRole('button', { name: p.name, exact: true }).count(), 0);
        await capture('page-two');
        await click('Trang trước');
        await includes(detail.items[0].name);
      }
      await click('Chọn size ' + detail.items[0].name);
      await includes('Chọn nhanh');
      await capture('quick-add');
      await open('/collections/' + collection.slug + '?page=999&sort=price-asc&stock=true');
      await includes('Trang này không còn sản phẩm');
      await click('Về trang đầu');
      await page.waitForURL(u => !u.hash.includes('page=') && u.hash.includes('stock=true') && u.hash.includes('sort=price-asc'));
      await includes('Chỉ hàng còn sẵn');
      await click('Lọc thêm trong cửa hàng');
      await page.waitForURL(u => u.hash.startsWith('#/shop?style='));
      assert.equal(new URL(page.url().split('#')[1], base).searchParams.get('style'), collection.style);
      await open('/collections/does-not-exist');
      await includes('Chưa tìm thấy bộ sưu tập');
      await capture('not-found');
      await click('Xem bộ sưu tập');
      await includes(collections.total + ' bộ sưu tập');
      await context.close();
      console.log('PASS collections ' + width + 'px: database cards, detail, pagination, quick add, filters, recovery.');
    }
    assert.deepEqual(errors, []);
  } catch (error) {
    const page = browser.contexts().flatMap(c => c.pages()).at(-1);
    if (page) {
      await page.screenshot({ path: path.join(output, 'failure.png') });
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').ariaSnapshot());
    }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({ collections: summaries, uniqueProducts: seen.size, views, errors }, null, 2));
    await browser.close();
  }
})().catch(e => { console.error(e.message); process.exitCode = 1; });
