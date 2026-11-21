const {chromium}=require('../.tools/browser/node_modules/playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../docs/qa');
fs.mkdirSync(path.join(out,'screenshots'),{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:375,height:1000}});
 page.setDefaultTimeout(12000);
 const results=[],errors=[],externalRequests=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('request',r=>{if(!/^(http:\/\/127\.0\.0\.1:4173|data:|blob:)/.test(r.url()))externalRequests.push(r.url());});
 const button=name=>page.getByRole('button',{name,exact:true});
 const snapshot=()=>page.locator('body').ariaSnapshot();
 // Flutter publishes expanded semantics after its animation frame. Wait for
 // the actual result instead of asserting in the click's first microtask.
 const check=async(name,text)=>{
  const deadline=Date.now()+3000;
  while(!(await snapshot()).includes(text)) {
   if(Date.now()>deadline)throw Error(name+': missing '+text);
   await page.waitForTimeout(50);
  }
  results.push(name);console.log('PASS '+name);
 };
 const route=async p=>{await page.evaluate(p=>location.hash=p,p);await page.waitForTimeout(650);};
 const shot=async name=>{await page.waitForTimeout(350);await page.screenshot({path:path.join(out,'screenshots',name+'-375.png')});};
 try {
  await page.goto('http://127.0.0.1:4173/#/shop');await page.waitForTimeout(1800);
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  await button('Bộ lọc').click();
  await page.getByRole('checkbox',{name:'M',exact:true}).click();
  await page.getByRole('checkbox',{name:'Tím',exact:true}).click();
  if(page.url().includes('size='))throw Error('Draft changed route');
  await shot('filter-draft');
  await button('Xem kết quả').click();await page.waitForTimeout(650);
  const query=new URLSearchParams(page.url().split('?')[1]);
  if(query.get('size')!=='M'||query.get('color')!=='Tím')throw Error('Filters not applied together');
  await check('Mobile multi-filter apply', 'Đầm ren tay dài Essential');
  await button('Bộ lọc').click();await page.getByRole('checkbox',{name:'L',exact:true}).click();await button('Đóng bộ lọc').click();
  if(!page.url().includes('size=M'))throw Error('Dismiss committed changes');results.push('Filter dismiss preserves query');
  await route('/shop');
  await button('Chọn size Áo cotton không tay Essential').click();
  await page.getByRole('checkbox',{name:'Đen',exact:true}).click();
  await button('M').click();await shot('quick-add');
  await button('Thêm vào giỏ').click();await page.waitForTimeout(600);
  await check('Quick add selected variant', 'Đen / M');
  if(!page.url().includes('/shop'))throw Error('Quick add left catalog');
  await page.keyboard.press('Escape');
  await route('/products/nep-1');await page.getByRole('group',{name:'Đen Màu Đen',exact:true}).getByRole('button').click();
  await check('Missing color image disclosure','Chưa có ảnh màu Đen');
  await route('/contact');await button('Gửi yêu cầu demo').click();
  await check('Contact validation','Nhập email hợp lệ');
  for(const [name,value] of [['Tên của bạn','Khách demo'],['Email liên hệ','demo@example.com'],['Nội dung cần hỗ trợ','Tôi cần xem bảng số đo.']])await page.getByRole('textbox',{name,exact:true}).fill(value);
  await button('Gửi yêu cầu demo').click();await page.waitForTimeout(250);
  await check('Contact local success','Đã hoàn tất yêu cầu mô phỏng');await shot('contact-success');
  await route('/faq');await button('Ảnh của tôi có được tải lên mạng không?').click();
  await check('FAQ expands privacy answer','Không. Ảnh nằm trong bộ nhớ');
  await route('/collections/everyday');await check('Collection detail has curated products','Áo cotton không tay Essential');
  await route('/admin/products');await check('Admin mobile exposes price','Từ 490.000');await shot('admin-product-cards');
  await route('/virtual-try-on?product=nep-1');
  await button('Chọn màu và size').click();await page.getByRole('menuitem',{name:'Trắng / M',exact:true}).click();
  const chooser=page.waitForEvent('filechooser');await button('Chọn ảnh từ thiết bị').click();await (await chooser).setFiles(path.resolve(__dirname,'../frontend/assets/images/shirt.jpg'));await page.waitForTimeout(600);
  await page.getByRole('checkbox',{name:/Tôi có quyền/}).click();await button('Tạo bản thử đồ demo').click();await page.waitForTimeout(2300);
  await button('Xem trang kết quả').click();await page.waitForTimeout(450);
  if(!page.url().includes('/virtual-try-on/tryon-'))throw Error('Missing result URL');
  await check('Completed result route retains metadata','Biến thể: WRL-1-MAIN-M');
  if((await snapshot()).includes('Ảnh đầu vào của bạn, chưa xử lý'))throw Error('Private input remained on result route');
  await shot('tryon-session-result');
  await button('Xóa kết quả demo').click();await page.waitForTimeout(200);
  await check('Result deletion invalidates link','Phiên thử đồ không còn ở đây');
 } catch(e) {errors.push(e.stack);fs.writeFileSync(path.join(out,'refinement-browser-failure.txt'),await snapshot());await shot('refinement-browser-failure');process.exitCode=1;}
 finally {const report={results,errors,externalRequests};fs.writeFileSync(path.join(out,'browser-refinement.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));await browser.close();}
})();
