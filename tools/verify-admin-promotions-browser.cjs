// Local Chrome acceptance; temporary database fixtures are always cleaned up.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {chromium}=require('../.tools/browser/node_modules/playwright');
const argon2=require('../backend/node_modules/argon2');
const {localDatabase}=require('./seed-customer-account.cjs');
const base=process.env.ADMIN_TEST_BASE||'http://localhost:8080';
if(!/^http:\/\/localhost:(8080|5173)$/.test(base))throw Error('Local frontend required');
const output=path.resolve(__dirname,'../.tools/promotions-admin-acceptance');
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const db=localDatabase(),marker='PQA'+randomUUID().replaceAll('-','').slice(0,8).toUpperCase(),password=randomUUID()+'-Aa1';
  const report={passed:[],errors:[],unexpectedResponses:[]},ids=[],orders=[];
  let browser,page,staff,allowConflict=false;
  const newCode=marker+'_NEW';
  try{
    staff=await db.user.create({data:{email:marker.toLowerCase()+'@example.test',username:marker.toLowerCase(),name:'Kiểm thử quản trị khuyến mãi',passwordHash:await argon2.hash(password),role:'ADMIN',active:true}});
    for(let i=0;i<23;i++)ids.push((await db.coupon.create({data:{code:marker+'_'+String(i).padStart(2,'0'),kind:i===2?'PERCENT':'FIXED',amount:i===2?'15':'50000',active:i!==1,usageLimit:i===4?1:10,startsAt:i===2?new Date(Date.now()+86400000):null,expiresAt:i===3?new Date(Date.now()-60000):null}})).id);
    for(let i=0;i<2;i++){
      const order=await db.order.create({data:{userId:staff.id,idempotencyKey:randomUUID(),requestHash:marker,status:i===0?'PENDING':'CANCELLED',addressSnapshot:{recipient:'QA',phone:'0900000000',address:'QA'},subtotal:'300000',discount:'50000',couponCode:marker+'_04',shipping:'30000',total:'280000'}});orders.push(order.id);
      await db.couponRedemption.create({data:{couponId:ids[4],orderId:order.id,userId:staff.id,discount:'50000',releasedAt:i===0?null:new Date()}});
    }
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--host-resolver-rules=MAP localhost 127.0.0.1']});
    const context=await browser.newContext({viewport:{width:1440,height:1050},timezoneId:'Asia/Bangkok',reducedMotion:'reduce'});
    page=await context.newPage();page.setDefaultTimeout(18000);
    page.on('pageerror',e=>report.errors.push(e.message));
    page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))report.errors.push(m.text());});
    page.on('response',r=>{if(/\/api\/v1\/admin\//.test(r.url())&&r.status()>=400&&!(allowConflict&&r.status()===409))report.unexpectedResponses.push({path:new URL(r.url()).pathname,status:r.status()});});
    const snapshot=()=>page.locator('body').ariaSnapshot();
    const button=name=>page.getByRole('button',{name,exact:typeof name==='string'});
    const passed=text=>{report.passed.push(text);console.log(text);};
    async function contains(text){for(let i=0;i<150;i++){if((await snapshot()).includes(text))return;await page.waitForTimeout(100);}throw Error('Missing UI: '+text);}
    async function semantics(){await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder,flt-semantics'),null,{timeout:45000});await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<70;i++){const box=await node.boundingBox(),v=page.viewportSize();if(box&&box.y>=20&&box.y+box.height<v.height-10)return;await page.mouse.move(v.width*.5,v.height*.5);await page.mouse.wheel(0,box?.y<20?-300:300);await page.waitForTimeout(80);}throw Error('Control outside viewport: '+node);}
    async function click(name){const node=button(name);await reveal(node);await node.click();await page.waitForTimeout(250);}
    async function fill(label,value){const node=page.getByRole('textbox',{name:new RegExp('^'+label.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))});await reveal(node);await node.click();await page.waitForTimeout(100);await node.fill(value);await page.waitForTimeout(100);}
    async function select(label,option){const node=button(new RegExp('^'+label+'\\s')).last();await reveal(node);await node.click();await page.getByRole('menu').last().hover();await page.mouse.wheel(0,-10000);await page.waitForTimeout(200);await page.getByRole('menuitem',{name:option,exact:true}).click();await page.waitForTimeout(250);}
    async function route(target,text){await page.evaluate(v=>location.hash='#'+v,target);await page.waitForTimeout(300);await contains(text);}
    async function capture(name){await page.mouse.move(page.viewportSize().width*.75,500);await page.mouse.wheel(0,-20000);await page.waitForTimeout(300);await page.screenshot({path:path.join(output,name+'.png')});fs.writeFileSync(path.join(output,name+'.txt'),await snapshot());}

    await page.goto(base+'/#/admin/promotions');await semantics();await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập',marker);await fill('Mật khẩu',password);await click('Đăng nhập quản trị');
    await contains('Tìm kiếm khuyến mãi');await fill('Tìm kiếm khuyến mãi',marker.toLowerCase());await click('Tìm kiếm');await contains('23 khuyến mãi phù hợp bộ lọc');
    await click('Trang sau');await contains('Trang 2/3');await page.reload();await semantics();await contains('Trang 2/3');
    for(const [status,total] of [['Đã tắt',1],['Sắp bắt đầu',1],['Hết hạn',1],['Hết lượt',1],['Đang áp dụng',19]]){await select('Trạng thái',status);await contains(total+' khuyến mãi phù hợp bộ lọc');}
    await select('Trạng thái','Tất cả trạng thái');await select('Loại giảm giá','Phần trăm');await contains('1 khuyến mãi phù hợp bộ lọc');await select('Loại giảm giá','Tất cả loại');
    await fill('Tìm kiếm khuyến mãi',marker+'_00');await click('Tìm kiếm');await contains('1 khuyến mãi phù hợp bộ lọc');await capture('list-desktop');
    passed('Real login, case-insensitive search, all lifecycle filters, discount type and persistent URL pagination');
    await click('Thêm khuyến mãi');await select('Cách áp dụng','Khách nhập mã');await click('Lưu thay đổi');await contains('Dùng 3–32');
    await fill('Mã khuyến mãi',marker+'_00');await select('Loại giảm giá','Phần trăm');await fill('Giá trị giảm','101');await click('Lưu thay đổi');await contains('Tối đa 100.');
    await fill('Giá trị giảm','15');await fill('Giá sản phẩm tối thiểu (VND)','250000');await fill('Giảm tối đa (VND, tùy chọn)','100000');
    await fill('Tổng lượt tối đa (tùy chọn)','25');await fill('Lượt tối đa mỗi khách','2');
    await fill('Bắt đầu (UTC+7)','2090-12-02 10:30');await fill('Hết hạn (UTC+7)','2090-12-01 10:30');await click('Lưu thay đổi');await contains('Hết hạn phải sau ngày bắt đầu.');
    await fill('Hết hạn (UTC+7)','2090-12-03 10:30');allowConflict=true;await click('Lưu thay đổi');await contains('Mã khuyến mãi đã tồn tại.');
    await fill('Mã khuyến mãi',newCode.toLowerCase());await click('Lưu thay đổi');await contains('Đã thêm mã khuyến mãi.');allowConflict=false;
    let created=await db.coupon.findUniqueOrThrow({where:{code:newCode}});ids.push(created.id);
    assert.equal(created.active,false);assert.equal(created.kind,'PERCENT');assert.equal(created.amount.toString(),'15');assert.equal(created.startsAt.toISOString(),'2090-12-02T03:30:00.000Z');
    await route('/admin/promotions/'+created.id,'Chi tiết khuyến mãi');await click('Bật mã');await click('Xác nhận');await contains('Sắp bắt đầu');
    await click('Sửa mã khuyến mãi');await fill('Bắt đầu (UTC+7)','');await fill('Hết hạn (UTC+7)','');await click('Lưu thay đổi');await contains('Đã cập nhật mã khuyến mãi.');await contains('Đang áp dụng');
    await click('Sao chép mã');await contains('Đã sao chép mã.');
    passed('Percentage/date validation, duplicate correction, UTC+7 persistence, draft creation, scheduled activation and editing');
    for(const width of [1440,768,375]){
      await page.setViewportSize({width,height:1000});await route('/admin/promotions?q='+newCode,'1 khuyến mãi phù hợp bộ lọc');await capture('list-'+width);
      await click('Xem chi tiết');await contains('Chi tiết khuyến mãi');await capture('detail-'+width);await click('Sửa mã khuyến mãi');await capture('editor-'+width);await click('Đóng');
    }
    passed('List, detail and editor render without overflow at desktop, tablet and mobile sizes');
    await click('Sửa mã khuyến mãi');await db.coupon.update({where:{id:created.id},data:{amount:'20',version:{increment:1}}});
    await fill('Giá trị giảm','25');allowConflict=true;await click('Lưu thay đổi');await contains('Dữ liệu đã thay đổi');await click('Tải lại dữ liệu');allowConflict=false;await contains('Giảm 20%');
    await click('Tắt mã');await click('Xác nhận');await contains('Đã tắt mã khuyến mãi.');
    assert.equal((await db.coupon.findUniqueOrThrow({where:{id:created.id}})).active,false);
    await route('/admin/promotions/'+ids[4],'Chi tiết khuyến mãi');await contains('1 lượt đang tính · 1 lượt đã trả lại');await contains('Tổng giảm của lượt đang tính: 50.000 ₫');await contains('Đã trả lượt');
    assert.equal(await button('Xóa mã khuyến mãi').isDisabled(),true);await capture('redemption-history');
    passed('Version conflict cannot overwrite another edit; real redemption totals distinguish released usage and prevent historical deletion');
    await route('/admin/promotions/'+created.id+'?from='+encodeURIComponent('/admin/promotions?q='+marker+'&status=inactive'),'Chi tiết khuyến mãi');
    await click('Xóa mã khuyến mãi');await click('Đóng');assert.ok(await db.coupon.findUnique({where:{id:created.id}}));
    await click('Xóa mã khuyến mãi');await click('Xác nhận xóa');await contains('Quản lý khuyến mãi');await contains('Đã xóa mã khuyến mãi.');
    assert.equal(new URL(page.url().split('#')[1],base).searchParams.get('status'),'inactive');assert.equal(await db.coupon.findUnique({where:{id:created.id}}),null);
    assert.equal(await db.adminAuditEvent.count({where:{targetId:created.id,action:'PROMOTION_DELETED'}}),1);
    assert.equal(await db.order.count({where:{id:{in:orders}}}),2);
    passed('Mobile delete confirmation/cancellation, return filters and atomic audit; existing orders remain intact');
    assert.deepEqual(report.errors,[]);assert.deepEqual(report.unexpectedResponses,[]);
  }catch(e){report.failure=e.message;if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));}throw e;}
  finally{
    await browser?.close();
    try{
      if(staff)await db.adminAuditEvent.deleteMany({where:{actorId:staff.id}});
      await db.couponRedemption.deleteMany({where:{couponId:{in:ids}}});
      await db.order.deleteMany({where:{id:{in:orders}}});
      await db.coupon.deleteMany({where:{code:{startsWith:marker}}});
      if(staff)await db.user.delete({where:{id:staff.id}});
      report.cleaned=true;
    }finally{await db.$disconnect();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));}
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
