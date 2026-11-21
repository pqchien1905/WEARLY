const { chromium } = require('../.tools/browser/node_modules/playwright');
const fs = require('fs'), path = require('path');
const out = path.resolve(__dirname, '../docs/qa');
fs.mkdirSync(path.join(out,'screenshots'),{recursive:true});
(async () => {
  const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const results = [], errors = [], externalRequests = [];
  page.setDefaultTimeout(12000);
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', r => {
    if (!/^(http:\/\/127\.0\.0\.1:4173|blob:|data:)/.test(r.url())) externalRequests.push(r.url());
  });
  const button = name => page.getByRole('button', { name, exact: true });
  const route = async url => {
    await page.evaluate(url => location.hash = url, url);
    await page.waitForTimeout(600);
  };
  const shot = async name => {
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(out, 'screenshots', `polish-${name}.png`) });
  };
  const check = async (label, expected) => {
    const snapshot = await page.locator('body').ariaSnapshot();
    if (!snapshot.includes(expected)) throw Error(`${label}: missing ${expected}`);
    results.push(label);
    console.log('PASS ' + label);
  };
  try {
    await page.goto('http://127.0.0.1:4173/#/products/nep-1');
    await page.waitForTimeout(1800);
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await button('M').click();
    await button('Thêm vào giỏ').click();
    await shot('cart-drawer-1440');
    await check('Animated drawer exposes selected variant', 'Trắng / M');
    await page.keyboard.press('Escape');
    for (const width of [375, 1440, 1920]) {
      await page.setViewportSize({ width, height: 1000 });
      await route('/cart');
      await check(`Populated cart at ${width}px`, 'Tóm tắt đơn hàng');
      await shot(`cart-${width}`);
      await route('/checkout');
      await check(`Populated checkout at ${width}px`, 'Tạo đơn hàng demo');
      await shot(`checkout-${width}`);
      if (width === 375) {
        await button('Tạo đơn hàng demo').scrollIntoViewIfNeeded();
        await shot('checkout-summary-375');
      }
    }
    await route('/');
    await button('Design system').scrollIntoViewIfNeeded();
    await shot('footer-1920');
    await check('Wide footer retains working newsletter field', 'Email của bạn');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.evaluate(async () => {
      for (const route of ['/shop', '/products/nep-1', '/login', '/shop']) {
        location.hash = route;
        await new Promise(resolve => setTimeout(resolve, 40));
      }
    });
    await page.waitForTimeout(600);
    await check('Reduced-motion rapid navigation remains usable', 'Tủ đồ của bạn.');
    await button('Chọn size Áo cotton không tay Essential').click();
    await button('M').click();
    await button('Thêm vào giỏ').click();
    await page.waitForTimeout(300);
    await check('Reduced-motion drawer remains interactive', 'Tóm tắt đơn hàng');
    await page.keyboard.press('Escape');
    await check('Escape restores storefront after reduced-motion drawer', 'Tủ đồ của bạn.');
  } catch (e) {
    errors.push(e.stack);
    await shot('browser-failure');
    process.exitCode = 1;
  } finally {
    const report = { results, errors, externalRequests };
    fs.writeFileSync(path.join(out, 'browser-polish.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
    await browser.close();
  }
})();
