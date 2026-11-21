// Real Chrome + Nest + PostgreSQL acceptance. All writes use the isolated *_test
// database; the running store's content is fingerprinted read-only and preserved.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {randomUUID,createHash}=require('node:crypto');
const {chromium}=require('../.tools/browser/node_modules/playwright');
const argon2=require('../backend/node_modules/argon2');
const {localDatabase}=require('./seed-customer-account.cjs');
const base=process.env.ADMIN_TEST_BASE||'http://localhost:8080';
if(!/^http:\/\/localhost:(8080|5173)$/.test(base))throw Error('Local frontend required');
require('../backend/test/setup-e2e-env.cjs');
process.env.CORS_ORIGINS=base;
process.env.JWT_ACCESS_SECRET='content-qa-access-'.repeat(4);
process.env.JWT_REFRESH_SECRET='content-qa-refresh-'.repeat(4);
const {NestFactory}=require('../backend/node_modules/@nestjs/core');
const {AppModule}=require('../backend/dist/app.module');
const {configureApp}=require('../backend/dist/bootstrap');
const {PrismaService}=require('../backend/dist/database/prisma.service');
const {ContentService}=require('../backend/dist/modules/content/content.service');
const {defaultStoreDetails}=require('../backend/dist/modules/content/store-details');
const output=path.resolve(__dirname,'../.tools/content-admin-acceptance');
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const report={passed:[],errors:[],unexpectedResponses:[],isolatedDatabase:true};
  const marker='content-qa-'+randomUUID().slice(0,8),password=randomUUID()+'-Aa1';
  const store=localDatabase();
  const fingerprint=async()=>createHash('sha256').update(JSON.stringify(await store.storeContent.findMany({orderBy:{key:'asc'}}))).digest('hex');
  const original=await fingerprint();
  let app,db,browser,page,staff,contentId,allowConflict=false;
  const title='Cảm hứng mùa thu '+marker,policy='Chính sách mới '+marker+' <script>window.__contentScriptRan=true</script>';
  try{
    app=await NestFactory.create(AppModule,{logger:false});configureApp(app);await app.listen(0,'127.0.0.1');db=app.get(PrismaService);
    assert.equal(await db.storeContent.count(),0,'Test singleton already exists; refusing to overwrite it');
    const api='http://localhost:'+app.getHttpServer().address().port+'/api/v1';
    staff=await db.user.create({data:{email:marker+'@example.test',username:marker,name:'Kiểm thử quản trị nội dung',passwordHash:await argon2.hash(password),role:'ADMIN',active:true}});
    const fixture=await db.storeContent.create({data:{key:'storefront',banner:'Bản nháp ban đầu',policy:'Chính sách nháp',details:{...defaultStoreDetails,name:'Wearly Test Studio'},version:3,publishedBanner:'Nội dung công khai ban đầu',publishedPolicy:'Chính sách công khai ban đầu',publishedDetails:{...defaultStoreDetails,name:'Wearly Test Studio'},publishedVersion:2,publishedAt:new Date()}});contentId=fixture.id;
    const publicContent=async()=>{const r=await fetch(api+'/content');assert.equal(r.status,200);return(await r.json()).content;};
    const initialPublic=await publicContent();
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--host-resolver-rules=MAP localhost 127.0.0.1']});
    const context=await browser.newContext({viewport:{width:1440,height:1050},timezoneId:'Asia/Bangkok',reducedMotion:'reduce'});
    await context.route('**/api/v1/**',async route=>{
      const url=new URL(route.request().url());
      if(url.hostname==='localhost'&&url.port==='3000'){url.port=String(app.getHttpServer().address().port);await route.continue({url:url.toString()});}
      else await route.continue();
    });
    page=await context.newPage();page.setDefaultTimeout(20000);
    page.on('pageerror',e=>report.errors.push(e.message));
    page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))report.errors.push(m.text());});
    page.on('response',r=>{if(/\/api\/v1\/admin\//.test(r.url())&&r.status()>=400&&!(allowConflict&&r.status()===409))report.unexpectedResponses.push({path:new URL(r.url()).pathname,status:r.status()});});
    const snapshot=()=>page.locator('body').ariaSnapshot();
    const button=name=>page.getByRole('button',{name,exact:typeof name==='string'});
    const passed=text=>{report.passed.push(text);console.log(text);};
    async function contains(text){for(let i=0;i<180;i++){if((await snapshot()).includes(text))return;await page.waitForTimeout(100);}throw Error('Missing UI: '+text);}
    async function semantics(){await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder,flt-semantics'),null,{timeout:45000});await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<70;i++){const box=await node.boundingBox(),v=page.viewportSize();if(box&&box.y>=85&&box.y+box.height<v.height-20)return;await page.mouse.move(v.width*.8,v.height*.7);await page.mouse.wheel(0,box?.y<85?-450:450);await page.waitForTimeout(80);}throw Error('Control outside viewport: '+node);}
    async function click(name){const node=button(name);await reveal(node);await node.click();await page.waitForTimeout(250);}
    async function fill(label,value){const node=page.getByRole('textbox',{name:new RegExp('^'+label.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))});await reveal(node);await node.click();await page.waitForTimeout(100);await node.fill(value);await page.waitForTimeout(100);}
    async function group(label){const node=page.getByRole('checkbox',{name:label,exact:true});await reveal(node);await node.click();await page.waitForTimeout(200);}
    async function route(target,text){await page.evaluate(v=>location.hash='#'+v,target);await page.waitForTimeout(300);await contains(text);}
    async function capture(name){await page.mouse.move(page.viewportSize().width*.75,500);await page.mouse.wheel(0,-20000);await page.waitForTimeout(300);await page.screenshot({path:path.join(output,name+'.png')});fs.writeFileSync(path.join(output,name+'.txt'),await snapshot());}

    await page.goto(base+'/#/admin/content');await semantics();await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập',marker);await fill('Mật khẩu',password);await click('Đăng nhập quản trị');await contains('Tiêu đề trang chủ');await capture('desktop-initial');
    await fill('Tiêu đề trang chủ',title);await click('Xem trước');await contains('Xem trước thay đổi chưa lưu');await contains(title);await click('Đóng xem trước');assert.deepEqual(await publicContent(),initialPublic);
    await click('Khuyến mãi');await contains('Rời trang khi chưa lưu?');await click('Tiếp tục chỉnh sửa');await contains('Nội dung cửa hàng');
    const unloadSeen=new Promise(resolve=>page.once('dialog',async d=>{assert.equal(d.type(),'beforeunload');await d.dismiss();resolve();}));
    await page.evaluate(()=>setTimeout(()=>location.reload(),0));await unloadSeen;await contains('Chưa lưu thay đổi');
    passed('Real login, live private preview, sidebar navigation confirmation and native reload protection');
    await group('Liên hệ');await fill('Email cửa hàng (không bắt buộc)','invalid');await group('Trang chủ');await click('Lưu bản nháp');await contains('Email không hợp lệ.');
    await fill('Email cửa hàng (không bắt buộc)','hello@example.test');await fill('Điện thoại (không bắt buộc)','0901234567');await group('Chính sách');await fill('Nội dung chính sách',policy);
    await click('Lưu bản nháp');await contains('Đã lưu bản nháp. Chưa xuất bản.');
    let saved=await db.storeContent.findUniqueOrThrow({where:{id:contentId}});assert.equal(saved.banner,title);assert.equal(saved.policy,policy);assert.equal(saved.details.email,'hello@example.test');assert.deepEqual(await publicContent(),initialPublic);
    await click('Xuất bản nội dung');await contains('Đang công khai');await contains('Bản chuẩn bị');await capture('publish-review');await click('Tiếp tục chỉnh sửa');assert.deepEqual(await publicContent(),initialPublic);
    await click('Xuất bản nội dung');await click('Xác nhận xuất bản');await contains('Đã xuất bản nội dung.');await contains('Đã đồng bộ với bản công khai');
    const published=await publicContent();assert.equal(published.banner,title);assert.equal(published.policy,policy);assert.equal(published.version,saved.version+1);
    await route('/shipping-returns','Giao hàng & đổi trả');await contains(policy);assert.equal(await page.evaluate(()=>window.__contentScriptRan),undefined);await capture('public-policy');
    passed('Hidden-group validation, draft privacy, exact-version publication review and real public policy rendered as plain text');
    await route('/admin/content','Nội dung cửa hàng');await contains('Tiêu đề trang chủ');await fill('Tiêu đề trang chủ','Bản nháp để khôi phục '+marker);await click('Lưu bản nháp');await contains('Đã lưu bản nháp. Chưa xuất bản.');
    await click('Khôi phục từ bản công khai');await click('Khôi phục bản nháp');await contains('Đã đồng bộ với bản công khai');assert.deepEqual(await publicContent(),published);
    assert.equal((await db.storeContent.findUniqueOrThrow({where:{id:contentId}})).banner,title);
    passed('Restore replaces the saved draft while preserving the public snapshot and publication timestamp');
    await fill('Tiêu đề trang chủ','Chỉnh sửa chưa lưu của tôi');
    const current=await db.storeContent.findUniqueOrThrow({where:{id:contentId}});
    await app.get(ContentService).save(staff.id,{expectedVersion:current.version,banner:'Nội dung từ phiên khác',policy:current.policy});
    allowConflict=true;await click('Lưu bản nháp');await contains('Nội dung đã thay đổi.');await click('Tải lại bản đã lưu');await click('Tải lại');allowConflict=false;await contains('Đã tải lại bản đã lưu.');
    const canonicalTitle=page.getByRole('textbox',{name:/^Tiêu đề trang chủ/});await reveal(canonicalTitle);await canonicalTitle.click();await page.waitForTimeout(150);
    assert.equal(await canonicalTitle.inputValue(),'Nội dung từ phiên khác');assert.deepEqual(await publicContent(),published);
    await click('Khôi phục từ bản công khai');await click('Khôi phục bản nháp');await contains('Đã đồng bộ với bản công khai');
    await click(/Nhật ký nội dung/);await contains('Người thao tác:');assert.ok(await db.adminAuditEvent.count({where:{targetId:contentId,action:'CONTENT_DRAFT_RESTORED'}}));
    passed('Concurrent updates cannot overwrite a newer revision; reload reconciles and history records saves, publication and restoration');
    for(const width of [1440,768,375]){
      await page.setViewportSize({width,height:1000});await group('Trang chủ');await capture('workspace-'+width);
      await group('Chính sách');await capture('policies-'+width);await click('Xem trước');await capture('preview-'+width);await click('Đóng xem trước');
    }
    passed('Workspace, policy editor and preview are usable at desktop, tablet and mobile widths');
    assert.deepEqual(report.errors,[]);assert.deepEqual(report.unexpectedResponses,[]);
  }catch(e){report.failure=e.message;if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));}throw e;}
  finally{
    await browser?.close();
    try{
      if(db&&staff)await db.adminAuditEvent.deleteMany({where:{actorId:staff.id}});
      if(db&&contentId)await db.storeContent.delete({where:{id:contentId}});
      if(db&&staff)await db.user.delete({where:{id:staff.id}});
      report.cleaned=true;report.storeContentPreserved=(await fingerprint())===original;
      assert.equal(report.storeContentPreserved,true,'Running store content changed during acceptance');
    }finally{await app?.close();await store.$disconnect();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));}
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
