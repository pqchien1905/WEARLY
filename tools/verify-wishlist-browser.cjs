const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, fixture }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web');
  const output = path.join(root, '.tools/api-wishlist-verification');
  fs.mkdirSync(output, { recursive: true });
  const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.jpg': 'image/jpeg', '.png': 'image/png', '.ttf': 'font/ttf' };
  const server = http.createServer((req, res) => {
    const file = path.resolve(web, '.' + (req.url.split('?')[0] === '/' ? '/index.html' : decodeURIComponent(req.url.split('?')[0])));
    if (!file.startsWith(web + path.sep)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (error, data) => { res.writeHead(error ? 404 : 200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); res.end(error ? 'Not found' : data); });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(4183, '127.0.0.1', resolve); });
  let browser, page;
  const errors = [], requests = [];
  try {
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
    page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text())) errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function semantics() { await page.waitForTimeout(700); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function route(value) { await page.evaluate(value => { location.hash = value; }, value); await page.waitForTimeout(500); }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 24; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .8, viewport.height * .7);
        await page.mouse.wheel(0, box && box.y < 125 ? -350 : 350);
        await page.waitForTimeout(180);
      }
      throw new Error('Flutter control could not be scrolled into view');
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }); await reveal(node); await node.click(); await page.mouse.move(12, 125); await page.waitForTimeout(400); }
    async function fill(name, value) {
      const node = page.getByRole('textbox', { name, exact: true }); await reveal(node); await node.click(); await page.waitForTimeout(150); await node.fill(value); await page.waitForTimeout(200); assert.equal(await node.inputValue(), value);
    }
    const email = 'browser-' + fixture + '@example.com', secondEmail = fixture + '@example.com', password = 'Browser-only-Password-2026';
    async function register(account, name) { await fill('Tên của bạn', name); await fill('Email', account); await fill('Mật khẩu', password); await button('Tạo tài khoản'); await page.getByText('Chào ' + name + '.', { exact: true }).waitFor(); }
    async function login() { await fill('Email', email); await fill('Mật khẩu', password); await button('Đăng nhập'); }
    await page.goto('http://127.0.0.1:4183/#/register'); await semantics(); await register(email, 'Khách yêu thích');
    await route('/shop?q=' + fixture);
    await button('Yêu thích Áo cotton kiểm thử');
    await route('/wishlist');
    await page.getByText('1 sản phẩm đã lưu', { exact: true }).waitFor();
    await button('Bỏ yêu thích Áo cotton kiểm thử');
    await page.getByText('Tủ đồ yêu thích còn trống', { exact: true }).waitFor();
    console.log('Chrome wishlist: card save/remove persisted.');
    await route('/products/' + fixture); await button('Lưu yêu thích');
    await page.getByRole('button', { name: 'Bỏ yêu thích', exact: true }).waitFor();
    await button('M'); await button('Thêm vào giỏ');
    await page.keyboard.press('Escape'); await page.waitForTimeout(300);
    await route('/wishlist'); await button('Bỏ yêu thích Áo cotton kiểm thử');
    await route('/cart');
    const before = requests.filter(r => r.method === 'PUT' && r.path.includes('/wishlist/')).length;
    await button('Lưu yêu thích'); await button('Lưu yêu thích');
    assert.equal(requests.filter(r => r.method === 'PUT' && r.path.includes('/wishlist/')).length, before + 1, 'Cart save should not unsave or duplicate a favorite');
    await route('/wishlist'); await page.getByText('1 sản phẩm đã lưu', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'wishlist-desktop.png') });
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(output, 'wishlist-mobile.png') });
    await page.reload(); await semantics();
    await page.getByText('1 sản phẩm đã lưu', { exact: true }).waitFor();
    console.log('Chrome wishlist: detail/cart saves and reload/login persistence passed.');
    await page.setViewportSize({ width: 1440, height: 900 });
    await route('/account'); await button('Đăng xuất');
    await route('/register'); await register(secondEmail, 'Khách khác');
    await route('/wishlist'); await page.getByText('Tủ đồ yêu thích còn trống', { exact: true }).waitFor();
    await route('/account'); await button('Đăng xuất');
    await route('/login?next=%2Fwishlist'); await login(); await page.getByText('1 sản phẩm đã lưu', { exact: true }).waitFor();
    for (const width of [600, 1440, 375, 1440]) { await page.setViewportSize({ width, height: 700 }); await page.waitForTimeout(250); }
    assert.deepEqual(errors, []); assert(!requests.some(r => r.status >= 400 && !isAnonymousRestore(r)), 'Unexpected API failure');
    console.log('PASS Chrome wishlist: card/detail/cart, idempotency, responsive UI, reload persistence and account isolation.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png') }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
