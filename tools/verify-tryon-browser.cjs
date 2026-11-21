const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
module.exports=async function verify({root,url,email,password,fixture,photo,callCount,foreignRead,deletedRead,disable,pauseUpload,holdJob}) {
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-tryon-verification');fs.mkdirSync(output,{recursive:true});
  const mime={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.jpg':'image/jpeg','.png':'image/png','.ttf':'font/ttf'};
  const server=http.createServer((req,res)=>{
    let pathname;try{pathname=decodeURIComponent(req.url.split('?')[0]);}catch{res.writeHead(400).end();return;}
    const file=path.resolve(web,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(web+path.sep)){res.writeHead(403).end();return;}
    fs.readFile(file,(e,data)=>{res.writeHead(e?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(e?'Not found':data);});
  });
  await new Promise((r,j)=>{server.once('error',j);server.listen(4183,'127.0.0.1',r);});
  let browser,page;const errors=[],requests=[];
  try {
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
    page=await browser.newPage({viewport:{width:1440,height:1100}});page.setDefaultTimeout(20000);
    page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text()))errors.push(m.text());});
    page.on('response',r=>{if(r.url().includes('/api/v1/'))requests.push({path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});
    async function semantics(){await page.waitForTimeout(700);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<45;i++){const b=await node.boundingBox(),v=page.viewportSize();if(b&&b.y>=125&&b.y+b.height<=v.height-25)return;await page.mouse.move(v.width*.8,v.height*.7);await page.mouse.wheel(0,b&&b.y<125?-280:280);await page.waitForTimeout(100);}throw Error('Cannot reveal try-on control');}
    async function button(label){const n=page.getByRole('button',{name:label,exact:true}).last();await reveal(n);await n.click();await page.mouse.move(10,125);await page.waitForTimeout(300);}
    async function fill(label,value){const n=page.getByRole('textbox',{name:label,exact:true});await reveal(n);await n.click();await page.waitForTimeout(150);await n.fill(value);}
    async function consent(text){const n=page.getByRole('checkbox',{name:new RegExp(text)});await reveal(n);await n.click();await page.waitForTimeout(250);}
    const entry='http://127.0.0.1:4183/#/virtual-try-on?product='+fixture;
    await page.goto(entry);await semantics();await button('Đăng nhập');
    await fill('Email',email);await fill('Mật khẩu',password);await button('Đăng nhập');
    await page.getByText('Phòng thử của bạn.',{exact:true}).waitFor();await page.getByText(/Đã dùng 0 \/ 3/).waitFor();
    assert.equal(callCount(),0);assert(await page.getByRole('button',{name:'Thử trang phục',exact:true}).isDisabled());
    const chosen=page.waitForEvent('filechooser');await button('Chọn ảnh từ thiết bị');
    await (await chosen).setFiles({name:'synthetic-private-photo.png',mimeType:'image/png',buffer:photo});
    await page.getByRole('button',{name:'Lưu ảnh riêng tư',exact:true}).waitFor();
    assert(await page.getByRole('button',{name:'Lưu ảnh riêng tư',exact:true}).isDisabled());
    await consent('Tôi đồng ý lưu ảnh');
    let imageId,uploadPosts=0,uploaded;
    const uploadFinished=new Promise(r=>{uploaded=r}),uploadGate=pauseUpload();
    await page.route('**/api/v1/uploads/images',async interception=>{
      if(interception.request().method()==='POST'){
        uploadPosts++;const r=await interception.fetch();assert.equal(r.status(),201);imageId=(await r.json()).id;uploaded();await interception.abort('failed').catch(()=>{});
      }else await interception.continue();
    });
    await button('Lưu ảnh riêng tư');await uploadGate.wait();
    await page.reload();await semantics();await page.getByRole('button',{name:'Kiểm tra ảnh đã gửi',exact:true}).waitFor();
    assert.equal(uploadPosts,1);await button('Kiểm tra ảnh đã gửi');
    await page.getByText('Ảnh đang được lưu. Hãy kiểm tra lại sau ít giây.',{exact:true}).waitFor();
    uploadGate.release();await uploadFinished;await button('Kiểm tra ảnh đã gửi');
    await page.getByText(/Thời hạn ảnh:/).first().waitFor();assert.equal(uploadPosts,1);assert.equal(callCount(),0);
    await page.unroute('**/api/v1/uploads/images');
    assert.equal(await foreignRead('uploads/images/'+imageId+'/content'),404);
    assert(await page.getByRole('button',{name:'Thử trang phục',exact:true}).isDisabled());
    await consent('Tôi đồng ý gửi ảnh');
    const first=page.waitForResponse(r=>r.url().endsWith('/ai/try-on/jobs')&&r.request().method()==='POST');
    await button('Thử trang phục');const response=await first;assert.equal(response.status(),201);const job=await response.json();
    assert.equal(job.sku,fixture);await page.getByText('Đã tạo ảnh thử đồ',{exact:true}).waitFor();
    const result=page.getByRole('img',{name:'Ảnh thử đồ do Gemini tạo',exact:true});await result.waitFor();await reveal(result);
    assert.equal(callCount(),1);assert.equal(await foreignRead('ai/try-on/jobs/'+job.id+'/result'),404);
    await page.screenshot({path:path.join(output,'tryon-desktop.png')});
    let lost=false,secondId,accepted;
    const secondFinished=new Promise(r=>{accepted=r}),jobGate=await holdJob();
    await page.route('**/api/v1/ai/try-on/jobs',async interception=>{
      if(!lost&&interception.request().method()==='POST'){
        lost=true;const r=await interception.fetch();assert.equal(r.status(),201);secondId=(await r.json()).id;accepted();await interception.abort('failed').catch(()=>{});
      }else await interception.continue();
    });
    await button('Thử lượt mới');await jobGate.wait();await page.reload();await semantics();
    await page.getByRole('button',{name:'Kiểm tra yêu cầu đã gửi',exact:true}).waitFor();
    assert.equal(await page.getByText('Đã tạo ảnh thử đồ',{exact:true}).count(),0);assert.equal(callCount(),1);
    assert(await page.getByRole('button',{name:'Thử trang phục',exact:true}).isDisabled());
    await jobGate.release();await secondFinished;await page.unroute('**/api/v1/ai/try-on/jobs');
    await button('Kiểm tra yêu cầu đã gửi');
    await page.getByText('Đã tạo ảnh thử đồ',{exact:true}).waitFor();assert(secondId);assert.equal(callCount(),2);
    await page.setViewportSize({width:375,height:900});await page.waitForTimeout(400);await reveal(result);
    await page.screenshot({path:path.join(output,'tryon-mobile.png')});
    await consent('Tôi đồng ý gửi ảnh');await button('Thử lượt mới');
    await page.getByText('Gemini đang giới hạn lượt dùng. Yêu cầu này đã kết thúc.',{exact:true}).waitFor();
    await page.getByText(/Đã dùng 3 \/ 3/).waitFor();assert.equal(callCount(),3);
    assert(await page.getByRole('button',{name:'Thử lượt mới',exact:true}).isDisabled());
    await button('Xem lịch sử thử đồ');await page.getByRole('heading',{name:'Lịch sử thử đồ',level:1,exact:true}).waitFor();
    await button('Xem ảnh thử đồ');await page.getByRole('img',{name:'Ảnh thử đồ riêng tư',exact:true}).waitFor();
    await button('Xóa ảnh và các kết quả');await button('Xác nhận xóa');await page.getByText('Bạn chưa có yêu cầu thử đồ còn trong thời gian lưu.',{exact:true}).waitFor();
    assert.equal(await deletedRead('uploads/images/'+imageId+'/content'),404);
    assert.equal(await deletedRead('ai/try-on/jobs/'+job.id+'/result'),404);
    disable();await page.goto(entry);await semantics();await page.getByText('Gemini chưa được cấu hình',{exact:true}).waitFor();
    assert.equal(callCount(),3);assert.deepEqual(errors,[]);
    assert(!requests.some(r=>r.status>=400&&!isAnonymousRestore(r)));
    console.log('PASS Chrome try-on: consent, reload before upload verification/job commit (including older history), same-key recovery, exact SKU, private history/ownership/deletion, quota/rate/config and375/1440. Synthetic photo and Gemini fixture only.');
  }catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests},null,2));await browser?.close();await new Promise(r=>server.close(r));}
};
