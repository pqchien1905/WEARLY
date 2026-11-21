const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
module.exports=async function verify({root,url,email,managerEmail,password,startWorker,stopWorker,redisUnavailable,customerDenied}){
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-operations-verification');fs.mkdirSync(output,{recursive:true});
  const mime={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.jpg':'image/jpeg','.png':'image/png','.ttf':'font/ttf'};
  const server=http.createServer((req,res)=>{
    let pathname;try{pathname=decodeURIComponent(req.url.split('?')[0]);if(pathname.includes('\0'))throw Error();}catch{res.writeHead(400).end();return;}
    const file=path.resolve(web,'.'+(pathname==='/'?'/index.html':pathname));if(!file.startsWith(web+path.sep)){res.writeHead(403).end();return;}
    fs.readFile(file,(e,data)=>{res.writeHead(e?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(e?'Not found':data);});
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(4183,'127.0.0.1',resolve);});
  let browser,page;const errors=[],requests=[],snapshots=[];
  try{
    browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
    page=await browser.newPage({viewport:{width:1440,height:1000}});page.setDefaultTimeout(18000);
    page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text()))errors.push(m.text());});
    page.on('response',r=>{if(r.url().includes('/api/v1/'))requests.push({path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});
    async function semantics(){await page.waitForTimeout(600);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<40;i++){const box=await node.boundingBox(),vp=page.viewportSize();if(box&&box.y>=80&&box.y+box.height<=vp.height-30)return;await page.mouse.move(vp.width*.75,vp.height*.7);await page.mouse.wheel(0,box&&box.y<80?-300:300);await page.waitForTimeout(90);}throw Error('Cannot reveal operations control');}
    async function button(name){const node=page.getByRole('button',{name,exact:true}).first();await reveal(node);await node.click();await page.mouse.move(10,100);await page.waitForTimeout(200);}
    async function fill(name,value){const node=page.getByRole('textbox',{name,exact:true});await reveal(node);await node.click();await node.fill(value);await page.waitForTimeout(100);}
    async function login(who){await fill('Tên đăng nhập',who.split('@')[0]);await fill('Mật khẩu',password);const response=page.waitForResponse(r=>r.url().endsWith('/auth/browser/admin/login'));await button('Đăng nhập quản trị');assert.equal((await response).status(),201);}
    const watch=()=>{const pending=page.waitForResponse(r=>new URL(r.url()).pathname.endsWith('/admin/operations')&&r.request().method()==='GET');pending.catch(()=>{});return pending;};
    async function snapshot(response){assert.equal(response.status(),200);assert.match(response.headers()['cache-control'],/private.*no-store/);const data=await response.json();assert(!JSON.stringify(data).includes('private-fixture'));snapshots.push(data);return data;}
    async function refresh(){const pending=watch();await button('Tải lại số liệu');return snapshot(await pending);}
    await page.goto('http://127.0.0.1:4183/#/admin/ai-monitoring');await semantics();
    const initial=watch();await login(email);const first=await snapshot(await initial);
    assert.equal(first.database.schemaReady,true);assert.equal(first.redis.queues.tryOn.waiting,1);assert.equal(first.storage.status,'ok');assert.equal(first.worker.status,'unavailable');
    assert.equal(first.providers.gemini.configured,false);assert.equal(first.providers.vnpay.configured,false);
    await page.getByText('Không có tín hiệu worker gần đây',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'operations-desktop.png')});
    const cost=page.getByText('Ước tính chi phí AI hôm nay',{exact:true});await reveal(cost);
    await page.screenshot({path:path.join(output,'operations-work-desktop.png')});
    await page.setViewportSize({width:375,height:812});await button('Tải lại số liệu');
    await page.screenshot({path:path.join(output,'operations-mobile.png')});
    await reveal(cost);await page.screenshot({path:path.join(output,'operations-work-mobile.png')});
    await startWorker();assert.equal((await refresh()).worker.status,'ok');
    await page.getByText('Worker có tín hiệu trong 30 giây gần đây.',{exact:true}).waitFor();
    await stopWorker();await redisUnavailable(true);
    const failed=await refresh();assert.equal(failed.redis.status,'unavailable');assert.equal(failed.redis.queues,null);assert.equal(failed.database.status,'ok');
    await page.getByText('Chưa có số liệu.',{exact:true}).waitFor();await page.screenshot({path:path.join(output,'operations-redis-unavailable-mobile.png')});
    await redisUnavailable(false);assert.equal((await refresh()).redis.status,'ok');
    await customerDenied();
    await (async()=>{await page.getByRole('button',{name:'Tài khoản quản trị',exact:true}).click();await page.getByRole('menuitem',{name:'Đăng xuất',exact:true}).or(page.getByRole('button',{name:'Đăng xuất',exact:true})).first().click();})();await login(managerEmail);
    const priorReads=requests.filter(r=>r.path.endsWith('/admin/operations')).length;
    await page.evaluate(()=>{location.hash='/admin/ai-monitoring';});
    await page.getByText('Bạn chưa có quyền truy cập',{exact:true}).waitFor();
    assert.equal(requests.filter(r=>r.path.endsWith('/admin/operations')).length,priorReads);
    assert.equal(await page.getByText('Vận hành & AI',{exact:true}).count(),0);
    await page.screenshot({path:path.join(output,'operations-denied-mobile.png')});
    assert.deepEqual(errors,[]);assert(!requests.some(r=>r.status>=500));assert(requests.filter(r=>r.path.endsWith('/admin/operations')).every(r=>r.method==='GET'));
    console.log('PASS Chrome operations: real PG/Redis/storage aggregates, heartbeat lifecycle, Redis outage, manual refresh, private/no-store, ADMIN-only and375/1440. No external provider call.');
  }catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{await redisUnavailable(false);fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests,snapshots},null,2));await browser?.close();await new Promise(resolve=>server.close(resolve));}
};
