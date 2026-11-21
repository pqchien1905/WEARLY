// Chrome acceptance against the local API and PostgreSQL; fixtures are scoped to this run.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {chromium}=require('../.tools/browser/node_modules/playwright');
const argon2=require('../backend/node_modules/argon2');
const {localDatabase}=require('./seed-customer-account.cjs');
const base=process.env.ADMIN_TEST_BASE||'http://localhost:8080';
if(!/^http:\/\/localhost:(8080|5173)$/.test(base))throw Error('Local frontend required');
const output=path.resolve(__dirname,'../.tools/collections-admin-acceptance');
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  const db=localDatabase(),marker='collections-qa-'+randomUUID().slice(0,8),password=randomUUID()+'-Aa1';
  const report={passed:[],errors:[],unexpectedResponses:[]},ids=[],products=[];
  let browser,page,staff,category,brand,allowConflict=false;
  const title='Bộ sưu tập mới '+marker,renamed='Phong cách mùa thu '+marker,createdSlug=marker+'-ui';
  try {
    staff=await db.user.create({data:{email:marker+'@example.test',username:marker,name:'Quản trị kiểm thử bộ sưu tập',passwordHash:await argon2.hash(password),role:'ADMIN',active:true}});
    category=await db.category.create({data:{name:marker,slug:marker}});
    brand=await db.brand.create({data:{name:marker,slug:marker}});
    for(let i=0;i<23;i++)ids.push((await db.storeCollection.create({data:{slug:marker+'-'+i,title:'Bộ sưu tập '+String(i).padStart(2,'0')+' '+marker,style:marker+'-'+i,description:'',position:i,active:i!==1}})).id);
    for(let i=0;i<3;i++)products.push(await db.product.create({data:{slug:marker+'-p'+i,name:'Áo cotton '+i+' '+marker,style:marker+(i===0?'-0':'-new'),categoryId:category.id,brandId:brand.id,description:'',material:'Cotton',images:{create:{url:'assets/images/shirt.jpg',alt:'Áo cotton'}},variants:{create:{sku:marker+'-'+i,color:'Trắng',colorHex:'#ffffff',size:'M',price:300000,inventory:{create:{quantity:7}}}}}}));
    const stocks=await db.inventory.findMany({where:{variant:{productId:{in:products.map(p=>p.id)}}},orderBy:{id:'asc'}});

    browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--host-resolver-rules=MAP localhost 127.0.0.1'] });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, timezoneId: 'Asia/Bangkok', reducedMotion: 'reduce' });
    page = await context.newPage(); page.setDefaultTimeout(18000);
    page.on('pageerror', e => report.errors.push(e.message));
    page.on('console', m => { if (/EXCEPTION CAUGHT|Another exception|overflowed/.test(m.text())) report.errors.push(m.text()); });
    page.on('response', r => { if (/\/api\/v1\/admin\//.test(r.url()) && r.status() >= 400 && !(allowConflict && r.status() === 409)) report.unexpectedResponses.push({ path: new URL(r.url()).pathname, status: r.status() }); });
    const snapshot = () => page.locator('body').ariaSnapshot();
    const button = name => page.getByRole('button', { name, exact: typeof name === 'string' });
    const passed = text => { report.passed.push(text); console.log(text); };
    async function contains(text) {
      for (let i = 0; i < 150; i++) { if ((await snapshot()).includes(text)) return; await page.waitForTimeout(100); }
      throw Error('Missing UI: ' + text);
    }
    async function semantics() {
      await page.waitForFunction(() => document.querySelector('flt-semantics-placeholder,flt-semantics'));
      await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    }
    async function reveal(node) {
      await node.waitFor({ state: 'attached' });
      for (let i = 0; i < 70; i++) {
        const box = await node.boundingBox(), v = page.viewportSize();
        if (box && box.y >= 85 && box.y + box.height < v.height - 20) return;
        await page.mouse.move(v.width * .8, v.height * .7);
        await page.mouse.wheel(0, box?.y < 85 ? -500 : 500); await page.waitForTimeout(80);
      }
      throw Error('Control outside viewport: ' + node);
    }
    async function click(name) { const node = name === 'Lưu thông tin sản phẩm' ? button(name).first() : button(name); await reveal(node); await node.click(); await page.waitForTimeout(250); }
    async function fill(label, value) {
      const node = page.getByRole('textbox', { name: new RegExp('^' + label) });
      await reveal(node); await node.click(); await page.waitForTimeout(100); await node.fill(value); await page.waitForTimeout(100);
    }
    async function select(label, option) {
      const node = button(new RegExp('^' + label + '\\s')).last(); await reveal(node); await node.click();
      await page.getByRole('menu').last().hover(); await page.mouse.wheel(0, -10000); await page.waitForTimeout(200);
      await page.getByRole('menuitem', { name: option, exact: true }).click(); await page.waitForTimeout(250);
    }
    async function route(target, text) { await page.evaluate(v => location.hash = '#' + v, target); await page.waitForTimeout(300); await contains(text); }
    async function capture(name) {
      await page.mouse.move(page.viewportSize().width * .75, 500); await page.mouse.wheel(0, -20000); await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(output, name + '.png') }); fs.writeFileSync(path.join(output, name + '.txt'), await snapshot());
    }

    await page.goto(base+'/#/admin/collections');await semantics();await contains('Đăng nhập quản trị');
    await fill('Tên đăng nhập',marker);await fill('Mật khẩu',password);await click('Đăng nhập quản trị');
    await contains('Tìm kiếm bộ sưu tập');await fill('Tìm kiếm bộ sưu tập',marker);await click('Tìm kiếm');
    await contains('23 bộ sưu tập phù hợp bộ lọc');await click('Trang sau');await contains('Trang 2/2');
    await page.reload();await semantics();await contains('Trang 2/2');
    await select('Trạng thái','Đang hiển thị');await contains('1 bộ sưu tập phù hợp bộ lọc');
    await select('Trạng thái','Đang ẩn');await contains('1 bộ sưu tập phù hợp bộ lọc');
    await select('Trạng thái','Chờ sản phẩm công khai');await contains('21 bộ sưu tập phù hợp bộ lọc');
    await select('Trạng thái','Tất cả trạng thái');await select('Sắp xếp','Tên A–Z');
    await fill('Tìm kiếm bộ sưu tập','bo suu tap 00 '+marker);await click('Tìm kiếm');await contains('1 bộ sưu tập phù hợp bộ lọc');
    await capture('desktop-list');passed('Real login; Vietnamese search, status filters, sorting and persistent URL pagination');
    await click('Thêm bộ sưu tập');await click('Lưu thay đổi');await contains('Vui lòng nhập thông tin.');
    await fill('Tên bộ sưu tập',title);await fill('Đường dẫn',marker+'-0');await fill('Mô tả','Các thiết kế cotton dành cho mùa thu.');await fill('Phong cách',marker+'-new');
    await click('Chọn ảnh bìa');await contains('Tìm sản phẩm làm bìa');
    await fill('Tìm sản phẩm làm bìa','ao cotton 1');await click('Tìm ảnh bìa');await contains(products[1].name);
    const pick=button(new RegExp(products[1].name));await reveal(pick);await pick.click();
    await fill('Thứ tự hiển thị','3');allowConflict=true;await click('Lưu thay đổi');await contains('Đường dẫn hoặc phong cách đã có bộ sưu tập.');
    await fill('Đường dẫn',createdSlug);await click('Lưu thay đổi');await contains('Đã thêm bộ sưu tập.');allowConflict=false;
    let created=await db.storeCollection.findUniqueOrThrow({where:{slug:createdSlug}});ids.push(created.id);
    assert.equal(created.coverProductId,products[1].id);assert.equal(created.active,false);assert.equal(created.position,3);
    await route('/admin/collections/'+created.id,'Chi tiết bộ sưu tập');await contains('2 công khai / 2 sản phẩm');
    await click('Hiện bộ sưu tập');await click('Xác nhận');await contains('Đã bật bộ sưu tập.');
    await click('Xem tại cửa hàng');await contains(title);await contains(products[1].name);await capture('storefront');
    await route('/admin/collections/'+created.id,'Chi tiết bộ sưu tập');await click('Xem sản phẩm');await contains('2 sản phẩm');
    assert.equal(new URL(page.url().split('#')[1],base).searchParams.get('style'),marker+'-new');await contains('Phong cách: '+marker+'-new');
    passed('UI validation, duplicate correction and paginated cover search; created collection publishes real members and links to exact product style');
    await route('/admin/collections/'+created.id,'Chi tiết bộ sưu tập');await click('Sửa bộ sưu tập');
    await fill('Tên bộ sưu tập',renamed);await click('Lưu thay đổi');await contains('Đã cập nhật bộ sưu tập.');
    assert.equal((await db.storeCollection.findUniqueOrThrow({where:{id:created.id}})).slug,createdSlug);
    await db.product.update({where:{id:products[1].id},data:{active:false}});await click('Tải lại');await contains('1 công khai / 2 sản phẩm');await contains('Ảnh đã chọn không còn công khai cùng phong cách.');
    await click('Sửa bộ sưu tập');await fill('Mô tả','Nội dung cập nhật sau khi ảnh bìa được ẩn.');await click('Lưu thay đổi');await contains('Đã cập nhật bộ sưu tập.');
    created=await db.storeCollection.findUniqueOrThrow({where:{id:created.id}});assert.equal(created.coverProductId,products[1].id);
    await capture('detail-1440');
    for(const width of [768,375]){
      await page.setViewportSize({width,height:1000});await route('/admin/collections?q='+createdSlug,'1 bộ sưu tập phù hợp bộ lọc');await capture('list-'+width);
      await click('Xem chi tiết');await contains('Chi tiết bộ sưu tập');await capture('detail-'+width);
      await click('Sửa bộ sưu tập');await capture('editor-'+width);await click('Đóng');
    }
    passed('Cover fallback and metadata edits preserve the selected product; list/detail/editor fit 375/768/1440');
    await click('Sửa bộ sưu tập');await db.storeCollection.update({where:{id:created.id},data:{title:renamed+' khác',version:{increment:1}}});
    await fill('Tên bộ sưu tập','Không ghi đè');allowConflict=true;await click('Lưu thay đổi');await contains('Bộ sưu tập đã thay đổi.');await click('Tải lại dữ liệu');allowConflict=false;await contains(renamed+' khác');
    await click('Ẩn bộ sưu tập');await click('Xác nhận');await contains('Đã ẩn bộ sưu tập.');
    assert.equal((await fetch('http://localhost:3000/api/v1/collections/'+createdSlug)).status,404);
    passed('Concurrent editing rejects stale version; hiding removes the public detail without altering product publication');
    await route('/admin/collections/'+created.id+'?from='+encodeURIComponent('/admin/collections?q='+marker+'&status=hidden'),'Chi tiết bộ sưu tập');
    await click('Xóa bộ sưu tập');await contains('Xóa vĩnh viễn');await click('Đóng');assert.ok(await db.storeCollection.findUnique({where:{id:created.id}}));
    await click('Xóa bộ sưu tập');await click('Xác nhận xóa');await contains('Quản lý bộ sưu tập');await contains('Đã xóa bộ sưu tập.');
    assert.equal(new URL(page.url().split('#')[1],base).searchParams.get('status'),'hidden');assert.equal(await db.storeCollection.findUnique({where:{id:created.id}}),null);
    assert.equal(await db.adminAuditEvent.count({where:{targetId:created.id,action:'COLLECTION_DELETED'}}),1);
    assert.equal(await db.product.count({where:{id:{in:products.map(p=>p.id)}}}),3);
    assert.deepEqual(await db.inventory.findMany({where:{variant:{productId:{in:products.map(p=>p.id)}}},orderBy:{id:'asc'}}),stocks);
    passed('Mobile deletion confirmation/cancellation, retained return filters and one audit; all products and stock remain intact');
    assert.deepEqual(report.errors,[]);assert.deepEqual(report.unexpectedResponses,[]);
  }catch(e){report.failure=e.message;if(page){await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});fs.writeFileSync(path.join(output,'failure.txt'),await page.locator('body').ariaSnapshot().catch(()=>''));}throw e;}
  finally{
    await browser?.close();
    try{
      if(staff)await db.adminAuditEvent.deleteMany({where:{actorId:staff.id}});
      await db.storeCollection.deleteMany({where:{slug:{startsWith:marker}}});
      await db.inventory.deleteMany({where:{variant:{productId:{in:products.map(p=>p.id)}}}});
      await db.productVariant.deleteMany({where:{productId:{in:products.map(p=>p.id)}}});await db.product.deleteMany({where:{id:{in:products.map(p=>p.id)}}});
      if(category)await db.category.delete({where:{id:category.id}});if(brand)await db.brand.delete({where:{id:brand.id}});if(staff)await db.user.delete({where:{id:staff.id}});report.cleaned=true;
    }finally{await db.$disconnect();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));}
  }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
