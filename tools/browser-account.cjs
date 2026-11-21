const {chromium}=require('../.tools/browser/node_modules/playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../docs/qa');
fs.mkdirSync(path.join(out,'screenshots'),{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:375,height:1000}});
 page.setDefaultTimeout(10000);
 const results=[],errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(!/^(http:\/\/127\.0\.0\.1:4173|blob:|data:)/.test(r.url()))external.push(r.url());});
 const button=name=>page.getByRole('button',{name,exact:true});
 const field=name=>page.getByRole('textbox',{name,exact:true});
 const check=async(name,text)=>{if(!(await page.locator('body').ariaSnapshot()).includes(text))throw Error(name+': '+text);results.push(name);console.log('PASS '+name);};
 try{
  await page.goto('http://127.0.0.1:4173/#/login');await page.waitForTimeout(1800);
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  await button('Đăng nhập demo').click();await page.waitForTimeout(200);
  await check('Auth validation', 'Nhập email hợp lệ');
  await field('Email').fill('demo@example.com');
  await field('Mật khẩu demo').fill('password-demo');
  await button('Hiện mật khẩu').click();
  await check('Password visibility toggle', 'Ẩn mật khẩu');
  await button('Kịch bản kiểm thử demo').click();
  await page.getByRole('switch',{name:'Mô phỏng lỗi tài khoản',exact:true}).click();
  await button('Đăng nhập demo').click();await page.waitForTimeout(650);
  await check('Auth simulated failure', 'Không kết nối được tài khoản demo');
  await page.screenshot({path:path.join(out,'screenshots/account-error-375.png')});
  await page.getByRole('switch',{name:'Mô phỏng lỗi tài khoản',exact:true}).click();
  await button('Đăng nhập demo').click();await page.waitForTimeout(650);
  await check('Auth retry opens account', 'Chào Khách Wearly.');
  await field('Họ và tên').fill('Khách thử Wearly');
  await field('Địa chỉ (không bắt buộc)').fill('123 Demo Street');
  await button('Lưu hồ sơ demo').click();await page.waitForTimeout(650);
  await check('Profile saved through repository', 'Chào Khách thử Wearly.');
  await page.screenshot({path:path.join(out,'screenshots/account-profile-375.png')});
  await button('Đăng xuất').click();await page.waitForTimeout(250);
  await check('Sign out clears session', 'Mở phiên tài khoản demo');
  await page.evaluate(()=>location.hash='/forgot-password');await page.waitForTimeout(350);
  await field('Email').fill('demo@example.com');
  await button('Gửi hướng dẫn demo').click();await page.waitForTimeout(650);
  await check('Password reset is explicitly simulated', 'Không gửi email thật');
 }catch(e){errors.push(e.stack);fs.writeFileSync(path.join(out,'account-failure.txt'),await page.locator('body').ariaSnapshot());process.exitCode=1;}
 finally{fs.writeFileSync(path.join(out,'browser-account.json'),JSON.stringify({results,errors,externalRequests:external},null,2));console.log(JSON.stringify({results,errors,externalRequests:external},null,2));await browser.close();}
})();
