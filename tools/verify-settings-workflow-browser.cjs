// Local API acceptance. Only a disposable customer is changed or signed out.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {randomUUID}=require('node:crypto');
const {chromium}=require('../.tools/browser/node_modules/playwright');
const {customerSession}=require('./customer-account-session.cjs');
const {localDatabase}=require('./seed-customer-account.cjs');
const output=path.resolve(__dirname,'../.tools/settings-workflow');
const origin=process.env.SETTINGS_TEST_BASE||'http://localhost:8080';
if(!/^http:\/\/localhost:(8080|5173)$/.test(origin))throw Error('Local storefront required');

(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const email=`settings-${randomUUID().slice(0,8)}@example.invalid`;
  const report={origin,passed:[],errors:[]};
  let browser,page,session,userId,release;
  let reads=0,logouts=0,recoveryRequests=0;
  try{
    const registered=await fetch('http://localhost:3000/api/v1/auth/register',{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Khách kiểm thử cài đặt',email,password:randomUUID()+'-Aa1'}),
    });
    assert.equal(registered.status,201);userId=(await registered.json()).user.id;
    fs.writeFileSync(path.join(output,'fixture.json'),JSON.stringify({userId,email}));
    session=await customerSession(email);
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--host-resolver-rules=MAP localhost 127.0.0.1']});
    const context=await browser.newContext({viewport:{width:1440,height:1080},reducedMotion:'reduce',permissions:['clipboard-read','clipboard-write']});
    await context.addCookies([session.cookie]);page=await context.newPage();page.setDefaultTimeout(18000);
    page.on('pageerror',e=>report.errors.push(e.message));
    page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))report.errors.push(m.text());});
    page.on('request',r=>{if(r.url().endsWith('/users/me')&&r.method()==='GET')reads++;if(r.url().endsWith('/auth/browser/customer/logout'))logouts++;if(r.url().endsWith('/auth/forgot-password'))recoveryRequests++;});
    const button=name=>page.getByRole('button',{name,exact:typeof name==='string'});
    const body=()=>page.locator('body').ariaSnapshot();
    async function semantics(){await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder,flt-semantics'));await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function includes(text){for(let i=0;i<150;i++){if((await body()).includes(text))return;await page.waitForTimeout(100);}throw Error('Missing: '+text);}
    async function reveal(n){await n.waitFor({state:'attached'});for(let i=0;i<45;i++){
      const b=await n.boundingBox(),h=page.viewportSize().height,inset=page.viewportSize().width<600?235:180;
      if(b&&b.y>=inset&&b.y+b.height<h-12)return;
      await page.mouse.move(page.viewportSize().width*.8,h*.7);await page.mouse.wheel(0,b?b.y-(inset+h-12-b.height)/2:250);await page.waitForTimeout(90);
    }throw Error('Cannot reveal control');}
    async function click(name){const n=button(name);await reveal(n);await n.click();await page.waitForTimeout(180);}
    async function top(){await page.mouse.move(page.viewportSize().width*.8,page.viewportSize().height*.7);await page.mouse.wheel(0,-100000);await page.waitForTimeout(150);}
    async function capture(name){await page.mouse.move(8,page.viewportSize().height-12);await page.waitForTimeout(120);await page.screenshot({path:path.join(output,name+'.png')});fs.writeFileSync(path.join(output,name+'.txt'),await body());}
    async function settings(){await page.evaluate(()=>{location.hash='/account/settings';});await page.getByRole('heading',{name:'Cài đặt tài khoản',level:1,exact:true}).waitFor();await top();}
    await page.goto(origin+'/#/account/settings');await semantics();await includes('Chưa thêm số điện thoại');await includes(email);await capture('desktop');
    await click('Sao chép email');await includes('Đã sao chép email.');assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),email);
    await session.request('users/me',{method:'PATCH',body:{name:'Nguyễn Minh An',phone:'0901234567'}});
    await click('Tải lại thông tin');await includes('Đã cập nhật thông tin tài khoản.');await includes('0901234567');await includes('Nguyễn Minh An');
    report.passed.push('Accessible profile details, clipboard copy and fresh data from the real profile API');

    const profileRoute='**/api/v1/users/me';
    await page.route(profileRoute,r=>r.request().method()==='GET'?r.fulfill({status:503,contentType:'application/json',body:'{}'}):r.continue());
    await click('Tải lại thông tin');await includes('Chưa cập nhật được thông tin.');await includes('0901234567');await capture('refresh-error');
    await page.unroute(profileRoute);await click('Thử lại');await includes('Đã cập nhật thông tin tài khoản.');
    await page.route(profileRoute,async r=>{await new Promise(resolve=>{release=resolve;});await r.continue();});
    const before=reads;await click('Tải lại thông tin');await includes('Đang tải…');
    await page.setViewportSize({width:375,height:900});assert(await button('Đang tải…').isDisabled());
    release();release=null;await includes('Đã cập nhật thông tin tài khoản.');assert.equal(reads,before+1);await page.unroute(profileRoute);
    report.passed.push('Refresh error preserves profile; retry works; resize keeps one pending refresh');

    await page.setViewportSize({width:1440,height:1080});
    for(const [name,target] of [['Chỉnh sửa hồ sơ','/account'],[/^Địa chỉ nhận hàng /,'/account/addresses'],[/^Phong cách của tôi Lưu/,'/account/style'],[/^Quyền riêng tư Tìm/,'/privacy'],[/^Quản lý ảnh thử đồ /,'/account/try-ons']]){
      await click(name);assert.equal(new URL(page.url()).hash,'#'+target);await settings();
    }
    await click('Đổi mật khẩu');assert(page.url().includes('/forgot-password?from=account'));
    const emailField=page.getByRole('textbox',{name:'Email',exact:true});await reveal(emailField);await emailField.click();assert.equal(await emailField.inputValue(),email);
    await click('Trở về cài đặt tài khoản');assert.equal(recoveryRequests,0);
    report.passed.push('All settings links navigate correctly; password flow prefills email and returns without sending mail');

    for(const [width,height] of [[320,900],[375,900],[768,1024],[1440,1080],[2560,1200],[844,390]]){
      await page.setViewportSize({width,height});await top();await capture('width-'+width);
      if(height>600){const logout=button('Đăng xuất').last();await reveal(logout);await capture('session-'+width);}
    }
    report.passed.push('Profile, shortcuts and session controls fit 320–2560px and landscape');

    await page.setViewportSize({width:1440,height:1080});
    const logoutRoute='**/api/v1/auth/browser/customer/logout';
    await page.route(logoutRoute,r=>r.fulfill({status:503,contentType:'application/json',body:'{}'}));
    let logout=button('Đăng xuất').last();await reveal(logout);await logout.click();await includes('Chưa đăng xuất được. Kiểm tra kết nối và thử lại.');await includes(email);
    await capture('logout-error');await page.unroute(logoutRoute);
    await page.route(logoutRoute,async r=>{await new Promise(resolve=>{release=resolve;});await r.continue();});
    logout=button('Đăng xuất').last();await reveal(logout);await logout.click();await includes('Đang đăng xuất…');
    for(const n of await button('Đang đăng xuất…').all())assert(await n.isDisabled());
    await page.getByRole('button',{name:/^Tài khoản Chào/}).hover();
    await page.getByRole('heading',{name:'Tài khoản',level:2,exact:true}).waitFor();
    assert.equal(await button('Đang đăng xuất…').count(),3);
    for(const n of await button('Đang đăng xuất…').all())assert(await n.isDisabled());
    await page.keyboard.press('Escape');
    await page.setViewportSize({width:375,height:900});assert(await button('Đang đăng xuất…').last().isDisabled());
    release();release=null;await includes('Đăng nhập khách hàng');assert.equal(logouts,2);assert(new URL(page.url()).hash==='#/login');
    await page.unroute(logoutRoute);await page.reload();await semantics();await includes('Đăng nhập khách hàng');
    await page.evaluate(()=>{location.hash='/account/settings';});await includes('Đăng nhập để tiếp tục');assert(!(await body()).includes(email));
    report.passed.push('Logout failure remains retryable; all controls lock together; successful logout survives resize and reload');
    assert.equal(recoveryRequests,0);assert.deepEqual(report.errors,[]);
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
  }catch(e){
    report.failure=String(e);
    if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));}
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));throw e;
  }finally{
    release?.();await browser?.close();await session?.close();
    if(userId){const db=localDatabase();try{await db.user.deleteMany({where:{id:userId,email}});}finally{await db.$disconnect();}}
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
