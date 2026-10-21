const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, fixture, buyerEmail, otherEmail, password, setProductAvailable }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web'), output = path.join(root, '.tools/api-reviews-verification');
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
      for (let i = 0; i < 28; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .8, viewport.height * .7);
        await page.mouse.wheel(0, box && box.y < 125 ? -350 : 350); await page.waitForTimeout(180);
      }
      throw new Error('Cannot reveal review control: ' + await node.getAttribute('aria-label'));
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }).last(); await reveal(node); await node.click(); await page.mouse.move(12, 125); await page.waitForTimeout(400); }
    // Flutter includes the visible hint in the focused textarea's accessible name.
    async function fill(name, value) { const node = page.getByRole('textbox', { name, exact: name !== 'Nội dung đánh giá' }); await reveal(node); await node.click(); await page.waitForTimeout(150); await node.fill(value); await page.waitForTimeout(200); assert.equal(await node.inputValue(), value); }
    async function login(email) { await fill('Email', email); await fill('Mật khẩu', password); await button('Đăng nhập'); }
    async function product() { await route('/products/' + fixture); await button('Xem đánh giá'); }
    async function frameReviews() {
      const heading = page.getByText('Đánh giá từ người mua', { exact: true });
      await reveal(heading);
      const box = await heading.boundingBox(), viewport = page.viewportSize();
      await page.mouse.move(viewport.width * .8, viewport.height * .7);
      await page.mouse.wheel(0, box.y - 145); await page.waitForTimeout(500);
    }
    async function logout() { await route('/account'); await button('Đăng xuất'); }
    async function history() { await route('/account'); await button('Đánh giá của tôi'); await page.getByText('1 đánh giá', { exact: true }).waitFor(); }
    async function frameHistory() {
      const title = page.getByText('Đánh giá của tôi', { exact: true }).first();
      await reveal(title);
      const box = await title.boundingBox(), viewport = page.viewportSize();
      await page.mouse.move(viewport.width * .8, viewport.height * .7);
      await page.mouse.wheel(0, box.y - 145); await page.waitForTimeout(500);
    }
    async function publish() { await button('Viết đánh giá'); await button('Chọn 5 sao'); await fill('Nội dung đánh giá', 'Mặc rất thoải mái.'); await button('Gửi đánh giá'); }
    await page.goto('http://127.0.0.1:4183/#/products/' + fixture); await semantics(); await button('Xem đánh giá');
    await page.getByText('Chưa có đánh giá', { exact: true }).waitFor();
    assert(!requests.some(r => r.path.endsWith('/reviews/me')));
    await frameReviews(); await page.screenshot({ path: path.join(output, 'reviews-guest-desktop.png') });
    await button('Đăng nhập để đánh giá'); await login(otherEmail); await button('Xem đánh giá');
    await page.getByText('Bạn có thể đánh giá sau khi đơn hàng được giao.', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Viết đánh giá', exact: true }).count(), 0);
    await logout(); await product(); await button('Đăng nhập để đánh giá'); await login(buyerEmail); await button('Xem đánh giá');
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(500);
    await button('Viết đánh giá'); await button('Chọn 4 sao'); await fill('Nội dung đánh giá', 'Cotton mềm, vừa size M.');
    await page.screenshot({ path: path.join(output, 'review-editor-mobile.png') });
    await button('Gửi đánh giá');
    await page.getByText('Cotton mềm, vừa size M.', { exact: true }).waitFor();
    await page.getByText('4,0 / 5', { exact: true }).waitFor();
    await frameReviews(); await page.screenshot({ path: path.join(output, 'review-published-mobile.png') });
    console.log('Chrome reviews: guest and non-buyer gates, verified buyer published on mobile.');
    await page.reload(); await semantics(); await button('Xem đánh giá');
    await page.getByText('Cotton mềm, vừa size M.', { exact: true }).waitFor();
    await history(); await frameHistory();
    await page.screenshot({ path: path.join(output, 'customer-reviews-mobile.png') });
    await button('Sửa đánh giá'); await button('Chọn 5 sao'); await fill('Nội dung đánh giá', 'Mặc rất thoải mái.'); await button('Lưu đánh giá');
    await page.getByText('Mặc rất thoải mái.', { exact: true }).waitFor();
    await button('Xem sản phẩm'); await button('Xem đánh giá');
    await page.getByText('5,0 / 5', { exact: true }).waitFor();
    await history(); await setProductAvailable(false); await button('Tải lại');
    await page.getByText('Sản phẩm không còn mở bán', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Sửa đánh giá', exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Xem sản phẩm', exact: true }).count(), 0);
    await frameHistory(); await page.screenshot({ path: path.join(output, 'customer-reviews-hidden-mobile.png') });
    await button('Xóa đánh giá'); await button('Xóa đánh giá');
    await page.getByText('Bạn chưa viết đánh giá nào', { exact: true }).waitFor();
    await setProductAvailable(true); await product();
    await publish(); await page.getByText('5,0 / 5', { exact: true }).waitFor();
    await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(500);
    await frameReviews();
    await page.screenshot({ path: path.join(output, 'reviews-buyer-desktop.png') });
    await history(); await frameHistory();
    await page.screenshot({ path: path.join(output, 'customer-reviews-desktop.png') });
    await page.reload(); await semantics();
    await page.getByText('1 đánh giá', { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => location.hash), '#/account/reviews');
    await logout(); await route('/account/reviews'); await button('Đăng nhập'); await login(otherEmail);
    await page.getByText('Bạn chưa viết đánh giá nào', { exact: true }).waitFor();
    assert.equal(await page.getByText('Mặc rất thoải mái.', { exact: true }).count(), 0);
    await logout(); await product();
    await page.getByText('Mặc rất thoải mái.', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Sửa đánh giá', exact: true }).count(), 0);
    assert(requests.some(r => r.method === 'PATCH' && r.path.endsWith('/reviews/me') && r.status === 200));
    assert(requests.some(r => r.method === 'DELETE' && r.path.endsWith('/reviews/me') && r.status === 200));
    assert(requests.some(r => r.path.endsWith('/users/me/reviews') && r.status === 200));
    assert(!requests.some(r => r.status >= 400 && !isAnonymousRestore(r)), 'Unexpected API failure'); assert.deepEqual(errors, []);
    console.log('PASS Chrome reviews: customer history navigation/login return, edit and hidden-product removal, republish, persisted reload, separate account privacy and public anonymous read.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png') }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
