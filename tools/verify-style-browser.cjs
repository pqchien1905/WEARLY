const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, email, otherEmail, password, changeStyle }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web'), output = path.join(root, '.tools/api-style-verification');
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
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text())) errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function semantics() { await page.waitForTimeout(700); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function route(value) { await page.evaluate(value => { location.hash = value; }, value); await page.waitForTimeout(500); }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 28; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .8, viewport.height * .7);
        await page.mouse.wheel(0, box && box.y < 125 ? -300 : 300); await page.waitForTimeout(150);
      }
      throw new Error('Cannot reveal style control');
    }
    async function click(node) { await reveal(node); await node.click(); await page.mouse.move(12, 125); await page.waitForTimeout(300); }
    async function button(name) { await click(page.getByRole('button', { name, exact: true }).last()); }
    async function login(account) {
      for (const [name, value] of [['Email', account], ['Mật khẩu', password]]) {
        const field = page.getByRole('textbox', { name, exact: true });
        await reveal(field); await field.click(); await page.waitForTimeout(150);
        await field.fill(value); await page.waitForTimeout(200);
        assert.equal(await field.inputValue(), value);
      }
      await button('Đăng nhập');
    }
    async function choose(label, value) {
      await click(page.getByRole('button', { name: `${label}: ${value}`, exact: true }));
    }
    async function save() { await button('Lưu hồ sơ phong cách'); await page.locator('flt-semantics').getByText('Đã lưu hồ sơ phong cách.', { exact: true }).waitFor(); }
    async function selected(label, value) {
      const field = page.getByRole('button', { name: `${label}: ${value}`, exact: true });
      await field.waitFor();
      assert.equal(await field.getAttribute('aria-current'), 'true', 'Unexpected selection for ' + label);
    }
    async function frame() {
      const heading = page.getByText('Phong cách, theo ý bạn.', { exact: true }); await reveal(heading);
      const box = await heading.boundingBox(); await page.mouse.wheel(0, box.y - 145); await page.waitForTimeout(400);
    }
    await page.goto('http://127.0.0.1:4183/#/account/style'); await semantics(); await button('Đăng nhập'); await login(email);
    assert.equal(await page.evaluate(() => location.hash), '#/account/style');
    await choose('Size thường chọn', 'L'); await choose('Phong cách yêu thích', 'Thanh lịch'); await choose('Màu ưu tiên', 'Đen'); await choose('Ngân sách mỗi outfit', '2.500.000 ₫'); await save();
    assert.equal(await page.getByRole('button', { name: 'Lưu & mở Stylist', exact: true }).count(), 0);
    await frame(); await page.screenshot({ path: path.join(output, 'style-desktop.png') });
    await page.reload(); await semantics();
    await selected('Size thường chọn', 'L'); await selected('Ngân sách mỗi outfit', '2.500.000 ₫');
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await choose('Size thường chọn', 'S'); await save();
    await frame(); await page.screenshot({ path: path.join(output, 'style-mobile-top.png') });
    await reveal(page.getByRole('button', { name: 'Lưu hồ sơ phong cách', exact: true }));
    await page.screenshot({ path: path.join(output, 'style-mobile-form.png') });
    await changeStyle(); await choose('Size thường chọn', 'XL'); await button('Lưu hồ sơ phong cách');
    await page.getByText('Tải lại hồ sơ để kiểm tra kết quả trước khi lưu tiếp. Thay đổi chưa lưu sẽ được bỏ.', { exact: true }).waitFor();
    await button('Tải lại hồ sơ'); await selected('Size thường chọn', 'XS');
    await choose('Size thường chọn', 'XL'); await save();
    await route('/account'); await button('Đăng xuất'); await route('/account/style'); await button('Đăng nhập'); await login(otherEmail);
    await selected('Size thường chọn', 'M'); await selected('Ngân sách mỗi outfit', '1.500.000 ₫');
    assert.equal(requests.filter(r => r.status === 409).length, 1);
    assert(!requests.some(r => r.status >= 400 && !isAnonymousRestore(r) && r.status !== 409), 'Unexpected API failure'); assert.deepEqual(errors, []);
    console.log('PASS Chrome style: saved choices, reload/login persistence, mobile second save, stale-form rejection/reload, isolated defaults, no demo/AI action.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png') }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
