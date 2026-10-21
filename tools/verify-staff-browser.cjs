const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
module.exports=async function verify({root,url,email,warehouseEmail,supportEmail,password,orderId,ticketId,demote}){
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-staff-verification');fs.mkdirSync(output,{recursive:true});
  const mime={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.jpg':'image/jpeg','.png':'image/png','.ttf':'font/ttf'};
  const server=http.createServer((req,res)=>{
    let pathname;try{pathname=decodeURIComponent(req.url.split('?')[0]);}catch{res.writeHead(400).end();return;}
    const file=path.resolve(web,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(web+path.sep)){res.writeHead(403).end();return;}
    fs.readFile(file,(e,data)=>{res.writeHead(e?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(e?'Not found':data);});
  });
  await new Promise((r,j)=>{server.once('error',j);server.listen(4183,'127.0.0.1',r);});
  let browser,page;const errors=[],requests=[];
  try{
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
    page=await browser.newPage({viewport:{width:1440,height:1000}});page.setDefaultTimeout(18000);
    page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text()))errors.push(m.text());});
    page.on('response',r=>{if(r.url().includes('/api/v1/'))requests.push({path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});
    async function semantics(){await page.waitForTimeout(700);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function route(value){await page.evaluate(v=>{location.hash=v;},value);await page.waitForTimeout(500);}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<36;i++){const box=await node.boundingBox(),vp=page.viewportSize();if(box&&box.y>=80&&box.y+box.height<=vp.height-35)return;await page.mouse.move(vp.width*.75,vp.height*.7);await page.mouse.wheel(0,box&&box.y<80?-280:280);await page.waitForTimeout(100);}throw Error('Cannot reveal staff control');}
    async function button(name){const node=page.getByRole('button',{name,exact:true}).first();await reveal(node);await node.click();await page.mouse.move(10,100);await page.waitForTimeout(300);}
    async function fill(name,value){const n=page.getByRole('textbox',{name,exact:true});await reveal(n);await n.click();await n.fill(value);await page.waitForTimeout(100);}
    async function login(who){await fill('Email',who);await fill('Mật khẩu',password);const response=page.waitForResponse(r=>r.url().endsWith('/auth/browser/admin/login'));await button('Đăng nhập quản trị');const r=await response;assert.equal(r.status(),201);return (await r.json()).accessToken;}
    async function grant(who,role){await fill('Email tài khoản',who);const loaded=page.waitForResponse(r=>new URL(r.url()).pathname.endsWith('/admin/staff')&&r.request().method()==='GET');await button('Tìm tài khoản');assert.equal((await loaded).status(),200);await button('Đổi quyền');await page.getByRole('button',{name:/^Vai trò /}).click();await page.getByRole('menuitem',{name:role,exact:true}).click();const saved=page.waitForResponse(r=>r.url().includes('/admin/staff/')&&r.request().method()==='PATCH');await button('Lưu thay đổi');assert.equal((await saved).status(),200);}
    async function denied(path,token,method='GET'){const r=await fetch(url+'/'+path,{method,headers:{Authorization:'Bearer '+token,...(method==='GET'?{}:{'Content-Type':'application/json'})},...(method==='GET'?{}:{body:'{}'})});assert.equal(r.status,403);}
    await page.goto('http://127.0.0.1:4183/#/admin/staff');await semantics();await login(email);
    await grant(warehouseEmail,'Kho');await grant(supportEmail,'Hỗ trợ');
    await page.screenshot({path:path.join(output,'staff-desktop.png')});
    await page.getByRole('button',{name:'Đăng xuất quản trị',exact:true}).click();await route('/admin');
    const warehouseToken=await login(warehouseEmail);
    await page.getByText('Biến thể & kho',{exact:true}).last().waitFor();
    await button('Điều chỉnh kho');await fill('Số lượng thay đổi','2');await fill('Lý do','Kiểm thử phân quyền kho');await button('Lưu thay đổi');
    await page.setViewportSize({width:375,height:812});await route('/admin/orders/'+orderId);
    await button('Xác nhận đơn');await button('Lưu thay đổi');await button('Bắt đầu giao hàng');await button('Lưu thay đổi');await button('Đánh dấu đã giao');await button('Lưu thay đổi');
    assert.equal(await page.getByRole('button',{name:'Đối soát COD',exact:true}).count(),0);
    await denied('admin/orders/'+orderId+'/settle-cod',warehouseToken,'POST');
    await denied('admin/staff',warehouseToken);
    await page.screenshot({path:path.join(output,'warehouse-order-mobile.png')});
    await route('/admin/staff');await page.getByText('Bạn chưa có quyền truy cập',{exact:true}).waitFor();await page.screenshot({path:path.join(output,'denied-mobile.png')});
    await page.getByRole('button',{name:'Đăng xuất quản trị',exact:true}).click();await route('/admin/support/'+ticketId);
    const supportToken=await login(supportEmail);await fill('Nội dung trả lời','Bạn có thể xem bảng size để chọn kích cỡ phù hợp.');await button('Lưu và gửi trả lời');
    await page.getByText('Đã lưu trả lời; thư đang được xử lý.',{exact:true}).waitFor();
    await denied('admin/staff',supportToken);
    await page.screenshot({path:path.join(output,'support-mobile.png')});
    await page.setViewportSize({width:1440,height:1000});
    const persisted=page.waitForResponse(r=>r.url().endsWith('/admin/support/'+ticketId)&&r.request().method()==='GET');
    await page.reload();await semantics();
    assert.equal((await(await persisted).json()).replies.length,1);
    await page.screenshot({path:path.join(output,'support-reload-desktop.png')});
    await demote();await button('Tải lại yêu cầu');await page.getByRole('button',{name:'Đăng nhập quản trị',exact:true}).waitFor();
    assert.deepEqual(errors,[]);assert(!requests.some(r=>r.status>=500));
    console.log('PASS Chrome staff: grants, warehouse stock/fulfillment, denied money/staff, support reply, mobile/desktop/reload and demotion revocation.');
  }catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests},null,2));await browser?.close();await new Promise(r=>server.close(r));}
};
