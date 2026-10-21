const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {isAnonymousRestore}=require('./browser-session-assertions.cjs');
module.exports=async function verify({root,url,email,password,callCount,foreignRead,disable}) {
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-stylist-verification');fs.mkdirSync(output,{recursive:true});
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
    page=await browser.newPage({viewport:{width:1440,height:1000}});page.setDefaultTimeout(18000);
    page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text()))errors.push(m.text());});
    page.on('response',r=>{if(r.url().includes('/api/v1/'))requests.push({path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});
    async function semantics(){await page.waitForTimeout(700);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<40;i++){const b=await node.boundingBox(),v=page.viewportSize();if(b&&b.y>=125&&b.y+b.height<=v.height-25)return;await page.mouse.move(v.width*.8,v.height*.7);await page.mouse.wheel(0,b&&b.y<125?-280:280);await page.waitForTimeout(100);}throw Error('Cannot reveal Stylist control');}
    async function button(label){const n=page.getByRole('button',{name:label,exact:true}).last();await reveal(n);await n.click();await page.mouse.move(10,125);await page.waitForTimeout(300);}
    async function fill(label,value){const n=label.startsWith('Bạn muốn')?page.getByRole('textbox',{name:/^Bạn muốn phối đồ cho dịp nào\?/}):page.getByRole('textbox',{name:label,exact:true});await reveal(n);await n.click();await page.waitForTimeout(150);await n.fill(value);await page.waitForTimeout(150);}
    async function preferences(){
      await fill('Bạn muốn phối đồ cho dịp nào?','Đi làm, đơn giản');await fill('Màu (để trống nếu không giới hạn)','Trắng thử nghiệm');
      const consent=page.getByRole('checkbox');await reveal(consent);await consent.click();
    }
    await page.goto('http://127.0.0.1:4183/#/ai-stylist');await semantics();await button('Đăng nhập');
    await fill('Email',email);await fill('Mật khẩu',password);await button('Đăng nhập');
    await page.getByText('Góc stylist của bạn.',{exact:true}).waitFor();
    await page.getByText(/Đã dùng 0 \/ 3/).waitFor();assert.equal(callCount(),0);
    assert(await page.getByRole('button',{name:'Nhờ Gemini gợi ý',exact:true}).isDisabled());
    await preferences();
    const first=page.waitForResponse(r=>r.url().endsWith('/ai/stylist/requests')&&r.request().method()==='POST');
    await button('Nhờ Gemini gợi ý');const firstResponse=await first;assert.equal(firstResponse.status(),201);
    const firstReceipt=await firstResponse.json();assert.equal(await foreignRead(firstReceipt.requestKey),404);
    const total=page.getByText('Tổng trang phục: 490.000 ₫',{exact:true});await total.waitFor();await reveal(total);
    assert.equal(callCount(),1);await page.screenshot({path:path.join(output,'stylist-desktop.png')});
    await button('Xem sản phẩm');await page.waitForURL('**/#/products/**');
    const restored=page.waitForResponse(r=>r.url().endsWith('/ai/stylist/requests/latest'));
    await page.goBack();await semantics();await total.waitFor();
    assert.equal((await (await restored).json()).receipt.requestKey,firstReceipt.requestKey);
    assert.equal(callCount(),1);await preferences();
    let lost=false,secondKey;
    await page.route('**/api/v1/ai/stylist/requests',async interception=>{
      if(!lost&&interception.request().method()==='POST'){lost=true;const response=await interception.fetch();assert.equal(response.status(),201);secondKey=(await response.json()).requestKey;await interception.abort('failed');}
      else await interception.continue();
    });
    await button('Yêu cầu mới');
    await page.getByText('Chưa nhận được kết quả. Dùng nút kiểm tra để lấy lại yêu cầu cũ trước khi thử thêm.',{exact:true}).waitFor();
    assert.equal(callCount(),2);await page.unroute('**/api/v1/ai/stylist/requests');
    const recovered=page.waitForResponse(r=>r.url().endsWith('/ai/stylist/requests/latest'));
    await page.reload();await semantics();await total.waitFor();
    assert.equal((await (await recovered).json()).receipt.requestKey,secondKey);assert.equal(callCount(),2);
    await page.setViewportSize({width:375,height:900});await page.waitForTimeout(400);await reveal(total);
    await page.screenshot({path:path.join(output,'stylist-mobile.png')});
    await preferences();
    await button('Yêu cầu mới');await page.getByText('Gemini đang giới hạn lượt dùng. Bạn có thể tạo yêu cầu mới sau.',{exact:true}).waitFor();
    await page.getByText(/Đã dùng 3 \/ 3/).waitFor();assert.equal(callCount(),3);
    assert(await page.getByRole('button',{name:'Yêu cầu mới',exact:true}).isDisabled());
    disable();await page.reload();await semantics();await page.getByText('Gemini chưa được cấu hình',{exact:true}).waitFor();
    assert.equal(callCount(),3);assert.deepEqual(errors,[]);
    assert(!requests.some(r=>r.status>=400&&!isAnonymousRestore(r)));
    console.log('PASS Chrome Stylist: consent, exact SKU prices, private receipts, product navigation/back and lost-reply reload recovery without another AI call, quota/rate-limit/configuration states and375/1440. Deterministic Gemini fixture only.');
  } catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests},null,2));await browser?.close();await new Promise(r=>server.close(r));}
};
