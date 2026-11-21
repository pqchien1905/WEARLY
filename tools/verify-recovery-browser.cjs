const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
module.exports = async function verify({ root, email, password, nextPassword, getCode, url, adminUsername }) {
  const { chromium } = require(path.join(root, '.tools/browser/node_modules/playwright'));
  const web = path.join(root, 'frontend/build/web'), output = path.join(root, '.tools/api-recovery-verification');
  fs.mkdirSync(output, { recursive: true });
  const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.jpg': 'image/jpeg', '.png': 'image/png', '.ttf': 'font/ttf' };
  const server = http.createServer((req, res) => {
    let pathname;
    try { pathname = decodeURIComponent(req.url.split('?')[0]); } catch { res.writeHead(400).end(); return; }
    if (pathname.includes('\0')) { res.writeHead(400).end(); return; }
    const file = path.resolve(web, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!file.startsWith(web + path.sep)) { res.writeHead(403).end(); return; }
    fs.readFile(file, (error, data) => { res.writeHead(error ? 404 : 200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); res.end(error ? 'Not found' : data); });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(4183, '127.0.0.1', resolve); });
  let browser, page;
  let stage = 'start';
  const errors = [], requests = [];
  try {
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', () => errors.push('Browser runtime error'));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text())) errors.push('Flutter runtime error'); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder, flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 28; i++) {
        const box = await node.boundingBox(), viewport = page.viewportSize();
        if (box && box.y >= 125 && box.y + box.height <= viewport.height - 35) return;
        await page.mouse.move(viewport.width * .8, viewport.height * .7);
        await page.mouse.wheel(0, box && box.y < 125 ? -300 : 300); await page.waitForTimeout(150);
      }
      throw new Error('Cannot reveal recovery control');
    }
    async function field(name, value) {
      const node = textbox(name);
      await reveal(node); await node.click(); await page.waitForTimeout(150);
      // Flutter replaces the semantic textbox with its active editing element.
      await page.keyboard.press('Control+A'); await page.keyboard.insertText(value);
      await page.waitForTimeout(150);
    }
    function textbox(name) {
      // Focused Flutter fields include their placeholder/helper in the label.
      return page.getByRole('textbox', { name: new RegExp('^' + name + '(?:\\s+(?:ban@example\\.com|000000))?$') });
    }
    async function button(name) {
      const node = page.getByRole('button', { name, exact: true }).last();
      await reveal(node); await node.click(); await page.mouse.move(12, 125); await page.waitForTimeout(300);
    }
    await page.goto('http://127.0.0.1:4183/#/admin/login'); await semantics();
    stage = 'admin-login';
    await field('Tên đăng nhập', adminUsername); await field('Mật khẩu', password); await button('Đăng nhập quản trị');
    await page.waitForURL('**/#/admin');
    // SPA navigation keeps the live admin state, so clearing it during customer
    // recovery cannot be hidden by a page reload/cookie restoration.
    await page.evaluate(() => { location.hash = '/forgot-password'; });
    stage = 'enter-email';
    await field('Email', email);
    stage = 'request-code';
    await button('Gửi mã xác nhận');
    await textbox('Mã xác nhận').waitFor();
    await page.screenshot({ path: path.join(output, 'request-desktop.png') });
    stage = 'receive-local-code';
    const code = await getCode();
    assert.match(code, /^\d{6}$/);
    stage = 'verify-code';
    await field('Mã xác nhận', code); await button('Xác nhận mã');
    await textbox('Mật khẩu mới').waitFor();
    assert.equal(new URL(page.url()).hash, '#/forgot-password', 'Recovery should remain on its original page');
    assert(!(await page.locator('body').ariaSnapshot()).includes('token='), 'Token leaked to semantics');
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await field('Mật khẩu mới', nextPassword); await field('Nhập lại mật khẩu mới', nextPassword);
    await page.screenshot({ path: path.join(output, 'reset-mobile.png') });
    stage = 'submit-reset';
    await button('Lưu mật khẩu mới');
    await page.getByText('Mật khẩu đã được thay đổi', { exact: true }).waitFor();
    stage = 'preserve-admin-session';
    await page.evaluate(() => { location.hash = '/admin'; });
    await page.getByText('Một góc nhìn toàn cảnh.', { exact: true }).waitFor();
    assert.equal(new URL(page.url()).hash, '#/admin');
    assert.equal(requests.filter(r => r.path.endsWith('/auth/browser/admin/login')).length, 1, 'Customer recovery must preserve the current admin session');
    await page.evaluate(() => { location.hash = '/login'; });
    stage = 'login-new-password';
    await field('Email', email); await field('Mật khẩu', nextPassword); await button('Đăng nhập');
    await page.waitForURL('**/#/account');
    const old = await fetch(url + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
    assert.equal(old.status, 401, 'Old password remained valid');
    stage = 'reject-used-code';
    await page.goto('http://127.0.0.1:4183/#/forgot-password'); await semantics();
    await field('Email', email); await button('Tôi đã có mã xác nhận');
    await field('Mã xác nhận', code); await button('Xác nhận mã');
    await page.getByText(/Mã không đúng, đã hết hạn/).first().waitFor();
    await page.reload(); await semantics();
    await textbox('Email').waitFor();
    assert.equal(await textbox('Mật khẩu mới').count(), 0);
    assert.equal(requests.filter(r => r.path.endsWith('/auth/reset-password') && r.status === 200).length, 1);
    assert.equal(requests.filter(r => r.path.endsWith('/auth/verify-reset-code') && r.status === 400).length, 1);
    assert.deepEqual(errors, []);
    console.log('PASS Chrome recovery: SMTP code, 375px form, new customer login, one-use code, reload and independent administrator password/session.');
  } catch (error) {
    if (['start', 'enter-email', 'request-code'].includes(stage)) {
      await page?.screenshot({ path: path.join(output, 'failure.png') });
      console.error('Recovery test error type:', error.name);
      console.error('Available textbox labels:', await page.getByRole('textbox').evaluateAll(nodes => nodes.map(node => node.getAttribute('aria-label'))));
    }
    // Never persist a URL, mail body, password field contents or raw token on failure.
    throw new Error('Recovery browser verification failed at '+stage+'; inspect sanitized request evidence.');
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
