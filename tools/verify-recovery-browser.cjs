const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
module.exports = async function verify({ root, email, password, nextPassword, getLink, url }) {
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
  const errors = [], requests = [];
  try {
    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
    page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', () => errors.push('Browser runtime error'));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text())) errors.push('Flutter runtime error'); });
    page.on('response', r => { if (r.url().includes('/api/v1/')) requests.push({ path: new URL(r.url()).pathname, status: r.status(), method: r.request().method() }); });
    async function semantics() { await page.waitForTimeout(700); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); }
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
      const node = page.getByRole('textbox', { name, exact: true });
      await reveal(node); await node.click(); await page.waitForTimeout(150); await node.fill(value); await page.waitForTimeout(150);
    }
    async function button(name) {
      const node = page.getByRole('button', { name, exact: true }).last();
      await reveal(node); await node.click(); await page.mouse.move(12, 125); await page.waitForTimeout(300);
    }
    await page.goto('http://127.0.0.1:4183/#/forgot-password'); await semantics();
    await field('Email', email); await button('Gửi liên kết khôi phục');
    await page.getByText(/Đã tiếp nhận yêu cầu/).waitFor();
    await page.screenshot({ path: path.join(output, 'request-desktop.png') });
    const link = await getLink();
    await page.goto(link); await semantics();
    await page.getByRole('textbox', { name: 'Mật khẩu mới', exact: true }).waitFor();
    assert.equal(new URL(page.url()).hash, '#/reset-password', 'Reset URL was not scrubbed');
    assert(!(await page.locator('body').ariaSnapshot()).includes('token='), 'Token leaked to semantics');
    await page.setViewportSize({ width: 375, height: 812 }); await page.waitForTimeout(400);
    await field('Mật khẩu mới', nextPassword); await field('Nhập lại mật khẩu mới', nextPassword);
    await page.screenshot({ path: path.join(output, 'reset-mobile.png') });
    await button('Đặt lại mật khẩu');
    await page.getByText('Mật khẩu đã được thay đổi', { exact: true }).waitFor();
    await button('Đăng nhập'); await field('Email', email); await field('Mật khẩu', nextPassword); await button('Đăng nhập');
    await page.waitForURL('**/#/account');
    const old = await fetch(url + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
    assert.equal(old.status, 401, 'Old password remained valid');
    await page.goto(link); await semantics();
    await field('Mật khẩu mới', nextPassword); await field('Nhập lại mật khẩu mới', nextPassword); await button('Đặt lại mật khẩu');
    await page.getByText('Liên kết không còn hiệu lực', { exact: true }).waitFor();
    await page.reload(); await semantics();
    await page.getByText('Liên kết không còn hiệu lực', { exact: true }).waitFor();
    assert.equal(requests.filter(r => r.path.endsWith('/auth/reset-password') && r.status === 200).length, 1);
    assert.equal(requests.filter(r => r.path.endsWith('/auth/reset-password') && r.status === 400).length, 1);
    assert.deepEqual(errors, []);
    console.log('PASS Chrome recovery: actual SMTP link, clean URL, 375px form, new login, old password/session rejection, one-use link and reload.');
  } catch {
    // Never persist a URL, mail body, password field contents or raw token on failure.
    throw new Error('Recovery browser verification failed; inspect sanitized request evidence.');
  } finally {
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ errors, requests }, null, 2));
    await browser?.close(); await new Promise(resolve => server.close(resolve));
  }
};
