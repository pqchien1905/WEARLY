// Real local API acceptance; all mutations belong to disposable fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {chromium} = require('../.tools/browser/node_modules/playwright');
const {customerSession} = require('./customer-account-session.cjs');
const {localDatabase} = require('./seed-customer-account.cjs');
const output = path.resolve(__dirname, '../.tools/wishlist-workflow');
const origin = process.env.WISHLIST_TEST_BASE || 'http://localhost:8080';
if (!/^http:\/\/localhost:(8080|5173)$/.test(origin)) throw Error('Local storefront required');

(async () => {
  fs.mkdirSync(output, {recursive:true});
  const db = localDatabase(), productIds = [], variantIds = [];
  const email = `wishlist-qa-${randomUUID().slice(0,8)}@example.invalid`;
  const report = {origin,passed:[],errors:[]};
  let browser, page, session, userId, release;
  let removes = 0, adds = 0;
  try {
    const registered = await fetch('http://localhost:3000/api/v1/auth/register', {
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({name:'Khách kiểm thử yêu thích',email,password:randomUUID()+'-Aa1'}),
    });
    assert.equal(registered.status,201); userId=(await registered.json()).user.id;
    const source = await db.product.findFirstOrThrow({where:{active:true},include:{images:true}});
    for(let i=0;i<13;i++) {
      const p=await db.product.create({data:{
        slug:`wishlist-qa-${randomUUID()}`,name:i===12?'Đầm lụa trắng kiểm thử':`Áo cotton kiểm thử ${i+1}`,
        description:'Sản phẩm kiểm thử tạm thời',material:i===12?'Lụa':'Cotton',style:'Tối giản',active:i!==1,
        categoryId:source.categoryId,brandId:source.brandId,
        images:{create:{url:source.images[0]?.url||'assets/images/shirt.jpg',alt:'Sản phẩm kiểm thử',position:0}},
        variants:{create:{sku:`WISH-QA-${randomUUID()}`,size:'M',color:'Trắng',colorHex:'#FFFFFF',price:String(490000+i*10000),inventory:{create:{quantity:i===2?0:12}}}},
      },include:{variants:true}});
      productIds.push(p.id);variantIds.push(p.variants[0].id);
    }
    await db.wishlistItem.createMany({data:productIds.map((productId,i)=>({userId,productId,createdAt:new Date(Date.now()-i*60000)}))});
    session=await customerSession(email);
    fs.writeFileSync(path.join(output,'fixture.json'),JSON.stringify({userId,productIds,variantIds}));
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--host-resolver-rules=MAP localhost 127.0.0.1']});
    const context=await browser.newContext({viewport:{width:1440,height:1080},reducedMotion:'reduce'});
    await context.addCookies([session.cookie]);page=await context.newPage();page.setDefaultTimeout(20000);
    page.on('pageerror',e=>report.errors.push(e.message));
    page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text()))report.errors.push(m.text());});
    page.on('request',r=>{if(r.method()==='DELETE'&&r.url().includes('/wishlist/'))removes++;if(r.method()==='POST'&&r.url().endsWith('/cart/items'))adds++;});
    const button=name=>page.getByRole('button',{name,exact:true});
    const body=()=>page.locator('body').ariaSnapshot();
    async function semantics(){await page.waitForFunction(()=>document.querySelector('flt-semantics-placeholder,flt-semantics'));await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function includes(value){for(let i=0;i<180;i++){if((await body()).includes(value))return;await page.waitForTimeout(100);}throw Error('Missing: '+value);}
    async function reveal(n){await n.waitFor({state:'attached'});for(let i=0;i<50;i++){
      const b=await n.boundingBox(),h=page.viewportSize().height;
      const modal=await page.getByRole('dialog').count()||await page.getByRole('alertdialog').count()||await button('Đóng chọn nhanh').count()||await button('Đóng giỏ hàng').count();
      const inset=modal?0:page.viewportSize().width<600?235:180;
      if(b&&b.y>=inset&&b.y+b.height<h-12)return;
      await page.mouse.move(page.viewportSize().width*.8,h*.7);await page.mouse.wheel(0,b?b.y-(inset+h-12-b.height)/2:250);await page.waitForTimeout(90);
    }throw Error('Cannot reveal '+await n.getAttribute('aria-label'));}
    async function click(name){const n=button(name);await reveal(n);await n.click();await page.waitForTimeout(180);}
    async function chip(name){const n=page.getByRole('checkbox',{name,exact:true});await reveal(n);await n.click();await page.waitForTimeout(200);}
    async function search(value){const n=page.getByRole('textbox',{name:/^Tìm sản phẩm đã lưu/});await reveal(n);await n.click();await n.fill(value);await page.waitForTimeout(250);}
    async function top(){await page.mouse.move(page.viewportSize().width*.8,page.viewportSize().height*.7);await page.mouse.wheel(0,-100000);await page.waitForTimeout(180);}
    async function capture(name){await page.mouse.move(8,page.viewportSize().height-12);await page.waitForTimeout(150);await page.screenshot({path:path.join(output,name+'.png')});fs.writeFileSync(path.join(output,name+'.txt'),await body());}
    async function openAdd(){const n=button('Chọn size').first();await reveal(n);await n.click();await includes('Chọn nhanh');await click('M');}
    const list=()=>session.request('wishlist');
    await page.goto(origin+'/#/wishlist');await semantics();await includes('13 sản phẩm đã lưu');await capture('desktop');
    await search('dam trang');await includes('Đầm lụa trắng kiểm thử');await includes('Hiển thị 1–1 trong 1 sản phẩm');
    assert(page.url().includes('q=dam'));
    await page.setViewportSize({width:375,height:900});await includes('Đầm lụa trắng kiểm thử');
    await page.reload();await semantics();await includes('Đầm lụa trắng kiểm thử');await includes('Hiển thị 1–1 trong 1 sản phẩm');
    await click('Đặt lại');await chip('Hết hàng (1)');await includes('Áo cotton kiểm thử 3');assert(await button('Tạm hết hàng').isDisabled());
    await chip('Ngừng bán (1)');await includes('Sản phẩm không còn mở bán');assert.equal(await button('Chọn size').count(),0);
    await click('Đặt lại');await search('khong-co-ket-qua');await includes('Chưa tìm thấy món đồ phù hợp');await click('Đặt lại bộ lọc');
    report.passed.push('Whole-list Vietnamese search, stock filters, empty results, URL persistence and responsive state');

    await page.setViewportSize({width:1440,height:1080});await click('Sắp xếp Lưu gần đây');
    await page.getByRole('menuitem',{name:'Giá cao đến thấp',exact:true}).click();await includes('Đầm lụa trắng kiểm thử');assert(page.url().includes('sort=price_desc'));
    await click('Đặt lại');
    const rootRoute='**/api/v1/wishlist';
    await page.route(rootRoute,r=>r.request().method()==='GET'?r.fulfill({status:503,contentType:'application/json',body:'{}'}):r.continue());
    await click('Tải lại');await includes('Chưa cập nhật được danh sách.');await includes('Áo cotton kiểm thử 1');
    assert(await button('Chọn size').first().isDisabled());assert(await button('Tải lại yêu thích Áo cotton kiểm thử 1').isDisabled());
    await capture('refresh-error');await page.unroute(rootRoute);await click('Thử lại');await includes('13 sản phẩm đã lưu');
    report.passed.push('Price sorting and failed refresh preserve cached products while disabling stale actions');

    await openAdd();assert(await button('Thêm vào giỏ').isEnabled());await includes('Còn 12 sản phẩm.');
    const cartRoute='**/api/v1/cart/items';
    await page.route(cartRoute,async r=>{
      if(r.request().method()!=='POST')return r.continue();
      await new Promise(resolve=>{release=resolve;});
      const response=await r.fetch();assert.equal(response.status(),201);
      await r.fulfill({status:503,contentType:'application/json',body:'{}'});
    });
    await click('Thêm vào giỏ');await includes('Đang cập nhật giỏ hàng…');assert(await button('Đóng chọn nhanh').isDisabled());
    await page.keyboard.press('Escape');await includes('Chọn nhanh');assert.equal(adds,1);
    release();release=null;await includes('Kiểm tra giỏ hàng');await page.unroute(cartRoute);
    assert.equal((await session.request('cart')).items[0].quantity,1);
    await click('Kiểm tra giỏ hàng');await includes('Giỏ hàng của bạn');assert.equal(adds,1);
    await capture('cart-after-uncertain-add');await click('Đóng giỏ hàng');
    assert.equal((await list()).items.length,13);
    report.passed.push('Quick add selects live stock, locks pending dismissal and checks an uncertain cart without duplicate additions');

    for(const [width,height] of [[320,900],[375,900],[768,1024],[1440,1080],[2560,1200],[844,390]]){
      await page.setViewportSize({width,height});await top();await capture('width-'+width);
      if(height>600){await openAdd();await capture('quick-add-'+width);await click('Đóng chọn nhanh');}
    }
    report.passed.push('Wishlist and quick add render across 320/375/768/1440/2560 with landscape list checked');

    await page.setViewportSize({width:1440,height:1080});await click('Trang sau');await includes('Trang 2 / 2');
    const removeRoute='**/api/v1/wishlist/'+productIds[12];
    await page.route(removeRoute,async r=>{const response=await r.fetch();assert.equal(response.status(),200);await r.fulfill({status:503,contentType:'application/json',body:'{}'});});
    await click('Bỏ yêu thích Đầm lụa trắng kiểm thử');await includes('Chưa xác nhận được thay đổi');await includes('Đầm lụa trắng kiểm thử');
    assert.equal((await list()).items.length,12);await page.unroute(removeRoute);await click('Thử lại');await includes('Trang 1 / 1');
    assert(!page.url().includes('page=2'));assert.equal(removes,1);
    await chip('Ngừng bán (1)');await click('Bỏ yêu thích');await includes('11 sản phẩm đã lưu');assert.equal(removes,2);
    await page.reload();await semantics();await includes('11 sản phẩm đã lưu');await includes('Chưa tìm thấy món đồ phù hợp');
    report.passed.push('Uncertain removal only reconciles; deleting the last page fixes the URL; hidden entries remain removable');
    assert.deepEqual(report.errors,[]);
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
  } catch(e) {
    report.failure=String(e);
    if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));}
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));throw e;
  } finally {
    release?.();await browser?.close();await session?.close();
    if(userId)await db.user.deleteMany({where:{id:userId,email}});
    await db.inventory.deleteMany({where:{variantId:{in:variantIds}}});
    await db.productVariant.deleteMany({where:{id:{in:variantIds}}});
    await db.product.deleteMany({where:{id:{in:productIds}}});await db.$disconnect();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
