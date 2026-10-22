const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, fixture, payments=false, promotion=null, markFixturePaid }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web');
  const output = path.join(root, promotion ? '.tools/api-promotion-verification' : payments ? '.tools/api-payment-verification' : '.tools/api-shopping-verification');
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
    const browserContext = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    page = await browserContext.newPage();
    if(payments) await page.context().route('https://sandbox.vnpayment.vn/**',route=>route.fulfill({status:200,contentType:'text/html',body:'<h1>LOCAL BROWSER TEST FIXTURE</h1>'}));
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
    if(promotion) {
      await page.goto('http://127.0.0.1:4183/#/admin/login'); await semantics();
      await fill('Tên đăng nhập',promotion.adminEmail.split('@')[0]);await fill('Mật khẩu',promotion.password);await button('Đăng nhập quản trị');
      await page.getByText('Một góc nhìn toàn cảnh.',{exact:true}).waitFor();
      await route('/admin/promotions');await button('Thêm mã khuyến mãi');
      async function dialogReveal(node) {
        for(let i=0;i<24;i++) {
          const box=await node.boundingBox().catch(()=>null),height=page.viewportSize().height;
          if(box&&box.y>=120&&box.y+box.height<height-110)return;
          await page.mouse.move(page.viewportSize().width/2,height/2);await page.mouse.wheel(0,box&&box.y<120?-220:220);await page.waitForTimeout(160);
        }
        throw Error('Promotion dialog control not visible');
      }
      async function promotionField(label,value){const node=page.getByRole('textbox',{name:label,exact:true});await dialogReveal(node);await node.click();await page.waitForTimeout(120);await node.fill(value);await page.waitForTimeout(120);}
      await promotionField('Mã khuyến mãi',promotion.code);await promotionField('Giá trị giảm','50000');await promotionField('Tổng lượt tối đa (tùy chọn)','1');
      const enabled=page.getByRole('switch',{name:'Đang áp dụng',exact:true});await dialogReveal(enabled);await enabled.click();
      await button('Lưu thay đổi');await page.getByRole('button',{name:'Chỉnh sửa '+promotion.code,exact:true}).waitFor();
      await page.screenshot({path:path.join(output,'promotion-admin-desktop.png'),fullPage:true});
      console.log('Chrome: admin promotion created.');
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
    if(payments) {
      const method=page.getByRole('button',{name:'Phương thức thanh toán COD',exact:true}); await reveal(method); await method.click();
      await page.getByRole('menuitem',{name:'VNPay sandbox',exact:true}).click();
    }
    if(promotion) {
      const input=page.getByRole('textbox',{name:/^Mã khuyến mãi/});await reveal(input);await input.click();await page.waitForTimeout(120);await input.fill(promotion.code);await page.waitForTimeout(150);
      await button('Áp dụng mã');await page.getByText('Khuyến mãi '+promotion.code,{exact:true}).waitFor();
      assert((await page.locator('body').ariaSnapshot()).includes('470.000'));
      await page.screenshot({path:path.join(output,'discount-checkout-mobile.png'),fullPage:true});
    }
    const confirm = page.getByRole('checkbox', { name: 'Tôi xác nhận thông tin nhận hàng và phương thức thanh toán.', exact: true });
    await reveal(confirm); await confirm.click();
    await button(payments ? 'Đặt hàng với VNPay sandbox':'Đặt hàng COD');
    await page.getByText('Đã tiếp nhận đơn hàng', { exact: true }).waitFor();
    console.log('Chrome: '+(payments?'VNPay sandbox':'COD')+' order persisted.');
    assert((await page.locator('body').ariaSnapshot()).includes(payments?'Chờ thanh toán':'Chưa thu tiền'));
    if(payments) {
      await button('Chuẩn bị thanh toán');
      const nextPage=page.context().waitForEvent('page');
      await button('Mở VNPay sandbox (tab mới)');
      const popup=await nextPage; await popup.waitForLoadState();
      const url=new URL(popup.url()); assert.equal(url.hostname,'sandbox.vnpayment.vn'); assert.equal(url.searchParams.get('vnp_Amount'),'52000000');
      await popup.close(); markFixturePaid();
      await button('Kiểm tra kết quả');
      await page.getByText('Đã thanh toán',{exact:true}).waitFor();
      console.log('Chrome: signed local query fixture verified and payment displayed.');
    }
    await button('Xem chi tiết đơn');
    if(!payments) {await button('Hủy đơn hàng'); await button('Xác nhận hủy');}
    await page.getByText(payments?'Đã thanh toán':'Đơn đã hủy', { exact: true }).waitFor();
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.screenshot({ path: path.join(output, 'order-desktop.png'), fullPage: true });
    await page.reload(); await semantics();
    await page.getByText(payments?'Đã thanh toán':'Đơn đã hủy', { exact: true }).waitFor();
    if(payments) {
      const returned=await page.context().newPage();
      await returned.goto('http://127.0.0.1:4183/#/payments/return');
      await returned.waitForTimeout(700); await returned.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
      await returned.getByText('Đã quay lại từ VNPay sandbox',{exact:true}).waitFor();
      assert(!(await returned.locator('body').ariaSnapshot()).includes('Đã thanh toán')); await returned.close();
    }
    await route('/faq');
    await page.mouse.move(700, 600); await page.mouse.wheel(0, 835);
    for (const width of [600, 1440, 375, 1440]) { await page.setViewportSize({ width, height: 900 }); await page.waitForTimeout(250); }
    await button('Làm sao chọn size phù hợp?');
    assert((await page.locator('body').ariaSnapshot()).includes('Mở bảng size ở trang sản phẩm'));
    assert.deepEqual(errors, []);
    assert(requests.some(r => r.path.endsWith('/orders') && r.status === 201));
    console.log('PASS Chrome real API: register, address, cart, '+(payments?'VNPay sandbox with signed LOCAL fixtures':'COD, cancel')+', reload/login restores order, 375/1440px and F12 resize.');
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
