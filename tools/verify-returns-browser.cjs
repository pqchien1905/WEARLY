const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
module.exports = async function verify({ root, email, customerEmail, password, orderId, cancelId, refunds=false }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web'), output = path.join(root, refunds?'.tools/api-refund-verification':'.tools/api-return-verification');
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
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 } }); page.setDefaultTimeout(18000);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text())) errors.push(m.text()); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function semantics() { await page.waitForTimeout(700); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
    async function route(value) { await page.evaluate(value => { location.hash = value; }, value); await page.waitForTimeout(500); }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 36; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .7, viewport.height * .7); await page.mouse.wheel(0, box && box.y < 125 ? -280 : 280); await page.waitForTimeout(150);
      }
      throw Error('Cannot reveal return control');
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }).last(); await reveal(node); await node.click(); await page.mouse.move(10, 125); await page.waitForTimeout(300); }
    async function fill(name, value) { const field = page.getByRole('textbox', { name, exact: typeof name === 'string' }); await reveal(field); await field.click(); await page.waitForTimeout(100); await field.fill(value); await page.waitForTimeout(200); }
    async function login(account, staff) { await fill(staff ? 'Tên đăng nhập' : 'Email', staff ? account.split('@')[0] : account); await fill('Mật khẩu', password); await button(staff ? 'Đăng nhập quản trị' : 'Đăng nhập'); }
    async function action(name, field, note) { await button(name); await fill(field, note); const response = page.waitForResponse(r => /\/(decision|receive|cancel)$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST'); await button('Lưu thay đổi'); assert((await response).ok()); await page.waitForTimeout(400); }
    await page.goto('http://127.0.0.1:4183/#/login?next=' + encodeURIComponent('/account/orders/' + orderId)); await semantics(); await login(customerEmail, false);
    await fill(/^Số lượng trả:/, '1'); await fill('Lý do trả hàng', 'Không vừa kích thước');
    await button('Tính tiền hàng dự kiến hoàn'); await page.getByText(/Tiền hàng dự kiến hoàn: 465.000/).waitFor();
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(300);
    await button('Gửi yêu cầu trả hàng'); await page.getByText('Chờ duyệt trả hàng', { exact: true }).waitFor();
    await reveal(page.getByText('Chờ duyệt trả hàng', { exact: true })); await page.screenshot({ path: path.join(output, 'request-customer-mobile.png') });
    await route('/admin/orders/' + orderId); await login(email, true);
    await action('Duyệt trả hàng', 'Ghi chú cho khách', 'Vui lòng gửi lại đúng sản phẩm đã chọn');
    await action('Nhận hàng khách trả', 'Ghi chú cho khách', 'Đã nhận một sản phẩm, hàng nguyên vẹn');
    await page.getByText('Đã nhận hàng khách trả', { exact: true }).waitFor();
    await reveal(page.getByText('Đã nhận hàng khách trả', { exact: true })); await page.screenshot({ path: path.join(output, 'received-admin-mobile.png') });
    assert(!(await page.locator('body').ariaSnapshot()).includes('Đã hoàn tiền'));
    if(refunds) {
      await button('Ghi nhận hoàn COD');await fill('Mã biên nhận hoàn tiền','BROWSER-COD-'+orderId);
      const response=page.waitForResponse(r=>r.url().endsWith('/refunds')&&r.request().method()==='POST');
      await button('Xác nhận đã hoàn COD');assert((await response).ok());
      await page.getByText('Đã hoàn tiền',{exact:true}).waitFor();await reveal(page.getByText('Đã hoàn tiền',{exact:true}));
      await page.screenshot({path:path.join(output,'cod-refunded-admin-mobile.png')});
    }
    await page.setViewportSize({ width: 1440, height: 1000 }); await route('/admin/orders/' + cancelId);
    await action('Hủy đơn trước khi gửi', 'Lý do hủy đơn', 'Khách đổi ý trước khi gửi hàng');
    await page.getByText('Đơn đã hủy', { exact: true }).waitFor();
    assert((await page.locator('body').ariaSnapshot()).includes('Đã thanh toán'));
    if(refunds) {
      await button('Hoàn qua VNPay sandbox');
      let response=page.waitForResponse(r=>r.url().endsWith('/refunds')&&r.request().method()==='POST');
      await button('Gửi yêu cầu hoàn sandbox');assert((await response).ok());
      await page.getByText('VNPay đang xử lý hoàn',{exact:true}).waitFor();
      assert(!(await page.locator('body').ariaSnapshot()).includes('Đã hoàn tiền'));
      await button('Kiểm tra kết quả hoàn');response=page.waitForResponse(r=>r.url().endsWith('/query')&&r.request().method()==='POST');
      await button('Truy vấn VNPay');assert((await response).ok());
      await page.getByText('Đã hoàn tiền',{exact:true}).waitFor();await reveal(page.getByText('Đã hoàn tiền',{exact:true}));
      await page.screenshot({path:path.join(output,'vnpay-refunded-admin-desktop.png')});
    }
    await route('/account/orders/' + orderId); await button('Cập nhật yêu cầu trả hàng');
    await page.getByText('Đã nhận hàng khách trả', { exact: true }).waitFor();
    if(refunds){await button('Cập nhật hoàn tiền');await page.getByText('Đã hoàn tiền',{exact:true}).waitFor();}
    await reveal(page.getByText('Đã nhận hàng khách trả', { exact: true })); await page.screenshot({ path: path.join(output, 'received-customer-desktop.png') });
    await page.reload(); await semantics();
    await page.getByText('Đã nhận hàng khách trả', { exact: true }).waitFor();
    if(refunds){await page.getByText('Đã hoàn tiền',{exact:true}).waitFor();await reveal(page.getByText('Đã hoàn tiền',{exact:true}));await page.screenshot({path:path.join(output,'refunded-customer-desktop.png')});}
    assert.deepEqual(errors, []); assert(!requests.some(r => r.status >= 400 && !isAnonymousRestore(r)), 'Unexpected API error');
    console.log('PASS Chrome returns: discounted partial request, approve, receive, paid cancellation, customer persistence, desktop/mobile.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png') }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
