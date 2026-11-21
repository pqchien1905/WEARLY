// Mutations use one disposable customer; no existing customer addresses change.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { chromium } = require('../.tools/browser/node_modules/playwright');
const { customerSession } = require('./customer-account-session.cjs');
const { localDatabase } = require('./seed-customer-account.cjs');
const output = path.resolve(__dirname, '../.tools/addresses-workflow');
const origin = process.env.ADDRESSES_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, {recursive:true});
  const email = `addresses-${randomUUID().slice(0,8)}@example.invalid`;
  const report = {origin,passed:[],errors:[]};
  let browser, page, session, userId, release;
  const mutations = [];
  try {
    const register = await fetch('http://localhost:3000/api/v1/auth/register', {
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({name:'Khách kiểm thử địa chỉ',email,password:randomUUID()+'-Aa1'}),
    });
    assert.equal(register.status,201); userId = (await register.json()).user.id;
    session = await customerSession(email);
    browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',
      headless:true,args:['--host-resolver-rules=MAP localhost 127.0.0.1']});
    const context = await browser.newContext({viewport:{width:1440,height:1080},reducedMotion:'reduce'});
    await context.addCookies([session.cookie]); page = await context.newPage(); page.setDefaultTimeout(15000);
    page.on('pageerror',e=>report.errors.push(e.message));
    page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text());});
    page.on('request',r=>{if(['POST','PATCH','DELETE'].includes(r.method()) && /\/users\/me\/addresses/.test(r.url()))
      mutations.push({method:r.method(),path:new URL(r.url()).pathname,key:r.headers()['idempotency-key'],body:r.postData()});});
    const button = name => page.getByRole('button',{name,exact:true});
    const body = () => page.locator('body').ariaSnapshot();
    async function semantics() {
      await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function includes(value) {
      for(let i=0;i<150;i++){if((await body()).includes(value))return;await page.waitForTimeout(100);}
      throw Error('Missing content: '+value);
    }
    async function reveal(node) {
      await node.waitFor({state:'attached'});
      for(let i=0;i<45;i++){
        const b=await node.boundingBox(),h=page.viewportSize().height;
        const modal=await page.getByRole('dialog').count() || await page.getByRole('alertdialog').count();
        const inset=modal?24:page.viewportSize().width<600?235:180;
        if(b && b.y>=inset && b.y+b.height<h-12)return;
        await page.mouse.move(page.viewportSize().width*.8,h*.7);
        await page.mouse.wheel(0,b?b.y-(inset+h-12-b.height)/2:250); await page.waitForTimeout(90);
      }
      throw Error('Cannot reveal control');
    }
    async function click(name){const n=button(name);await reveal(n);await n.click();await page.waitForTimeout(180);}
    async function fill(name,value){const n=page.getByRole('textbox',{name:new RegExp('^'+name)});await reveal(n);await n.click();await n.fill(value);await page.waitForTimeout(100);}
    async function top(){await page.mouse.move(page.viewportSize().width*.8,page.viewportSize().height*.7);await page.mouse.wheel(0,-100000);await page.waitForTimeout(180);}
    async function capture(name){await page.mouse.move(8,page.viewportSize().height-12);await page.waitForTimeout(150);await page.screenshot({path:path.join(output,name+'.png')});fs.writeFileSync(path.join(output,name+'.txt'),await body());}
    async function add(label, address){
      await click('Thêm địa chỉ');await includes('Địa chỉ mới');
      await fill('Tên gợi nhớ',label);await fill('Người nhận','Nguyễn An');
      await fill('Điện thoại nhận hàng','0901234567');await fill('Địa chỉ nhận hàng',address);
    }
    const list = () => session.request('users/me/addresses');
    await page.goto(origin+'/#/account/addresses');await semantics();await includes('Chưa có địa chỉ nhận hàng');
    await click('Thêm địa chỉ');await click('Lưu địa chỉ');await includes('Nhập số điện thoại 10 chữ số.');
    assert.equal(mutations.length,0);await click('Hủy');
    await add('Nhà','12 Nguyễn Huệ, Phường Sài Gòn, TP. Hồ Chí Minh');
    const rootRoute='**/users/me/addresses';
    await page.route(rootRoute,async route=>{
      if(route.request().method()!=='POST')return route.continue();
      const response=await route.fetch();assert.equal(response.status(),201);
      await route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:{code:'LOST_RESPONSE',message:'Chưa nhận được phản hồi lưu địa chỉ.'}})});
    });
    await click('Lưu địa chỉ');await includes('Thử lại yêu cầu này');
    assert.equal((await list()).length,1);await page.unroute(rootRoute);
    await click('Thử lại yêu cầu này');await includes('Đã lưu địa chỉ.');await includes('1 địa chỉ đã lưu');
    assert.equal((await list()).length,1);assert.equal(mutations[0].key,mutations[1].key);assert.equal(mutations[0].body,mutations[1].body);
    assert.equal((await list())[0].isDefault,true);
    report.passed.push('Validation blocks invalid requests; uncertain creation retries the same key without duplication');

    await add('Văn phòng','Tầng 12, số 128 Nguyễn Văn Cừ, Phường Trường Vinh, Nghệ An');
    await click('Lưu địa chỉ');await includes('2 địa chỉ đã lưu');
    const office=(await list()).find(a=>a.label==='Văn phòng');assert(office);
    await click('Sửa Văn phòng');assert(await button('Lưu địa chỉ').isDisabled());
    await fill('Người nhận','Bản nháp');await click('Hủy');await includes('Bỏ thay đổi chưa lưu?');
    await click('Tiếp tục nhập');await click('Hủy');await click('Bỏ thay đổi');
    assert.equal((await list()).find(a=>a.id===office.id).recipient,'Nguyễn An');
    report.passed.push('Unchanged edits disable save; discarding a draft leaves server data intact');

    await click('Sửa Văn phòng');await fill('Người nhận','Nguyễn Minh An');
    const officeRoute='**/users/me/addresses/'+office.id;
    await page.route(officeRoute,async route=>{if(route.request().method()!=='PATCH')return route.continue();await new Promise(resolve=>{release=resolve;});await route.continue();});
    await click('Lưu địa chỉ');await includes('Đang lưu địa chỉ…');assert(await button('Hủy').isDisabled());
    release();release=null;await includes('Đã lưu địa chỉ.');await page.unroute(officeRoute);
    await includes('Nguyễn Minh An');
    await click('Đặt làm mặc định');await includes('Đã đổi địa chỉ mặc định.');
    assert.equal((await list()).find(a=>a.isDefault).id,office.id);
    await page.reload();await semantics();await includes('Nguyễn Minh An');
    assert.equal((await list()).find(a=>a.isDefault).id,office.id);
    report.passed.push('Edits and default selection persist after reload; pending save locks repeated actions');

    await page.route(rootRoute,route=>route.request().method()==='GET'
      ? route.fulfill({status:503,contentType:'application/json',body:'{}'}):route.continue());
    await click('Tải lại');await includes('Chưa cập nhật được sổ địa chỉ');await includes('Nguyễn Minh An');
    assert(await button('Thêm địa chỉ').isDisabled());assert(await button('Sửa Văn phòng').isDisabled());
    await capture('refresh-error');await page.unroute(rootRoute);await click('Thử lại');
    await includes('2 địa chỉ đã lưu');assert(await button('Sửa Văn phòng').isEnabled());
    report.passed.push('Refresh error retains readable addresses and locks mutations until retry succeeds');

    for(const [width,height] of [[320,900],[375,900],[768,1024],[1440,1080],[2560,1200],[844,390]]){
      await page.setViewportSize({width,height});await top();await capture('width-'+width);
      await click('Sửa Văn phòng');await includes('Chỉnh sửa địa chỉ');await capture('editor-'+width);
      await click('Đóng địa chỉ');await includes('2 địa chỉ đã lưu');
    }
    report.passed.push('Address list and editor remain usable at 320–2560px and landscape');

    await page.setViewportSize({width:1440,height:1080});
    await click('Xóa Văn phòng');await includes('Địa chỉ còn lại được lưu sớm nhất sẽ trở thành mặc định.');
    await capture('delete-confirmation');await click('Giữ lại');assert.equal((await list()).length,2);
    const previousMutations=mutations.length;
    await click('Xóa Văn phòng');await click('Xác nhận');await includes('Đã xóa địa chỉ.');await includes('1 địa chỉ đã lưu');
    const remaining=await list();assert.equal(remaining[0].label,'Nhà');assert(remaining[0].isDefault);
    assert.deepEqual(mutations.slice(previousMutations).map(r=>r.method),['DELETE']);
    await click('Xóa Nhà');await click('Xác nhận');await includes('Chưa có địa chỉ nhận hàng');assert.equal((await list()).length,0);
    report.passed.push('Deleting default promotes the remaining address atomically; deleting the last shows empty state');
    assert.deepEqual(report.errors,[]);console.log(JSON.stringify(report,null,2));
  }catch(error){report.failure=String(error);if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await bodySafe(page));}throw error;
  }finally{
    release?.();await browser?.close();await session?.close();
    if(userId){const db=localDatabase();try{await db.user.deleteMany({where:{id:userId,email}});}finally{await db.$disconnect();}}
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
async function bodySafe(page){return page.locator('body').ariaSnapshot().catch(()=>'');}
