const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

module.exports = async function verify({ root, fixture, email, customerEmail, password, orderId }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web');
  const output = path.join(root, '.tools/api-admin-verification');
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
    // Scroll the Flutter viewport, not the browser's semantics overlay. Native
    // scrollIntoView can move the overlay without moving the canvas hit targets.
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 24; i++) {
        const box = await node.boundingBox();
        const viewport = page.viewportSize();
        if (box && box.y >= 95 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * 0.8, viewport.height * 0.7);
        await page.mouse.wheel(0, box && box.y < 95 ? -350 : 350);
        await page.waitForTimeout(180);
      }
      throw new Error('Flutter control could not be scrolled into view');
    }
    async function button(name) { const node = page.getByRole('button', { name, exact: true }); if (name !== 'Đăng xuất quản trị') await reveal(node); await node.click(); await page.waitForTimeout(300); }
    async function fill(name, value) {
      const field = page.getByRole('textbox', { name, exact: true });
      await reveal(field); await field.click(); await page.waitForTimeout(150);
      await field.fill(value); await page.waitForTimeout(200);
      assert.equal(await field.inputValue(), value);
    }
    async function login(account, admin = true) { await fill('Email', account); await fill('Mật khẩu', password); await button(admin ? 'Đăng nhập quản trị' : 'Đăng nhập'); }
    await page.goto('http://127.0.0.1:4183/#/admin'); await semantics();
    await page.getByRole('button', { name: 'Đăng nhập quản trị', exact: true }).waitFor();
    assert(page.url().includes('/admin/login?next='));
    assert(!(await page.locator('body').ariaSnapshot()).includes('Bản tin'));
    await page.screenshot({ path: path.join(output, 'admin-login-desktop.png') });
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(output, 'admin-login-mobile.png') });
    await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(400);
    await login(customerEmail);
    // Flutter also announces live errors in a separate accessibility element.
    await page.locator('flt-semantics').getByText('Tài khoản này chưa có quyền quản trị. Vui lòng dùng tài khoản được cửa hàng cấp quyền.', { exact: true }).waitFor();
    assert(page.url().includes('/admin/login'));
    await login(email);
    await page.getByText('Một góc nhìn toàn cảnh.', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'dashboard-desktop.png'), fullPage: true });
    console.log('Chrome admin: authenticated dashboard.');
    assert(!requests.some(r => r.path.endsWith('/auth/browser/customer/login') || r.path.endsWith('/cart') || r.path.includes('/users/me')), 'Admin login must not initialize shopper data');
    for (const [kind, label, initial, renamed] of [
      ['categories', 'danh mục', 'BST mới kiểm thử', 'BST thu đông kiểm thử'],
      ['brands', 'thương hiệu', 'AAA Studio mới kiểm thử', 'AAA Studio thu đông kiểm thử'],
    ]) {
      await route('/admin/' + kind);
      await button('Thêm ' + label);
      await fill('Tên hiển thị', initial);
      await fill('Đường dẫn', fixture + '-taxonomy');
      await button('Lưu thay đổi');
      await page.getByText(initial, { exact: true }).waitFor();
      await button('Đổi tên ' + initial);
      await fill('Tên hiển thị', renamed);
      await button('Lưu thay đổi');
      await page.mouse.move(12, 125); await page.waitForTimeout(500);
      await page.getByText(renamed, { exact: true }).waitFor();
      await page.screenshot({ path: path.join(output, kind + '-desktop.png') });
      await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(output, kind + '-mobile.png') });
      await button('Đổi tên ' + renamed);
      await page.screenshot({ path: path.join(output, kind + '-dialog-mobile.png') });
      await button('Đóng');
      await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(400);
    }
    console.log('Chrome admin: created and renamed category/brand, responsive lists and dialogs.');
    await route('/admin/products/new');
    await fill('Tên sản phẩm', 'Áo quản trị trình duyệt');
    await fill('Đường dẫn sản phẩm', fixture + '-admin');
    await page.getByText('Danh mục', { exact: true }).last().click();
    await page.getByRole('menuitem', { name: 'BST thu đông kiểm thử', exact: true }).click();
    await page.waitForTimeout(300);
    await page.getByText('Thương hiệu', { exact: true }).last().click();
    await page.getByRole('menuitem', { name: 'AAA Studio thu đông kiểm thử', exact: true }).click();
    await page.waitForTimeout(300);
    await fill('Mô tả', 'Sản phẩm kiểm thử quản trị.');
    await fill('Chất liệu', 'Cotton');
    await fill('Phong cách', 'Tối giản');
    await button('Thêm ảnh');
    await fill('Đường dẫn ảnh', 'assets/images/shirt.jpg');
    await fill('Mô tả ảnh', 'Áo kiểm thử quản trị');
    await button('Lưu thông tin sản phẩm');
    console.log('Chrome admin: created product with gallery.');
    const chooser = page.waitForEvent('filechooser');
    await button('Tải ảnh từ máy');
    const sharp = require(path.join(root, 'backend/node_modules/sharp'));
    const photo = await sharp({ create: { width: 120, height: 160, channels: 3, background: '#568079' } })
      .withExif({ IFD0: { Artist: 'Synthetic catalog browser fixture' } }).png().toBuffer();
    const uploaded = page.waitForResponse(r => /\/api\/v1\/admin\/products\/[^/]+\/images$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
    await (await chooser).setFiles({ name: 'catalog-fixture.png', mimeType: 'image/png', buffer: photo });
    const uploadedResponse = await uploaded;
    assert.equal(uploadedResponse.status(), 201);
    const receipt = await uploadedResponse.json();
    const uploadedField = page.getByRole('textbox', { name: 'Đường dẫn ảnh', exact: true }).nth(1);
    await uploadedField.waitFor({ state: 'attached' });
    await reveal(uploadedField); await uploadedField.click(); await page.waitForTimeout(200);
    assert.equal(await uploadedField.inputValue(), receipt.url);
    assert.equal(await page.getByRole('textbox', { name: 'Đường dẫn ảnh', exact: true }).count(), 2);
    // Make the uploaded asset the cover using the ordinary gallery save path.
    const removeOld = page.getByRole('button', { name: 'Bỏ ảnh', exact: true }).first();
    await reveal(removeOld); await removeOld.click(); await page.waitForTimeout(300);
    await button('Lưu thông tin sản phẩm');
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await reveal(page.getByRole('textbox', { name: 'Đường dẫn ảnh', exact: true }));
    await page.screenshot({ path: path.join(output, 'catalog-upload-mobile.png') });
    assert(requests.some(r => r.path.endsWith('/' + receipt.url) && r.status === 200), 'Verified catalog preview was not loaded');
    await page.setViewportSize({ width: 1440, height: 900 }); await page.waitForTimeout(400);
    console.log('Chrome admin: multipart file selected, verified public preview loaded, uploaded cover saved on mobile.');
    await button('Thêm biến thể');
    await fill('Mã SKU', fixture + '-admin-M'); await fill('Kích cỡ', 'M');
    await fill('Màu sắc', 'Trắng'); await fill('Mã màu HEX', '#FFFFFF'); await fill('Giá bán (VND)', '690000');
    await button('Lưu thay đổi');
    await button('Điều chỉnh kho');
    await fill('Số lượng thay đổi', '8'); await fill('Lý do', 'Nhập kho kiểm thử');
    await button('Lưu thay đổi');
    await page.getByText('Đang bán · Tồn kho: 8', { exact: true }).waitFor();
    await button('Sửa giá / trạng thái'); await fill('Giá bán (VND)', '700000'); await button('Lưu thay đổi');
    const visible = page.getByRole('switch', { name: /Hiển thị sản phẩm/ });
    await reveal(visible); await visible.click(); await page.waitForTimeout(300);
    await button('Lưu thông tin sản phẩm');
    await page.waitForTimeout(500);
    await page.reload(); await semantics();
    await page.getByText('Đang bán · Tồn kho: 8', { exact: true }).waitFor();
    assert((await page.locator('body').ariaSnapshot()).includes('700.000'));
    console.log('Chrome admin: product, gallery, SKU price and stock persisted across reload/login.');
    await route('/shop');
    const categoryChip = page.getByRole('checkbox', { name: 'BST thu đông kiểm thử', exact: true });
    await reveal(categoryChip); await categoryChip.click(); await page.waitForTimeout(400);
    await page.getByText('Áo quản trị trình duyệt', { exact: true }).waitFor();
    assert(page.url().includes('category=' + fixture + '-taxonomy'));
    await page.screenshot({ path: path.join(output, 'category-storefront-desktop.png') });
    console.log('Chrome storefront: new category filters the published product.');
    await page.setViewportSize({ width: 375, height: 812 });
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(output, 'category-storefront-mobile.png') });
    await route('/admin/inventory'); await page.getByText(fixture + '-admin-M · Trắng / M', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'inventory-mobile.png'), fullPage: true });
    await route('/admin/orders/' + orderId);
    for (const name of ['Xác nhận đơn', 'Bắt đầu giao hàng', 'Đánh dấu đã giao']) { await button(name); await button('Lưu thay đổi'); await page.waitForTimeout(400); }
    await page.getByText('Đã giao', { exact: true }).waitFor();
    assert((await page.locator('body').ariaSnapshot()).includes('Chưa thu tiền'));
    await page.screenshot({ path: path.join(output, 'order-mobile.png'), fullPage: true });
    await button('Đối soát COD');
    await fill('Số tiền đã thu (VND)', '520000');
    await fill('Mã đối soát', 'COD-BROWSER-001');
    await button('Lưu thay đổi');
    await page.getByText('Mã đối soát: COD-BROWSER-001', { exact: true }).waitFor();
    assert((await page.locator('body').ariaSnapshot()).includes('Đã thanh toán'));
    assert.equal(await page.getByRole('button', { name: 'Đối soát COD', exact: true }).count(), 0);
    await page.screenshot({ path: path.join(output, 'cod-receipt-mobile.png'), fullPage: true });
    await route('/admin/content');
    await fill('Tiêu đề campaign', 'Campaign kiểm thử');
    await fill('Nội dung chính sách', 'Chính sách kiểm thử đã xuất bản.');
    await fill('Tên cửa hàng', 'WEARLY kiểm thử');
    await fill('Điều khoản sử dụng', 'Điều khoản local kiểm thử.');
    const firstContentSave = page.waitForResponse(r => r.url().endsWith('/api/v1/admin/content') && r.request().method() === 'PUT' && r.status() === 200);
    await button('Lưu bản nháp');
    await firstContentSave;
    await page.getByText('Chưa xuất bản nội dung cửa hàng. Bản nháp chỉ quản trị viên nhìn thấy.', { exact: true }).waitFor();
    await route('/');
    await page.getByText('Mặc theo\ncách bạn.', { exact: true }).waitFor();
    assert.equal(await page.getByText('Campaign kiểm thử', { exact: true }).count(), 0);
    assert.equal(await page.getByText('WEARLY kiểm thử', { exact: true }).count(), 0);
    await route('/admin/content');
    await button('Xuất bản nội dung');
    await page.getByText('Chính sách kiểm thử đã xuất bản.', { exact: true }).first().waitFor();
    await page.screenshot({ path: path.join(output, 'content-mobile.png') });
    await route('/');
    await page.getByText('Campaign kiểm thử', { exact: true }).waitFor();
    await route('/shipping-returns');
    await page.getByText('Chính sách kiểm thử đã xuất bản.', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'published-policy-mobile.png') });
    await route('/terms');
    await page.getByText('Điều khoản local kiểm thử.',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'published-terms-mobile.png')});
    await page.setViewportSize({width:1440,height:900});await page.waitForTimeout(400);
    await page.getByRole('button',{name:'WEARLY kiểm thử',exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'published-terms-desktop.png')});
    await page.setViewportSize({width:375,height:812});await page.waitForTimeout(400);
    await route('/admin/content');
    await fill('Tiêu đề campaign', 'Bản nháp tiếp theo');
    const nextContentSave = page.waitForResponse(r => r.url().endsWith('/api/v1/admin/content') && r.request().method() === 'PUT' && r.status() === 200);
    await button('Lưu bản nháp');
    await nextContentSave;
    await route('/');
    await page.getByText('Campaign kiểm thử', { exact: true }).waitFor();
    assert.equal(await page.getByText('Bản nháp tiếp theo', { exact: true }).count(), 0);
    console.log('Chrome content: draft private, explicit publication visible, later draft leaves publication unchanged.');
    await route('/admin');
    const history = page.getByText('Thay đổi gần đây', { exact: true });
    await history.scrollIntoViewIfNeeded();
    await page.getByText('Chuyển trạng thái đơn hàng', { exact: true }).first().waitFor();
    await page.screenshot({ path: path.join(output, 'activity-mobile.png') });
    await button('Tải lại lịch sử');
    await page.getByText('Chuyển trạng thái đơn hàng', { exact: true }).first().waitFor();
    console.log('Chrome admin: persistent activity history and refresh on mobile.');
    await route('/admin/customers'); await page.getByText('Khách hàng', { exact: true }).last().waitFor();
    await page.waitForTimeout(500);
    assert((await page.locator('body').ariaSnapshot()).includes('Khách kiểm thử'));
    assert(!(await page.locator('body').ariaSnapshot()).includes('Quản trị kiểm thử'));
    await button('Đăng xuất quản trị');
    await page.getByRole('button', { name: 'Đăng nhập quản trị', exact: true }).waitFor();
    await page.setViewportSize({ width: 1440, height: 900 });
    await route('/login?next=%2Fadmin');
    await page.getByText('Đăng nhập khách hàng', { exact: true }).waitFor();
    await page.screenshot({ path: path.join(output, 'customer-login-desktop.png') });
    await login(customerEmail, false);
    await page.getByText('Chào Khách kiểm thử.', { exact: true }).waitFor();
    assert(page.url().endsWith('/account'), 'Shopper next must not enter admin');
    await route('/admin/customers');
    await page.getByRole('button', { name: 'Đăng nhập quản trị', exact: true }).waitFor();
    await login(email);
    await page.getByText('Khách hàng', { exact: true }).last().waitFor();
    await button('Đăng xuất quản trị');
    await route('/account');
    await page.getByText('Chào Khách kiểm thử.', { exact: true }).waitFor();
    await route('/admin/customers'); await login(email);
    await page.getByText('Khách hàng', { exact: true }).last().waitFor();
    await route('/account'); await button('Đăng xuất');
    await page.getByText('Đăng nhập để tiếp tục', { exact: true }).waitFor();
    await route('/admin/customers');
    await page.getByText('Khách hàng', { exact: true }).last().waitFor();
    console.log('Chrome admin: independent shopper/staff identities, both logout directions and safe return paths.');
    assert.deepEqual(errors, []);
    assert(requests.some(r => r.path.endsWith('/status') && r.status === 200));
    assert.equal(requests.filter(r => r.path.endsWith('/auth/browser/admin/login') && r.status === 403).length, 1);
    assert(!requests.some(r => r.status >= 400 && !isAnonymousRestore(r) && !(r.path.endsWith('/auth/browser/admin/login') && r.status === 403)), 'Unexpected API failure');
    console.log('PASS Chrome admin: CRUD, stock, order lifecycle, responsive separate login UI, isolated logout and customer gate.');
  } catch (error) {
    if (page) { fs.writeFileSync(path.join(output, 'failure-aria.txt'), await page.locator('body').ariaSnapshot()); await page.screenshot({ path: path.join(output, 'failure.png'), fullPage: true }); }
    throw error;
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
