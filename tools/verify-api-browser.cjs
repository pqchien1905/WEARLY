const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, fixture }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web');
  const output = path.join(root, '.tools/api-shopping-verification');
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
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    async function semantics() { await page.waitForTimeout(700); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function route(value) { await page.evaluate(value => { location.hash = value; }, value); await page.waitForTimeout(400); }
    // Flutter rebuilds semantics while detail data loads. Scroll the actual
    // canvas viewport and resolve the locator again each time, rather than
    // scrolling an HTML semantics element that may detach during an update.
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 24; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 95 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * 0.8, viewport.height * 0.7);
        await page.mouse.wheel(0, box && box.y < 95 ? -350 : 350);
        await page.waitForTimeout(180);
      }
      throw new Error('Flutter control could not be scrolled into view');
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }); await reveal(node); await node.click(); }
    async function fill(name, value) {
      const field = page.getByRole('textbox', {
        name: name === 'Tên gợi nhớ' ? /^Tên gợi nhớ(?: Nhà, Văn phòng…)?$/ : name,
        exact: true,
      });
      // Focusing an obscured Flutter field can replace its semantics input.
      // Let that transition finish before Playwright fills the current element.
      await field.click();
      await page.evaluate(() => new Promise(resolve =>
        requestAnimationFrame(() => requestAnimationFrame(resolve))));
      await field.fill(value);
      // Flutter synchronizes the HTML editing element with Dart on the next
      // frame. Do not immediately move focus and race that synchronization.
      await page.waitForTimeout(120);
      assert.equal(await field.inputValue(), value, 'Field did not retain input: ' + name);
    }
    const email = 'browser-' + fixture + '@example.com';
    await page.goto('http://127.0.0.1:4183/#/register'); await semantics();
    await fill('Tên của bạn', 'Nguyễn Trình Duyệt');
    await fill('Email', email);
    await fill('Mật khẩu', 'Browser-only-Password-2026');
    await button('Tạo tài khoản');
    await page.getByText('Chào Nguyễn Trình Duyệt.', { exact: true }).waitFor();
    console.log('Chrome: registration persisted.');
    await route('/account/addresses'); await button('Thêm địa chỉ');
    await fill('Tên gợi nhớ', 'Nhà');
    await fill('Người nhận', 'Nguyễn Trình Duyệt');
    await fill('Điện thoại nhận hàng', '0901234567');
    await fill('Địa chỉ nhận hàng', '12 Nguyễn Huệ, TP.HCM');
    await button('Lưu địa chỉ');
    await page.getByText('12 Nguyễn Huệ, TP.HCM', { exact: true }).waitFor();
    console.log('Chrome: address saved.');
    await route('/products/' + fixture);
    await page.getByText('Áo cotton kiểm thử', { exact: true }).first().waitFor();
    await button('M');
    await button('Thêm vào giỏ');
    await route('/cart');
    await page.getByText('Giỏ hàng của bạn', { exact: true }).waitFor();
    await page.setViewportSize({ width: 375, height: 812 });
    await page.screenshot({ path: path.join(output, 'cart-mobile.png'), fullPage: true });
    await button('Tiến hành đặt hàng');
    await page.getByText('Chọn địa chỉ đã lưu', { exact: true }).click();
    await page.getByRole('menuitem', { name: 'Nhà — Nguyễn Trình Duyệt', exact: true }).click();
    const confirm = page.getByRole('checkbox', { name: 'Tôi xác nhận thông tin nhận hàng và đặt đơn COD.', exact: true });
    await reveal(confirm); await confirm.click();
    await button('Đặt hàng COD');
    await page.getByText('Đã tiếp nhận đơn hàng', { exact: true }).waitFor();
    console.log('Chrome: COD order persisted.');
    assert((await page.locator('body').ariaSnapshot()).includes('Chưa thu tiền'));
    await button('Xem chi tiết đơn');
    await button('Hủy đơn hàng'); await button('Xác nhận hủy');
    await page.getByText('Đơn đã hủy', { exact: true }).waitFor();
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.screenshot({ path: path.join(output, 'order-desktop.png'), fullPage: true });
    await page.reload(); await semantics();
    await page.getByText('Đăng nhập để tiếp tục', { exact: true }).waitFor();
    await button('Đăng nhập');
    await fill('Email', email);
    await fill('Mật khẩu', 'Browser-only-Password-2026');
    await button('Đăng nhập');
    await page.getByText('Đơn đã hủy', { exact: true }).waitFor();
    await route('/faq');
    await page.mouse.move(700, 600); await page.mouse.wheel(0, 835);
    for (const width of [600, 1440, 375, 1440]) { await page.setViewportSize({ width, height: 900 }); await page.waitForTimeout(250); }
    await button('Làm sao chọn size phù hợp?');
    assert((await page.locator('body').ariaSnapshot()).includes('Mở bảng size ở trang sản phẩm'));
    assert.deepEqual(errors, []);
    assert(requests.some(r => r.path.endsWith('/orders') && r.status === 201));
    console.log('PASS Chrome real API: register, address, cart, COD, cancel, reload/login restores order, 375/1440px and F12 resize.');
  } catch (error) {
    if (page) {
      fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot());
      await page.screenshot({ path: path.join(output, 'failure.png'), fullPage: true });
    }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
};
