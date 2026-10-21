const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
module.exports = async function verify({ root, email, customerEmail, password, returnedId, deliveredId }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web'), output = path.join(root, '.tools/api-shipment-verification');
  fs.mkdirSync(output, { recursive: true });
  const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.jpg': 'image/jpeg', '.png': 'image/png', '.ttf': 'font/ttf' };
  const server = http.createServer((req, res) => {
    const file = path.resolve(web, '.' + (req.url.split('?')[0] === '/' ? '/index.html' : decodeURIComponent(req.url.split('?')[0])));
    if (!file.startsWith(web + path.sep)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (error, data) => { res.writeHead(error ? 404 : 200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); res.end(error ? 'Not found' : data); });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(4183, '127.0.0.1', resolve); });
  let browser, page; const errors = [], requests = [];
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
      for (let i = 0; i < 32; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .7, viewport.height * .7);
        await page.mouse.wheel(0, box && box.y < 125 ? -280 : 280); await page.waitForTimeout(150);
      }
      throw Error('Cannot reveal shipment control');
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }).last(); await reveal(node); await node.click(); await page.mouse.move(10, 125); await page.waitForTimeout(300); }
    async function fill(name, value) { const field = page.getByRole('textbox', { name, exact: true }); await reveal(field); await field.click(); await page.waitForTimeout(100); await field.fill(value); await page.waitForTimeout(200); }
    async function login(account, staff) { await fill('Email', account); await fill('Mật khẩu', password); await button(staff ? 'Đăng nhập quản trị' : 'Đăng nhập'); }
    async function transition(name, note) {
      await button(name); if (note) await fill('Ghi chú cho khách (tùy chọn)', note);
      const response = page.waitForResponse(r => /\/(status|shipment-events)$/.test(new URL(r.url()).pathname) && ['PATCH', 'POST'].includes(r.request().method()));
      await button('Lưu thay đổi'); assert((await response).ok()); await page.waitForTimeout(400);
    }
    await page.goto('http://127.0.0.1:4183/#/admin/orders/' + returnedId); await semantics(); await login(email, true);
    await transition('Xác nhận đơn'); await transition('Bắt đầu giao hàng');
    const code = await page.getByText(/^LOCAL-[0-9A-F-]{36}$/).textContent();
    await page.getByText('Mô phỏng vận chuyển local', { exact: true }).waitFor();
    await transition('Đang giao đến khách'); await transition('Giao thất bại', 'Khách hẹn giao lại');
    assert.equal(await page.getByRole('button', { name: 'Đánh dấu đã giao', exact: true }).count(), 0);
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(300);
    await transition('Giao lại'); await transition('Giao thất bại', 'Khách từ chối nhận');
    await transition('Xác nhận hàng hoàn về kho', 'Đã nhận đủ hàng về kho');
    await page.getByText('Hiện tại: Đã hoàn về kho', { exact: true }).waitFor();
    await reveal(page.getByText('Mô phỏng vận chuyển local', { exact: true }));
    await page.screenshot({ path: path.join(output, 'returned-admin-mobile.png') });
    await page.setViewportSize({ width: 1440, height: 1000 });
    await route('/admin/orders/' + deliveredId); await transition('Xác nhận đơn'); await transition('Bắt đầu giao hàng'); await transition('Đánh dấu đã giao');
    await page.getByRole('button', { name: 'Đối soát COD', exact: true }).waitFor();
    assert((await page.locator('body').ariaSnapshot()).includes('Chưa thu tiền'));
    console.log('Chrome shipment: failed, retried, returned and separate delivered COD flow.');
    await route('/login?next=' + encodeURIComponent('/account/orders/' + returnedId)); await login(customerEmail, false);
    await page.getByText('Hiện tại: Đã hoàn về kho', { exact: true }).waitFor();
    assert.equal(await page.getByText(code, { exact: true }).count(), 1);
    await page.getByText('Đã nhận đủ hàng về kho', { exact: true }).first().waitFor();
    await reveal(page.getByText('Mô phỏng vận chuyển local', { exact: true }));
    await page.screenshot({ path: path.join(output, 'returned-customer-desktop.png') });
    await page.reload(); await semantics(); await button('Đăng nhập'); await login(customerEmail, false);
    await page.getByText('Hiện tại: Đã hoàn về kho', { exact: true }).waitFor();
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(300);
    await reveal(page.getByText(code, { exact: true })); await page.screenshot({ path: path.join(output, 'returned-customer-mobile.png') });
    assert.deepEqual(errors, []); assert(!requests.some(r => r.status >= 400), 'Unexpected API error');
    console.log('PASS Chrome shipment: persistent customer/admin history, simulator label, code, notes, reload/login, 375/1440px.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png') }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
