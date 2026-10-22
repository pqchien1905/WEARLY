const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
module.exports=async function verify({root,email,customerEmail,password,orderId}){
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-support-verification');fs.mkdirSync(output,{recursive:true});
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
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<36;i++){const box=await node.boundingBox(),vp=page.viewportSize();if(box&&box.y>=125&&box.y+box.height<=vp.height-35)return;await page.mouse.move(vp.width*.75,vp.height*.7);await page.mouse.wheel(0,box&&box.y<125?-280:280);await page.waitForTimeout(150);}throw Error('Cannot reveal support control');}
    async function button(name){const n=page.getByRole('button',{name,exact:true}).last();await reveal(n);await n.click();await page.mouse.move(10,125);await page.waitForTimeout(300);}
    async function fill(name,value){const n=page.getByRole('textbox',{name,exact:true});await reveal(n);await n.click();await page.waitForTimeout(100);await n.fill(value);await page.waitForTimeout(150);}
    async function login(){await fill('Tên đăng nhập',email.split('@')[0]);await fill('Mật khẩu',password);await button('Đăng nhập quản trị');}
    async function captured(needle){
      for(let i=0;i<60;i++){
        const data=await(await fetch('http://127.0.0.1:8025/api/v1/search?query='+encodeURIComponent('to:'+customerEmail))).json();
        for(const item of data.messages??[]){const m=await(await fetch('http://127.0.0.1:8025/api/v1/message/'+item.ID)).json();if(m.Text?.includes(needle))return m;}
        await new Promise(r=>setTimeout(r,200));
      }throw Error('Expected synthetic message not found in native inbox');
    }
    await page.goto('http://127.0.0.1:4183/#/contact');await semantics();
    await fill('Tên của bạn','Khách hỗ trợ local');await fill('Email liên hệ',customerEmail);await fill('Nội dung cần hỗ trợ','Tôi cần chọn size áo cotton phù hợp.');
    await page.setViewportSize({width:375,height:812});await page.waitForTimeout(300);
    const created=page.waitForResponse(r=>r.url().endsWith('/support')&&r.request().method()==='POST');await button('Gửi yêu cầu hỗ trợ');
    const response=await created;assert.equal(response.status(),201);const receipt=await response.json();
    await page.getByText('Đã lưu yêu cầu hỗ trợ',{exact:true}).waitFor();await reveal(page.getByText('Đã lưu yêu cầu hỗ trợ',{exact:true}));await page.screenshot({path:path.join(output,'contact-receipt-mobile.png')});
    await route('/admin/support/'+receipt.id);
    const detail=page.waitForResponse(r=>r.url().endsWith('/admin/support/'+receipt.id)&&r.request().method()==='GET');
    await login();assert.equal((await(await detail).json()).message,'Tôi cần chọn size áo cotton phù hợp.');
    await page.getByRole('textbox',{name:'Nội dung trả lời',exact:true}).waitFor();
    const reply='Bạn hãy đối chiếu số đo với bảng size ở trang sản phẩm.';
    await fill('Nội dung trả lời',reply);await button('Lưu và gửi trả lời');await page.getByText('Đã lưu trả lời; thư đang được xử lý.',{exact:true}).waitFor();
    const mail=await captured(reply);assert(mail.Text.includes(receipt.id));
    await button('Tải lại yêu cầu');await page.getByText('Đã gửi đến hộp thư local',{exact:true}).waitFor();
    await reveal(page.getByText('Đã gửi đến hộp thư local',{exact:true}));await page.screenshot({path:path.join(output,'support-reply-mobile.png')});
    await page.setViewportSize({width:1440,height:1000});await route('/admin/orders/'+orderId);
    await button('Xác nhận đơn');await button('Lưu thay đổi');
    const notice=await captured('Đơn hàng đã được xác nhận');assert(notice.Text.includes(orderId));
    await route('/admin/mail');await page.getByText('Theo dõi thư',{exact:true}).last().waitFor();await page.screenshot({path:path.join(output,'mail-status-desktop.png')});
    await route('/admin/support/'+receipt.id);
    const persisted=page.waitForResponse(r=>r.url().endsWith('/admin/support/'+receipt.id)&&r.request().method()==='GET');
    await page.reload();await semantics();assert.equal((await(await persisted).json()).replies[0].message,reply);
    await page.getByText('Đã gửi đến hộp thư local',{exact:true}).waitFor();await page.screenshot({path:path.join(output,'support-persisted-desktop.png')});
    assert.deepEqual(errors,[]);assert(!requests.some(r=>r.status>=400&&!isAnonymousRestore(r)));
    console.log('PASS Chrome support: guest receipt, staff reply, native inbox, order notice, mobile/desktop and persisted reload.');return receipt.id;
  }catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests},null,2));await browser?.close();await new Promise(r=>server.close(r));}
};
