const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
module.exports=async function verify({root,url,email,otherEmail,adminEmail,password,expiredAccess,revokeStaff}) {
  const {chromium}=require(path.join(root,'.tools/browser/node_modules/playwright'));
  const web=path.join(root,'frontend/build/web'),output=path.join(root,'.tools/api-sessions-verification');fs.mkdirSync(output,{recursive:true});
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
    const context=await browser.newContext({viewport:{width:1440,height:1000}});
    function observe(p,tab){p.setDefaultTimeout(18000);p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(/EXCEPTION CAUGHT|Another exception|subtype|TypeError/.test(m.text()))errors.push(m.text());});p.on('response',r=>{if(r.url().includes('/api/v1/'))requests.push({tab,path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});}
    page=await context.newPage();observe(page,'primary');const primary=page;
    async function semantics(){await page.waitForTimeout(700);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());}
    async function route(value){await page.evaluate(v=>{location.hash=v;},value);await page.waitForTimeout(500);}
    async function reveal(node){await node.waitFor({state:'attached'});for(let i=0;i<36;i++){const b=await node.boundingBox(),v=page.viewportSize();if(b&&b.y>=60&&b.y+b.height<=v.height-25)return;await page.mouse.move(v.width*.75,v.height*.7);await page.mouse.wheel(0,b&&b.y<60?-280:280);await page.waitForTimeout(100);}throw Error('Cannot reveal session control');}
    async function button(name){const n=page.getByRole('button',{name,exact:true}).first();await reveal(n);await n.click();await page.mouse.move(10,100);await page.waitForTimeout(250);}
    async function fill(name,value){const n=page.getByRole('textbox',{name,exact:true});await reveal(n);await n.click();await page.waitForTimeout(150);await n.fill(value);await page.waitForTimeout(150);assert.equal(await n.inputValue(),value);}
    async function login(who,admin=false){await fill(admin?'Tên đăng nhập':'Email',admin?who.split('@')[0]:who);await fill('Mật khẩu',password);const response=page.waitForResponse(r=>r.url().endsWith('/auth/browser/'+(admin?'admin':'customer')+'/login'));await button(admin?'Đăng nhập quản trị':'Đăng nhập');const r=await response;assert.equal(r.status(),201);const data=await r.json();assert.equal(data.refreshToken,undefined);return data.accessToken;}
    async function assertPrivateCookies(){
      const cookies=await context.cookies();assert.equal(cookies.length,2);
      for(const scope of ['customer','admin']){const c=cookies.find(c=>c.name==='wearly_'+scope+'_session');assert(c);assert(c.httpOnly);assert.equal(c.sameSite,'Strict');assert.equal(c.path,'/api/v1/auth/browser/'+scope);assert.equal(c.secure,false);assert(c.expires>Date.now()/1000);}
      const visible=await page.evaluate(()=>({cookie:document.cookie,local:Object.values(localStorage),session:Object.values(sessionStorage)}));
      assert.equal(visible.cookie.includes('wearly_'),false);
      const stored=JSON.stringify(visible);for(const c of cookies)assert(!stored.includes(c.value));assert(!stored.includes('eyJ'));
      return cookies;
    }
    await page.goto('http://127.0.0.1:4183/#/login?next=%2Faccount');await semantics();
    const access=await login(email);await page.getByText('Chào Khách thử phiên.',{exact:true}).waitFor();
    await route('/admin/staff');await login(adminEmail,true);await page.getByText('Nhân sự & quyền',{exact:true}).last().waitFor();
    const original=await assertPrivateCookies();
    await page.reload();await semantics();await page.getByText('Nhân sự & quyền',{exact:true}).last().waitFor();
    assert.equal(await page.getByRole('button',{name:'Đăng nhập quản trị',exact:true}).count(),0);
    await page.screenshot({path:path.join(output,'staff-reloaded-desktop.png')});
    const csrf=await page.evaluate(async url=>(await fetch(url+'/auth/browser/customer/refresh',{method:'POST',credentials:'include'})).status,url);assert.equal(csrf,403);
    const renewal=await page.evaluate(async url=>Promise.all(Array.from({length:4},async()=>{
      const r=await fetch(url+'/auth/browser/customer/refresh',{method:'POST',credentials:'include',headers:{'X-Wearly-Browser':'1','Content-Type':'application/json'},body:'{}'});const body=await r.json();return {status:r.status,hasRefresh:'refreshToken'in body};
    })),url);assert(renewal.every(r=>r.status===201&&!r.hasRefresh));
    const renewed=await assertPrivateCookies();for(const before of original){const after=renewed.find(c=>c.name===before.name);assert.equal(after.value,before.value);assert.equal(after.expires,before.expires);}
    const secondary=await context.newPage();observe(secondary,'secondary');page=secondary;
    await page.goto('http://127.0.0.1:4183/#/account');await semantics();await page.getByText('Chào Khách thử phiên.',{exact:true}).waitFor();
    await page.setViewportSize({width:375,height:900});await page.screenshot({path:path.join(output,'customer-second-tab-mobile.png')});
    page=primary;await page.bringToFront();const expired=await expiredAccess(access);let injected=false;
    await page.route('**/api/v1/orders?*',async interception=>{
      if(!injected&&interception.request().method()==='GET'){injected=true;await interception.continue({headers:{...interception.request().headers(),authorization:'Bearer '+expired}});}else await interception.continue();
    });
    const resumed=page.waitForResponse(r=>r.url().endsWith('/auth/browser/customer/refresh')&&r.status()===201);
    await route('/account/orders');await resumed;assert(injected);await page.unroute('**/api/v1/orders?*');
    await route('/account');await button('Đăng xuất');await page.getByText('Đăng nhập để tiếp tục',{exact:true}).waitFor();
    assert(!(await context.cookies()).some(c=>c.name==='wearly_customer_session'));
    await route('/login?next=%2Faccount');await login(otherEmail);await page.getByText('Chào Khách thứ hai.',{exact:true}).waitFor();
    console.log('Chrome sessions: reload, parallel renewal, expired access and second-account login passed.');
    const marker=requests.length;page=secondary;await page.bringToFront();await route('/account/orders');await page.getByText('Đăng nhập để tiếp tục',{exact:true}).waitFor();
    const oldTab=requests.slice(marker).filter(r=>r.tab==='secondary');
    assert(oldTab.some(r=>r.path.endsWith('/orders')&&r.status===401));
    assert(oldTab.some(r=>r.path.endsWith('/auth/browser/customer/refresh')&&r.status===201));
    assert(!oldTab.some(r=>r.path.endsWith('/orders')&&r.status===200),'Old tab replayed request as the new cookie owner');
    await page.screenshot({path:path.join(output,'changed-account-mobile.png')});
    page=primary;await page.bringToFront();await route('/account');await button('Đăng xuất');
    await route('/admin/staff');await page.reload();await semantics();await page.getByText('Nhân sự & quyền',{exact:true}).last().waitFor();
    await revokeStaff();await page.reload();await semantics();await page.getByRole('button',{name:'Đăng nhập quản trị',exact:true}).waitFor();
    await login(adminEmail,true);await page.getByText('Hỗ trợ khách hàng',{exact:true}).last().waitFor();
    await (async()=>{await page.getByRole('button',{name:'Tài khoản quản trị',exact:true}).click();await page.getByRole('menuitem',{name:'Đăng xuất',exact:true}).or(page.getByRole('button',{name:'Đăng xuất',exact:true})).first().click();})();await page.waitForTimeout(300);
    await page.reload();await semantics();await page.getByRole('button',{name:'Đăng nhập quản trị',exact:true}).waitFor();
    assert.equal((await context.cookies()).filter(c=>c.name.startsWith('wearly_')).length,0);
    assert.deepEqual(errors,[]);assert(!requests.some(r=>r.status>=500));
    // Actual Set-Cookie arrives after the UI timeout; compensating logout fails.
    // The non-secret recovery marker must survive reload and block restoration.
    await route('/login?next=%2Faccount');
    let rejectedCleanups=0;
    await page.route('**/auth/browser/customer/logout',async interception=>{
      rejectedCleanups++;await interception.fulfill({status:503,contentType:'application/json',body:'{}'});
    });
    await page.route('**/auth/browser/customer/login',async interception=>{
      const response=await interception.fetch();await page.waitForTimeout(16000);
      await interception.fulfill({response});
    });
    await fill('Email',email);await fill('Mật khẩu',password);
    const failedCleanup=page.waitForResponse(r=>r.url().endsWith('/auth/browser/customer/logout')&&r.status()===503);
    await button('Đăng nhập');
    await page.getByText('Chưa xác nhận được đăng nhập. Hãy thử lại để đóng phiên chưa xác nhận trước khi tiếp tục.',{exact:true}).waitFor();
    await failedCleanup;
    assert((await context.cookies()).some(c=>c.name==='wearly_customer_session'));
    assert.equal(await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('wearly.auth-recovery.v1:')).length),1);
    const recoveryMarker=requests.length;
    await page.reload();await semantics();
    await page.getByText('Chưa khôi phục được phiên đăng nhập',{exact:true}).waitFor();
    assert(!requests.slice(recoveryMarker).some(r=>r.path.endsWith('/auth/browser/customer/refresh')));
    assert(rejectedCleanups>=2);
    await page.unroute('**/auth/browser/customer/logout');await page.unroute('**/auth/browser/customer/login');
    await page.getByRole('button',{name:'Thử khôi phục lại',exact:true}).click();
    await page.getByRole('button',{name:'Đăng nhập',exact:true}).last().waitFor();
    assert(!(await context.cookies()).some(c=>c.name==='wearly_customer_session'));
    assert.equal(await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('wearly.auth-recovery.v1:')).length),0);
    await login(email);await page.getByText('Chào Khách thử phiên.',{exact:true}).waitFor();
    await button('Đăng xuất');
    assert.deepEqual(errors,[]);
    assert.equal(requests.filter(r=>r.status>=500).length,rejectedCleanups);
    console.log('PASS Chrome abandoned login: late cookie, failed cleanup, durable reload gate and confirmed cleanup retry.');
    console.log('PASS Chrome sessions: HttpOnly scoped cookies, reload/tabs, bounded parallel renewal, expired access recovery, CSRF, account-change isolation, scoped logout, role revocation and375/1440.');
  } catch(error){if(page){fs.writeFileSync(path.join(output,'failure-aria.txt'),await page.locator('body').ariaSnapshot());await page.screenshot({path:path.join(output,'failure.png')});}throw error;}
  finally{fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,requests},null,2));await browser?.close();await new Promise(r=>server.close(r));}
};
