const {chromium}=require('../.tools/browser/node_modules/playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../docs/qa');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 page.setDefaultTimeout(12000);
 const results=[],errors=[],external=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(!/^(http:\/\/127\.0\.0\.1:4173|blob:|data:)/.test(r.url()))external.push(r.url());});
 const button=name=>page.getByRole('button',{name,exact:true});
 const field=name=>page.getByRole('textbox',{name,exact:name!=='Tên gợi nhớ'});
 const fill=async(name,value)=>{await field(name).click();await page.waitForTimeout(120);await field(name).fill(value);await page.waitForTimeout(120);};
 const route=async url=>{await page.evaluate(url=>location.hash=url,url);await page.waitForTimeout(650);};
 const check=async(name,text)=>{let found=false;for(let i=0;i<15;i++){if((await page.locator('body').ariaSnapshot()).includes(text)){found=true;break;}await page.waitForTimeout(200);}if(!found)throw Error(name+': '+text);results.push(name);console.log('PASS '+name);};
 const capture=async name=>{
  const close=button('Đóng');if(await close.count()){await close.click();await page.waitForTimeout(250);}
  for(const width of [1440,375]){
   await page.setViewportSize({width,height:1000});await page.waitForTimeout(350);
   await page.mouse.wheel(0,-20000);await page.waitForTimeout(250);
   await page.screenshot({path:path.join(out,`screenshots/journeys-${name}-${width}.png`)});
  }
  await page.setViewportSize({width:1440,height:1000});await page.waitForTimeout(250);
 };
 try{
  await page.goto('http://127.0.0.1:4173/#/account/addresses');await page.waitForTimeout(1800);
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  await check('Address direct link offers login','Mở góc riêng của bạn');
  await route('/login');await field('Email').fill('journeys@example.com');await field('Mật khẩu demo').fill('password-demo');
  await button('Đăng nhập demo').click();await page.waitForTimeout(750);
  await button('Sổ địa chỉ').click();await page.waitForTimeout(500);
  await button('Thêm địa chỉ').click();await button('Lưu địa chỉ demo').click();
  await check('Address form validates','Nhập số điện thoại 10 chữ số');
  await page.waitForTimeout(300);
  for(const [label,value] of [['Tên gợi nhớ','Nhà'],['Người nhận','Nguyễn An'],['Điện thoại nhận hàng','0901234567'],['Địa chỉ nhận hàng','12 Nguyễn Huệ, TP.HCM']])await fill(label,value);
  await button('Lưu địa chỉ demo').click();await page.waitForTimeout(500);
  await check('First saved address is default','Mặc định');await capture('addresses');
  await button('Sửa Nhà').click();await page.waitForTimeout(350);await field('Địa chỉ nhận hàng').click();await field('Địa chỉ nhận hàng').fill('24 Nguyễn Huệ, TP.HCM');await page.waitForTimeout(200);await button('Lưu địa chỉ demo').click();await page.waitForTimeout(500);
  await check('Address edit persists','24 Nguyễn Huệ');
  await button('Phong cách của tôi').click();await page.waitForTimeout(400);
  await page.getByRole('button',{name:/^Size thường chọn/}).click();await page.getByRole('menuitem',{name:'L',exact:true}).click();
  await page.getByRole('button',{name:/^Màu ưu tiên/}).click();await page.getByRole('menuitem',{name:'Đen',exact:true}).click();
  await button('Lưu hồ sơ phong cách').click();await page.waitForTimeout(500);
  await check('Style profile saved','Đã lưu phong cách');await capture('style');
  await button('Lưu & mở Stylist').click();await page.waitForTimeout(700);
  await button('Dùng hồ sơ phong cách').click();await check('Stylist applies preferred color','Đen');
  await route('/products/nep-1');await button('Phối đồ cùng AI').click();await page.waitForTimeout(500);
  await field('Bạn đang tìm một outfit như thế nào?').click();await page.waitForTimeout(200);
  if(!(await field('Bạn đang tìm một outfit như thế nào?').inputValue()).includes('Gợi ý phối đồ cùng Áo cotton'))throw Error('Product context missing from editor');
  results.push('Product CTA carries garment context');
  await route('/products/nep-1');await button('M').click();await button('Thêm vào giỏ').click();await page.waitForTimeout(600);await page.keyboard.press('Escape');
  await route('/checkout');await button('Chọn địa chỉ đã lưu').click();await page.getByRole('menuitem',{name:'Nhà — Nguyễn An',exact:true}).click();
  await field('Họ và tên').click();await page.waitForTimeout(150);
  if(await field('Họ và tên').inputValue()!=='Nguyễn An')throw Error('Saved recipient not applied');
  await field('Địa chỉ đầy đủ').click();await page.waitForTimeout(150);
  if(await field('Địa chỉ đầy đủ').inputValue()!=='24 Nguyễn Huệ, TP.HCM')throw Error('Saved address not applied');
  results.push('Checkout applies edited saved address');
  const consent=page.getByRole('checkbox',{name:/Tôi hiểu đây/});await consent.click();await page.waitForTimeout(250);
  if(await consent.getAttribute('aria-checked')!=='true')throw Error('Checkout consent not checked');
  await button('Tạo đơn hàng demo').click();await page.waitForTimeout(1000);
  await route('/account/orders');await check('Customer order list includes new order','WRL-0001');await capture('orders');
  await field('Tìm mã đơn hoặc tên sản phẩm').fill('missing');await check('Order no-result state','Không có đơn phù hợp');
  await button('Xóa bộ lọc').click();await button('Xem chi tiết').click();await page.waitForTimeout(500);
  await check('Order detail has progress and recipient','Tiến trình đơn hàng');await capture('order-detail');
  await route('/virtual-try-on?product=nep-1');
  const chooser=page.waitForEvent('filechooser');await button('Chọn ảnh từ thiết bị').click();await(await chooser).setFiles(path.resolve(__dirname,'../apps/storefront/assets/images/shirt.jpg'));
  await page.waitForTimeout(500);await button('Chọn màu và size').click();await page.getByRole('menuitem',{name:'Trắng / M',exact:true}).click();
  await page.getByRole('checkbox',{name:/Tôi có quyền/}).click();await button('Tạo bản thử đồ demo').click();await page.waitForTimeout(2200);
  await route('/account/try-ons');await check('Try-On appears in history','Xem kết quả');await capture('history');
  await button('Xem kết quả').click();await page.waitForTimeout(500);await check('History opens saved result','Lịch sử thử đồ');
  await button('Lịch sử thử đồ').click();await page.waitForTimeout(450);await button('Xóa toàn bộ lịch sử').click();
  await button('Xác nhận').click();await page.waitForTimeout(350);await check('History clear empties registry','Chưa có lần thử đồ nào');
  await route('/account');await button('Đăng xuất').click();await route('/account/addresses');await check('Signout hides saved address book','Mở góc riêng của bạn');
 }catch(e){errors.push(e.stack);fs.writeFileSync(path.join(out,'journeys-failure.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(out,'screenshots/journeys-failure.png')});process.exitCode=1;}
 finally{fs.writeFileSync(path.join(out,'browser-account-journeys.json'),JSON.stringify({results,errors,externalRequests:external},null,2));console.log(JSON.stringify({results,errors,externalRequests:external},null,2));await browser.close();}
})();
