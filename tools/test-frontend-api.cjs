// Bounded real API verification. Only unique synthetic rows in the dedicated
// *_test database are created/deleted; the normal development API stays running.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { randomUUID, createHmac } = require('node:crypto');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const backend = path.join(root, 'backend');
const requireBackend = createRequire(path.join(backend, 'package.json'));
const dotenv = requireBackend('dotenv');
const normal = dotenv.parse(fs.readFileSync(path.join(backend, '.env')));
const test = dotenv.parse(fs.readFileSync(path.join(backend, '.env.test')));
const target = new URL(test.TEST_DATABASE_URL);
if (!/^\/[a-zA-Z0-9_]+_test$/.test(target.pathname) || target.href === new URL(normal.DATABASE_URL).href) {
  throw new Error('A separate *_test database is required.');
}
Object.assign(process.env, normal, { DATABASE_URL: target.href, NODE_ENV: 'test',
  JWT_ACCESS_SECRET: randomUUID() + randomUUID(), JWT_REFRESH_SECRET: randomUUID() + randomUUID(),
  AI_QUEUE_PREFIX: 'flutter-test-' + randomUUID(), CORS_ORIGINS: 'http://127.0.0.1:4183' });
process.env.PASSWORD_RECOVERY_ENABLED = 'false';
process.env.LOCAL_MAIL_ENABLED = 'false';
process.env.VNPAY_ENABLED = 'false';
process.env.GEMINI_API_KEY = ' ';
process.chdir(backend);
requireBackend('reflect-metadata');
const { NestFactory } = requireBackend('@nestjs/core');
const { PrismaService } = requireBackend('./dist/database/prisma.service');
const { configureApp } = requireBackend('./dist/bootstrap');
const fixture = 'flutter-test-' + randomUUID();
const browser = process.argv.includes('--browser');
const admin = process.argv.includes('--admin');
const wishlist = process.argv.includes('--wishlist');
const reviews = process.argv.includes('--reviews');
const style = process.argv.includes('--style');
const recovery = process.argv.includes('--recovery');
const payments = process.argv.includes('--payments');
const promotions = process.argv.includes('--promotions');
const shipments = process.argv.includes('--shipments');
const returns = process.argv.includes('--returns');
const refunds = process.argv.includes('--refunds');
const support = process.argv.includes('--support');
const staffMode = process.argv.includes('--staff');
const sessions = process.argv.includes('--sessions');
const stylist = process.argv.includes('--stylist');
const tryon = process.argv.includes('--tryon');
const operations = process.argv.includes('--operations');
const mailpit = process.argv.includes('--mailpit');
const promotionCode = 'BROWSER' + fixture.replaceAll('-', '').slice(-12).toUpperCase();
if (admin || tryon || operations) {
  process.env.S3_BUCKET = test.TEST_S3_BUCKET || normal.S3_BUCKET + '-test';
  if (!process.env.S3_BUCKET.endsWith('-test') || process.env.S3_BUCKET === normal.S3_BUCKET)
    throw new Error('Catalog browser upload requires a dedicated test bucket.');
}
function flutter(args) {
  const binary = path.join(root, '.tools/flutter/bin/flutter.bat');
  // All arguments below are local constants, loopback URLs or generated UUIDs.
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', `""${binary}" ${args.join(' ')}"`],
      { cwd: path.join(root, 'frontend'), stdio: 'inherit', windowsHide: true, windowsVerbatimArguments: true });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error('Flutter command failed: ' + code)));
  });
}
async function main() {
  let smtp, recoveryWorker, recoveryQueue, mailWorker, tryonWorker, tryonQueue, suiteLock, operationsQueue, operationsHeartbeat;
  const releaseTryonGates=[];
  const mails = [];
  if (support || (recovery && mailpit)) {
    const health=await fetch('http://127.0.0.1:8025/livez',{signal:AbortSignal.timeout(2000)});
    if(!health.ok)throw Error('Start native Mailpit first');
    Object.assign(process.env,{LOCAL_MAIL_ENABLED:support?'true':'false',PASSWORD_RECOVERY_ENABLED:recovery?'true':'false',SMTP_HOST:'127.0.0.1',SMTP_PORT:'1025',SMTP_SECURE:'false',SMTP_ALLOW_INSECURE_LOCAL:'true',SMTP_FROM:'store@example.test',SMTP_USER:'',SMTP_PASSWORD:'',PASSWORD_RESET_WEB_URL:'http://127.0.0.1:4183/#/reset-password'});
  }
  if (recovery && !mailpit) {
    const { SMTPServer } = requireBackend('smtp-server');
    smtp = new SMTPServer({ authOptional: true, disabledCommands: ['AUTH', 'STARTTLS'], logger: false,
      onData(stream, _session, callback) {
        let text = '';
        stream.on('data', chunk => { text += chunk.toString(); });
        stream.on('end', () => { mails.push(text); callback(); });
      },
    });
    await new Promise(resolve => smtp.listen(0, '127.0.0.1', resolve));
    Object.assign(process.env, { PASSWORD_RECOVERY_ENABLED: 'true', SMTP_HOST: '127.0.0.1',
      SMTP_PORT: String(smtp.server.address().port), SMTP_SECURE: 'false', SMTP_ALLOW_INSECURE_LOCAL: 'true',
      SMTP_FROM: 'store@example.test', SMTP_USER: '', SMTP_PASSWORD: '',
      PASSWORD_RESET_WEB_URL: 'http://127.0.0.1:4183/#/reset-password',
    });
  }
  const fixtureSecret = randomUUID()+randomUUID();
  if(payments || refunds) Object.assign(process.env,{ VNPAY_ENABLED:'true',VNPAY_TMN_CODE:'TEST0001',VNPAY_HASH_SECRET:fixtureSecret,
    VNPAY_RETURN_URL:'http://127.0.0.1:3000/api/v1/payments/vnpay/return',VNPAY_WEB_RETURN_URL:'http://127.0.0.1:4183/#/payments/return' });
  let fixturePaid = false;
  const refundFixtures = new Map();
  const fixtureHttp = async (_url, init) => {
    const body=JSON.parse(init.body);
    if(refunds) {
      if(body.vnp_Command==='refund') {
        if(refundFixtures.has(body.vnp_RequestId))throw Error('Duplicate outbound refund');
        refundFixtures.set(body.vnp_RequestId,{info:body.vnp_OrderInfo,amount:body.vnp_Amount,reference:body.vnp_TxnRef,number:String(Date.now()),type:body.vnp_TransactionType});
      }
      const row=body.vnp_Command==='refund'?refundFixtures.get(body.vnp_RequestId):[...refundFixtures.values()].find(r=>r.number===body.vnp_TransactionNo);
      if(!row)throw Error('Unknown synthetic refund');
      const reply={vnp_ResponseId:randomUUID().replaceAll('-',''),vnp_Command:body.vnp_Command,vnp_ResponseCode:'00',vnp_Message:'Signed local refund fixture',vnp_TmnCode:'TEST0001',vnp_TxnRef:row.reference,vnp_Amount:row.amount,vnp_BankCode:'NCB',vnp_PayDate:'20261022120000',vnp_TransactionNo:row.number,vnp_TransactionType:row.type,vnp_TransactionStatus:body.vnp_Command==='refund'?'05':'00',vnp_OrderInfo:row.info};
      if(body.vnp_Command==='querydr')Object.assign(reply,{vnp_PromotionCode:'',vnp_PromotionAmount:''});
      reply.vnp_SecureHash=createHmac('sha512',fixtureSecret).update(Object.values(reply).join('|')).digest('hex');
      return Response.json(reply);
    }
    const fields = ['vnp_ResponseId','vnp_Command','vnp_ResponseCode','vnp_Message','vnp_TmnCode','vnp_TxnRef','vnp_Amount','vnp_BankCode','vnp_PayDate','vnp_TransactionNo','vnp_TransactionType','vnp_TransactionStatus','vnp_OrderInfo','vnp_PromotionCode','vnp_PromotionAmount'];
    const reply = {vnp_ResponseId:randomUUID().replaceAll('-',''),vnp_Command:'querydr',vnp_ResponseCode:'00',vnp_Message:'Signed local fixture',vnp_TmnCode:'TEST0001',vnp_TxnRef:body.vnp_TxnRef,vnp_Amount:'52000000',vnp_BankCode:'NCB',vnp_PayDate:'20261021120000',vnp_TransactionNo:String(Date.now()),vnp_TransactionType:'01',vnp_TransactionStatus:fixturePaid?'00':'01',vnp_OrderInfo:'Test',vnp_PromotionCode:'',vnp_PromotionAmount:''};
    reply.vnp_SecureHash=createHmac('sha512',fixtureSecret).update(fields.map(k=>reply[k]).join('|')).digest('hex');
    return Response.json(reply);
  };
  if(stylist)Object.assign(process.env,{GEMINI_API_KEY:'local-fixture-not-a-real-key-2026',AI_STYLIST_USER_DAILY_LIMIT:'3'});
  let fixturePhoto;
  if(tryon) {
    Object.assign(process.env,{GEMINI_API_KEY:'local-fixture-not-a-real-key-2026',AI_TRYON_USER_DAILY_LIMIT:'3',
      S3_ENDPOINT:test.TEST_S3_ENDPOINT||normal.S3_ENDPOINT,
      REDIS_HOST:test.TEST_REDIS_HOST||normal.REDIS_HOST,REDIS_PORT:test.TEST_REDIS_PORT||normal.REDIS_PORT});
    fixturePhoto=await requireBackend('sharp')({create:{width:240,height:320,channels:3,background:'#b8c4d4'}}).png().toBuffer();
    const {Client}=requireBackend('pg');suiteLock=new Client({connectionString:target.href});await suiteLock.connect();
    const lock=await suiteLock.query('SELECT pg_try_advisory_lock(hashtext($1)) AS locked',['wearly-worker-e2e']);
    if(!lock.rows[0].locked){await suiteLock.end();throw Error('Another worker suite uses the test database');}
    const pending=await suiteLock.query(`SELECT EXISTS(SELECT 1 FROM "OutboxEvent" WHERE "publishedAt" IS NULL) OR EXISTS(SELECT 1 FROM "AIJob" WHERE status IN ('PENDING','PROCESSING')) AS pending`);
    if(pending.rows[0].pending){await suiteLock.end();throw Error('Unfinished AI fixtures exist; inspect before browser worker');}
  }
  const { AppModule } = requireBackend('./dist/app.module');
  let fixtureAiCalls = 0;
  const fixtureAiHttp = async (endpoint, init) => {
    if(endpoint !== 'https://generativelanguage.googleapis.com/v1/interactions')throw Error('Unexpected Gemini endpoint');
    if(tryon) {
      const body=JSON.parse(init.body),images=body.input.filter(x=>x.type==='image');
      if(body.store!==false||body.background!==false||images.length!==2||images.some(x=>!x.data||x.uri))throw Error('Invalid private inline image request');
      fixtureAiCalls++;
      if(fixtureAiCalls===3)return new Response('fixture rate limit',{status:429});
      return Response.json({status:'completed',steps:[{type:'model_output',content:[{type:'image',mime_type:'image/png',data:fixturePhoto.toString('base64')}]}],usage:{total_input_tokens:42,total_output_tokens:20}});
    }
    const body=JSON.parse(init.body),input=JSON.parse(body.input);
    if(body.store!==false || !input.catalog.some(p=>p.sku===fixture))throw Error('Invalid stateless catalog request');
    fixtureAiCalls++;
    if(fixtureAiCalls===3)return new Response('fixture rate limit',{status:429});
    return Response.json({status:'completed',steps:[{type:'model_output',content:[{type:'text',text:JSON.stringify({message:'Áo cotton phù hợp cho ngày đi làm.',skus:[fixture]})}]}],usage:{total_input_tokens:42,total_output_tokens:20}});
  };
  const app = stylist || tryon
    ? (await requireBackend('@nestjs/testing').Test.createTestingModule({imports:[AppModule]}).overrideProvider(requireBackend('./dist/integrations/ai-providers/gemini.client').GEMINI_HTTP).useValue(fixtureAiHttp).compile()).createNestApplication({logger:false})
    : payments || refunds
    ? (await requireBackend('@nestjs/testing').Test.createTestingModule({imports:[AppModule]}).overrideProvider('VNPAY_HTTP').useValue(fixtureHttp).compile()).createNestApplication({logger:false})
    : await NestFactory.create(AppModule, { logger: false });
  const db = app.get(PrismaService);
  let category, brand, product;
  try {
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    category = await db.category.create({ data: { slug: fixture, name: 'Áo kiểm thử' } });
    brand = await db.brand.create({ data: { slug: fixture, name: 'Wearly kiểm thử' } });
    product = await db.product.create({ data: { slug: fixture, name: 'Áo cotton kiểm thử', description: 'Sản phẩm chỉ dành cho kiểm thử.', material: 'Cotton', style: 'Tối giản', tryOnSupported:tryon,
      categoryId: category.id, brandId: brand.id,
      images: { create: { url: 'assets/images/shirt.jpg', alt: 'Áo cotton', position: 0 } },
      variants: { create: { sku: fixture, size: 'M', color: stylist?'Trắng thử nghiệm':'Trắng', colorHex: '#FFFFFF', price: '490000', inventory: { create: { quantity: 10 } } } } } });
    const url = (await app.getUrl()) + '/api/v1';
    if(payments) app.get(requireBackend('@nestjs/config').ConfigService).set('VNPAY_RETURN_URL',url+'/payments/vnpay/return');
    if(tryon) {
      const config=app.get(requireBackend('@nestjs/config').ConfigService);
      const storage=app.get(requireBackend('./dist/integrations/storage/storage.service').StorageService);
      const {AiProcessor}=requireBackend('./dist/worker/ai.processor');
      tryonWorker=new AiProcessor(db,config,app.get(requireBackend('./dist/integrations/ai-providers/try-on.provider').TryOnProvider),storage,
        app.get(requireBackend('./dist/modules/ai/ai-usage.service').AiUsageService),app.get(requireBackend('./dist/integrations/ai-providers/garment-reader.service').GarmentReader));
      tryonWorker.onModuleInit();
      tryonQueue=new (requireBackend('bullmq').Queue)('wearly-try-on',{prefix:process.env.AI_QUEUE_PREFIX,connection:{host:process.env.REDIS_HOST,port:Number(process.env.REDIS_PORT)}});
      const email=fixture+'@example.com',password='Tryon-browser-fixture-2026',accounts=[];
      for(const who of [email,'browser-'+fixture+'@example.com']) {
        const r=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Khách thử đồ',email:who,password})});
        if(r.status!==201)throw Error('Try-on fixture registration failed');accounts.push(await r.json());
      }
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      const read=(endpoint,account=1)=>fetch(url+'/'+endpoint,{headers:{Authorization:'Bearer '+accounts[account].accessToken}});
      await require('./verify-tryon-browser.cjs')({root,url,email,password,fixture,photo:fixturePhoto,callCount:()=>fixtureAiCalls,
        pauseUpload:()=>{
          let release,entered;const gate=new Promise(r=>{release=r}),started=new Promise(r=>{entered=r}),original=storage.putImage.bind(storage);
          storage.putImage=async(...args)=>{storage.putImage=original;entered();await gate;return original(...args);};
          releaseTryonGates.push(release);return {wait:()=>started,release};
        },
        holdJob:async()=>{
          const held=new (requireBackend('pg').Client)({connectionString:target.href});await held.connect();await held.query('BEGIN');
          await held.query("SELECT pg_advisory_xact_lock(hashtextextended('ai:usage:reservation',0))");
          let released=false;const release=async()=>{if(released)return;released=true;try{await held.query('COMMIT');}finally{await held.end();}};
          releaseTryonGates.push(release);
          return {release,wait:async()=>{for(let i=0;i<80;i++){const r=await held.query("SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND NOT granted) AS waiting");if(r.rows[0].waiting)return;await new Promise(r=>setTimeout(r,50));}throw Error('Try-on POST did not wait for reservation');}};
        },
        foreignRead:async endpoint=>(await read(endpoint)).status,
        deletedRead:async endpoint=>(await read(endpoint,0)).status,
        disable:()=>config.set('GEMINI_API_KEY',''),
      });
      const owner={userId:accounts[0].user.id};
      const jobs=await db.aIJob.findMany({where:owner}),usage=await db.aiUsage.findMany({where:owner}),images=await db.imageAsset.findMany({where:owner});
      if(jobs.length!==3||usage.length!==3||usage.filter(r=>r.status==='COMPLETED').length!==2||fixtureAiCalls!==3||images.length!==1||!images[0].deletedAt)throw Error('Try-on accounting/deletion mismatch');
      await app.get(requireBackend('./dist/modules/uploads/image-lifecycle.service').ImageLifecycleService).purge(images[0].id);
      const results=await db.tryOnResult.findMany({where:{job:owner}});
      for(const key of [images[0].objectKey,...results.map(r=>r.objectKey)]) {
        let missing=false;try{await storage.readImage(key);}catch(error){if(error.$metadata?.httpStatusCode===404)missing=true;else throw error;}
        if(!missing)throw Error('Private object remains after purge');
      }
      console.log('PASS try-on database: one source, three accepted attempts, two completions, one rate limit, source/results revoked and physically purged. Deterministic Gemini HTTP only.');
    } else if (recovery) {
      const { ConfigService } = requireBackend('@nestjs/config');
      const { RecoveryService } = requireBackend('./dist/modules/recovery/recovery.service');
      const { RecoveryWorker } = requireBackend('./dist/worker/recovery.worker');
      const { Queue } = requireBackend('bullmq');
      recoveryWorker = new RecoveryWorker(app.get(ConfigService), app.get(RecoveryService));
      recoveryWorker.onModuleInit();
      recoveryQueue = new Queue('wearly-password-recovery', { prefix: process.env.AI_QUEUE_PREFIX,
        connection: { host: process.env.REDIS_HOST, port: Number(process.env.REDIS_PORT) } });
      const email = fixture + '@example.com', password = 'Browser-original-Password-2026';
      const registered = await fetch(url + '/auth/register', { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, name: 'Khôi phục kiểm thử' }) });
      if (registered.status !== 201) throw new Error('Recovery fixture registration failed');
      const account = await registered.json();
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-recovery-browser.cjs')({ root, email, password, url, nextPassword: 'Browser-replaced-Password-2026',
        getLink: async () => {
          for (let i = 0; i < 100; i++) {
            if(mailpit) {
              const result=await (await fetch('http://127.0.0.1:8025/api/v1/search?query='+encodeURIComponent('to:'+email))).json();
              for(const item of result.messages??[]) {
                const message=await (await fetch('http://127.0.0.1:8025/api/v1/message/'+item.ID)).json();
                const match=message.Text?.match(/http:\/\/127\.0\.0\.1:4183\/#\/reset-password\?token=[A-Za-z0-9_-]{43}/);
                if(match)return match[0];
              }
            }
            for (const mail of mails) {
              const split = mail.indexOf('\r\n\r\n'), headers = mail.slice(0, split), body = mail.slice(split + 4);
              const decoded = /Content-Transfer-Encoding: base64/i.test(headers)
                ? Buffer.from(body.replace(/\s/g, ''), 'base64').toString()
                : body.replace(/=\r\n/g, '').replace(/=([0-9A-F]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
              const link = decoded.match(/http:\/\/127\.0\.0\.1:4183\/#\/reset-password\?token=[A-Za-z0-9_-]{43}/)?.[0];
              if (link) return link;
            }
            await new Promise(resolve => setTimeout(resolve, 50));
          }
          throw new Error('Local SMTP reset link did not arrive');
        },
      });
      const oldSession = await fetch(url + '/auth/me', { headers: { Authorization: 'Bearer ' + account.accessToken } });
      if (oldSession.status !== 401) throw new Error('Pre-reset session remained active');
      if (await db.passwordResetToken.count({ where: { userId: account.user.id, consumedAt: null } }) !== 0)
        throw new Error('Unconsumed reset token remained');
      console.log('PASS recovery database: token consumed and original session revoked.');
    } else if(stylist) {
      const email=fixture+'@example.com',otherEmail='browser-'+fixture+'@example.com',password='Stylist-browser-fixture-2026';
      const accounts=[];
      for(const who of [email,otherEmail]) {
        const r=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Khách Stylist',email:who,password})});
        if(r.status!==201)throw Error('Stylist fixture registration failed');accounts.push(await r.json());
      }
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      await require('./verify-stylist-browser.cjs')({root,url,email,password,callCount:()=>fixtureAiCalls,
        foreignRead:async key=>(await fetch(url+'/ai/stylist/requests/'+key,{headers:{Authorization:'Bearer '+accounts[1].accessToken}})).status,
        disable:()=>app.get(requireBackend('@nestjs/config').ConfigService).set('GEMINI_API_KEY',''),
      });
      const rows=await db.aiUsage.findMany({where:{userId:accounts[0].user.id}});
      if(rows.length!==3||rows.filter(r=>r.status==='COMPLETED').length!==2||fixtureAiCalls!==3)throw Error('Incorrect Stylist usage/receipt accounting');
      console.log('PASS Stylist database: three accepted attempts, two results, one rate limit; Gemini HTTP was a deterministic test double.');
    } else if(operations) {
      const email=fixture+'@example.com',managerEmail='browser-'+fixture+'@example.com',customerEmail='admin-'+fixture+'@example.com',password='Operations-browser-fixture-2026';
      const accounts={};
      for(const [who,role] of [[email,'ADMIN'],[managerEmail,'MANAGER'],[customerEmail,'CUSTOMER']]) {
        const r=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Kiểm thử vận hành',email:who,password})});
        if(r.status!==201)throw Error('Operations fixture registration failed');accounts[who]=await r.json();
        await db.user.update({where:{id:accounts[who].user.id},data:{role}});
      }
      const now=new Date();
      await db.aiUsage.createMany({data:[
        {userId:accounts[email].user.id,kind:'TRY_ON',requestKey:randomUUID(),inputHash:'a'.repeat(64),model:'gemini-fixture',estimatedCostVnd:3000,status:'RESERVED',deadlineAt:new Date(now.getTime()-1000),expiresAt:new Date(now.getTime()+3600000)},
        {userId:accounts[email].user.id,kind:'STYLIST',requestKey:randomUUID(),inputHash:'b'.repeat(64),model:'gemini-fixture',estimatedCostVnd:500,status:'FAILED',errorCode:'private-fixture-error',deadlineAt:now,expiresAt:new Date(now.getTime()+3600000)},
      ]});
      const config=app.get(requireBackend('@nestjs/config').ConfigService),redisPort=config.get('REDIS_PORT');
      const {WorkerHeartbeat}=requireBackend('./dist/modules/operations/worker-heartbeat.service');
      const {operationsResources}=requireBackend('./dist/modules/operations/operations.probes');
      operationsQueue=new (requireBackend('bullmq').Queue)('wearly-try-on',{prefix:process.env.AI_QUEUE_PREFIX,connection:{host:config.get('REDIS_HOST'),port:redisPort}});
      await operationsQueue.add('synthetic-monitor',{private:'private-fixture-payload'},{jobId:randomUUID()});
      operationsHeartbeat=new WorkerHeartbeat(config,operationsResources);
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      await require('./verify-operations-browser.cjs')({root,url,email,managerEmail,password,
        startWorker:()=>operationsHeartbeat.onModuleInit(),stopWorker:()=>operationsHeartbeat.onModuleDestroy(),
        redisUnavailable:(disabled)=>config.set('REDIS_PORT',disabled?1:redisPort),
        customerDenied:async()=>{const r=await fetch(url+'/admin/operations',{headers:{Authorization:'Bearer '+accounts[customerEmail].accessToken}});if(r.status!==403)throw Error('Customer can access operations');},
      });
    } else if(sessions) {
      const email=fixture+'@example.com',otherEmail='browser-'+fixture+'@example.com',adminEmail='admin-'+fixture+'@example.com',password='Browser-only-Password-2026';
      const accounts={};
      for(const [who,name,role] of [[email,'Khách thử phiên','CUSTOMER'],[otherEmail,'Khách thứ hai','CUSTOMER'],[adminEmail,'Quản trị thử phiên','ADMIN']]) {
        const response=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,email:who,password})});
        if(response.status!==201)throw Error('Session fixture registration failed');
        accounts[who]=await response.json();await db.user.update({where:{id:accounts[who].user.id},data:{role}});
      }
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      await require('./verify-sessions-browser.cjs')({root,url,email,otherEmail,adminEmail,password,
        expiredAccess:async token=>{
          const {JwtService}=requireBackend('@nestjs/jwt'),jwt=app.get(JwtService),claims=jwt.decode(token);
          if(claims.sub!==accounts[email].user.id)throw Error('Unexpected fixture identity');
          return jwt.signAsync({sub:claims.sub,sid:claims.sid,typ:'access'},{secret:process.env.JWT_ACCESS_SECRET,expiresIn:-1,algorithm:'HS256',issuer:'wearly',audience:'wearly-api'});
        },
        revokeStaff:async()=>{
          await db.user.update({where:{id:accounts[otherEmail].user.id},data:{role:'ADMIN'}});
          const response=await fetch(url+'/admin/staff/'+accounts[adminEmail].user.id,{method:'PATCH',headers:{'Content-Type':'application/json',Authorization:'Bearer '+accounts[otherEmail].accessToken},body:JSON.stringify({expectedVersion:0,role:'SUPPORT',active:true})});
          if(response.status!==200)throw Error('Session staff revocation fixture failed');
        }});
    } else if(staffMode) {
      const email='admin-'+fixture+'@example.com',warehouseEmail='browser-'+fixture+'@example.com',supportEmail=fixture+'@example.com',password='Browser-only-Password-2026';
      const accounts={};
      for(const who of [email,warehouseEmail,supportEmail]){
        const response=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Nhân viên kiểm thử',email:who,password})});
        if(response.status!==201)throw Error('Staff account fixture failed');accounts[who]=await response.json();
      }
      await db.user.update({where:{id:accounts[email].user.id},data:{role:'ADMIN'}});
      const variant=await db.productVariant.findFirstOrThrow({where:{productId:product.id}});
      const order=await db.order.create({data:{userId:accounts[supportEmail].user.id,idempotencyKey:randomUUID(),requestHash:'staff-fixture',addressSnapshot:{recipient:'Staff fixture',phone:'0901234567',address:'Test address'},subtotal:'490000',shipping:'30000',total:'520000',payment:{create:{provider:'cod',amount:'520000'}},items:{create:{variantId:variant.id,name:'Staff fixture',sku:variant.sku,slug:fixture,size:'M',color:'Trắng',image:'assets/images/shirt.jpg',unitPrice:'490000',quantity:1}}}});
      const ticketResponse=await fetch(url+'/support',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestKey:randomUUID(),name:'Khách thử quyền',email:supportEmail,message:'Cần hỗ trợ chọn kích cỡ phù hợp.'})});
      if(ticketResponse.status!==201)throw Error('Staff support fixture failed');const ticket=await ticketResponse.json();
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      await require('./verify-staff-browser.cjs')({root,url,email,warehouseEmail,supportEmail,password,orderId:order.id,ticketId:ticket.id,demote:async()=>{
        const response=await fetch(url+'/admin/staff/'+accounts[supportEmail].user.id,{method:'PATCH',headers:{'Content-Type':'application/json',Authorization:'Bearer '+accounts[email].accessToken},body:JSON.stringify({expectedVersion:1,role:'CUSTOMER',active:true})});
        if(response.status!==200)throw Error('Staff demotion failed');
      }});
      const result=await db.order.findUniqueOrThrow({where:{id:order.id},include:{payment:true}});
      const inventory=await db.inventory.findUniqueOrThrow({where:{variantId:variant.id}});
      if(result.status!=='DELIVERED'||result.payment.status!=='PENDING'||inventory.quantity!==12)throw Error('Staff fulfillment changed forbidden state');
      if(await db.supportReply.count({where:{ticketId:ticket.id}})!==1)throw Error('Support reply did not persist');
      console.log('PASS staff roles, exact inventory adjustment, delivery without COD collection and support persistence.');
    } else if(support) {
      const {MailService}=requireBackend('./dist/modules/mail/mail.service');
      const {MailWorker}=requireBackend('./dist/worker/mail.worker');
      mailWorker=new MailWorker(app.get(MailService));mailWorker.onModuleInit();
      const email='admin-'+fixture+'@example.com',customerEmail=fixture+'@example.com',password='Browser-only-Password-2026';
      for(const [who,name,role] of [[email,'Support admin','ADMIN'],[customerEmail,'Support customer','CUSTOMER']]) {
        const r=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,email:who,password})});
        if(r.status!==201)throw Error('Support account fixture failed');const a=await r.json();await db.user.update({where:{id:a.user.id},data:{role}});
      }
      const user=await db.user.findUniqueOrThrow({where:{email:customerEmail}}),variant=await db.productVariant.findFirstOrThrow({where:{productId:product.id}});
      const order=await db.order.create({data:{userId:user.id,idempotencyKey:randomUUID(),requestHash:'support-fixture',addressSnapshot:{recipient:'Support customer',phone:'0901234567',address:'Test address'},subtotal:'490000',shipping:'30000',total:'520000',payment:{create:{provider:'cod',status:'PENDING',amount:'520000'}},items:{create:{variantId:variant.id,name:'Support fixture',sku:variant.sku,slug:fixture,size:'M',color:'Trắng',image:'assets/images/shirt.jpg',unitPrice:'490000',quantity:1}}}});
      await flutter(['build','web','--release','--dart-define=USE_REMOTE_API=true','--dart-define=API_BASE_URL='+url]);
      const ticketId=await require('./verify-support-browser.cjs')({root,email,customerEmail,password,orderId:order.id});
      const ticket=await db.supportTicket.findUniqueOrThrow({where:{id:ticketId},include:{replies:{include:{mail:true}}}});
      if(ticket.status!=='ANSWERED'||ticket.replies.length!==1||ticket.replies[0].mail.status!=='SENT')throw Error('Support persistence/delivery failed');
      const orderMail=await db.mailOutbox.findUniqueOrThrow({where:{eventKey:`order:${order.id}:1`}});
      if(orderMail.status!=='SENT')throw Error('Order notification not sent');
      console.log('PASS support receipt, staff reply and order notification persisted and delivered to native local inbox.');
    } else if (returns || refunds) {
      const password = 'Browser-only-Password-2026', email = 'admin-' + fixture + '@example.com', customerEmail = 'browser-' + fixture + '@example.com';
      const send = async (method, endpoint, body, token, headers = {}) => {
        const response = await fetch(url + '/' + endpoint, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw Error('Return fixture failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const staff = await send('POST', 'auth/register', { name: 'Returns admin', email, password });
      await db.user.update({ where: { id: staff.user.id }, data: { role: 'ADMIN' } });
      const customer = await send('POST', 'auth/register', { name: 'Returns customer', email: customerEmail, password });
      const address = await send('POST', 'users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      await send('POST', 'admin/promotions', { code: promotionCode, kind: 'FIXED', amount: '50000', active: true }, staff.accessToken);
      await send('POST', 'cart/items', { sku: fixture, quantity: 2 }, customer.accessToken);
      let order = await send('POST', 'orders', { addressId: address.id, expectedSubtotal: '980000', couponCode: promotionCode, expectedDiscount: '50000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      for (const status of ['CONFIRMED', 'SHIPPED', 'DELIVERED']) order = await send('PATCH', 'admin/orders/' + order.id + '/status', { status, expectedVersion: order.version }, staff.accessToken);
      order = await send('POST', 'admin/orders/' + order.id + '/settle-cod', { amount: '960000', reference: 'COD-RETURN-FIXTURE', expectedVersion: order.version }, staff.accessToken);
      await send('POST', 'cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
      let cancelled = await send('POST', 'orders', { addressId: address.id, expectedSubtotal: '490000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      // Explicit synthetic prepaid snapshot; no claim of real gateway acceptance.
      const paymentNumber=String(Date.now());
      await db.payment.update({ where: { orderId: cancelled.id }, data: { provider: 'vnpay', status: 'PAID', providerTransactionId: paymentNumber,
        ...(refunds?{attempts:{create:{reference:randomUUID().replaceAll('-',''),amount:'520000',status:'PAID',transactionNo:paymentNumber,ipAddress:'127.0.0.1',expiresAt:new Date(Date.now()+900000)}}}:{}) } });
      cancelled = await send('PATCH', 'admin/orders/' + cancelled.id + '/status', { status: 'CONFIRMED', expectedVersion: cancelled.version }, staff.accessToken);
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-returns-browser.cjs')({ root, email, customerEmail, password, orderId: order.id, cancelId: cancelled.id, refunds });
      const returned = await db.order.findUniqueOrThrow({ where: { id: order.id }, include: { returns: { include: { items: true } }, payment: {include:{refunds:true}} } });
      if (returned.status !== 'DELIVERED' || returned.payment.status !== (refunds?'PARTIALLY_REFUNDED':'PAID') || returned.returns.length !== 1 || returned.returns[0].status !== 'RECEIVED' || returned.returns[0].amount.toString() !== '465000' || returned.returns[0].items[0].quantity !== 1) throw Error('Partial return entitlement/state mismatch');
      const stopped = await db.order.findUniqueOrThrow({ where: { id: cancelled.id }, include: { payment: {include:{refunds:true}} } });
      if (stopped.status !== 'CANCELLED' || stopped.payment.status !== (refunds?'REFUNDED':'PAID')) throw Error('Paid cancellation refund state mismatch');
      if(refunds) {
        if(returned.payment.refunds.length!==1 || returned.payment.refunds[0].amount.toString()!=='465000' || returned.payment.refunds[0].status!=='SUCCEEDED')throw Error('COD partial refund mismatch');
        if(stopped.payment.refunds.length!==1 || stopped.payment.refunds[0].amount.toString()!=='520000' || stopped.payment.refunds[0].status!=='SUCCEEDED' || refundFixtures.size!==1)throw Error('VNPay verified refund mismatch');
      }
      const inventory = await db.inventory.findFirstOrThrow({ where: { variant: { productId: product.id } } });
      if (inventory.quantity !== 9) throw Error('Return/cancellation stock compensation mismatch');
      console.log(refunds?'PASS partial COD and verified signed-fixture VNPay refund; stock unchanged by refund; one outbound sandbox fixture request.':'PASS partial discounted return, one receipt/restock, paid cancellation retains money; no real provider call.');
    } else if (shipments) {
      const password = 'Browser-only-Password-2026';
      const post = async (endpoint, body, token, headers = {}) => {
        const response = await fetch(url + '/' + endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw Error('Shipment fixture failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const email = 'admin-' + fixture + '@example.com', customerEmail = 'browser-' + fixture + '@example.com';
      const staff = await post('auth/register', { name: 'Shipment admin', email, password });
      await db.user.update({ where: { id: staff.user.id }, data: { role: 'ADMIN' } });
      const customer = await post('auth/register', { name: 'Shipment customer', email: customerEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      const orders = [];
      for (let i = 0; i < 2; i++) {
        await post('cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
        orders.push(await post('orders', { addressId: address.id, expectedSubtotal: '490000', shippingMethod: 'standard' }, customer.accessToken, { 'Idempotency-Key': randomUUID() }));
      }
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-shipment-browser.cjs')({ root, email, customerEmail, password, returnedId: orders[0].id, deliveredId: orders[1].id });
      for (const [index, expected] of [[0, 'RETURNED'], [1, 'DELIVERED']]) {
        const row = await db.order.findUniqueOrThrow({ where: { id: orders[index].id }, include: { shipment: { include: { events: true } }, payment: true, history: true } });
        if (row.status !== expected || row.shipment?.status !== expected || row.shipment.carrier !== 'local_simulator') throw Error('Persisted shipment mismatch');
        if (row.payment.status !== (index === 0 ? 'CANCELLED' : 'PENDING')) throw Error('Shipment incorrectly altered payment');
        if (row.shipment.events.length !== (index === 0 ? 6 : 2)) throw Error('Shipment event history mismatch');
      }
      const inventory = await db.inventory.findFirstOrThrow({ where: { variant: { productId: product.id } } });
      if (inventory.quantity !== 9) throw Error('Returned stock was not restored exactly once');
      console.log('PASS persisted shipment events, return stock compensation, delivered COD unpaid; no external carrier call.');
    } else if (admin) {
      if (await db.storeContent.count() !== 0) throw new Error('Admin content verification requires no pre-existing content; refusing to overwrite it.');
      const password = 'Browser-only-Password-2026';
      const post = async (path, body, token, headers = {}) => {
        const res = await fetch(url + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!res.ok) throw new Error('Admin fixture request failed: ' + path + ' ' + res.status);
        return res.json();
      };
      const email = 'admin-' + fixture + '@example.com';
      const adminUser = await post('auth/register', { name: 'Quản trị kiểm thử', email, password });
      await db.user.update({ where: { id: adminUser.user.id }, data: { role: 'ADMIN' } });
      const customerEmail = 'browser-' + fixture + '@example.com';
      const customer = await post('auth/register', { name: 'Khách kiểm thử', email: customerEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, customer.accessToken);
      await post('cart/items', { sku: fixture, quantity: 1 }, customer.accessToken);
      const order = await post('orders', { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: '490000' }, customer.accessToken, { 'Idempotency-Key': randomUUID() });
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-admin-browser.cjs')({ root, fixture, email, customerEmail, password, orderId: order.id });
      const saved = await db.product.findUniqueOrThrow({ where: { slug: fixture + '-admin' }, include: { variants: { include: { inventory: true } }, images: true, category: true, brand: true } });
      if (!saved.active || saved.variants.length !== 1 || saved.variants[0].inventory.quantity !== 8 || saved.variants[0].price.toString() !== '700000' || saved.images.length !== 1) throw new Error('Persisted admin product does not match browser operations');
      if (saved.category.slug !== fixture + '-taxonomy' || saved.category.name !== 'BST thu đông kiểm thử' || saved.brand.slug !== fixture + '-taxonomy' || saved.brand.name !== 'Studio thu đông kiểm thử') throw new Error('Product taxonomy assignment did not persist');
      const delivered = await db.order.findUniqueOrThrow({ where: { id: order.id }, include: { payment: { include: { settlement: true } } } });
      if (delivered.status !== 'DELIVERED' || delivered.shippingMethod !== 'standard' || delivered.payment.status !== 'PAID') throw new Error('Persisted order/COD state mismatch');
      if (delivered.payment.settlement?.reference !== 'COD-BROWSER-001' || delivered.payment.settlement?.actorId !== adminUser.user.id || delivered.payment.settlement?.amount.toString() !== '520000') throw new Error('Persisted COD receipt mismatch');
      const activity = await db.adminAuditEvent.findMany({ where: { actorId: adminUser.user.id } });
      if (!saved.images[0].url.startsWith('catalog/images/')) throw new Error('Uploaded catalog image did not persist as the cover');
      const catalog = await db.catalogAsset.findMany({ where: { productId: saved.id } });
      if (catalog.length !== 1 || !catalog[0].verifiedAt || catalog[0].deletedAt) throw new Error('Catalog asset was not verified exactly once');
      for (const action of ['PRODUCT_CREATED', 'PRODUCT_UPDATED', 'PRODUCT_IMAGE_UPLOADED', 'SKU_CREATED', 'SKU_UPDATED', 'CATEGORY_CREATED', 'CATEGORY_RENAMED', 'BRAND_CREATED', 'BRAND_RENAMED', 'INVENTORY_ADJUSTED', 'ORDER_STATUS_CHANGED', 'CONTENT_DRAFT_SAVED', 'CONTENT_PUBLISHED']) {
        if (!activity.some(event => event.action === action)) throw new Error('Missing persisted admin activity: ' + action);
      }
      if (activity.filter(event => event.action === 'ORDER_STATUS_CHANGED' && event.targetId === order.id).length !== 3) throw new Error('Order activity cardinality mismatch');
      const content = await db.storeContent.findUniqueOrThrow({ where: { key: 'storefront' } });
      if (content.version !== 3 || content.publishedVersion !== 2 || content.banner !== 'Bản nháp tiếp theo' || content.publishedBanner !== 'Campaign kiểm thử' || content.publishedPolicy !== 'Chính sách kiểm thử đã xuất bản.') throw new Error('Draft/public content isolation mismatch');
      console.log('PASS persistent admin history: authenticated actor and all thirteen action categories; draft/public content isolation and verified catalog cover.');
      console.log('PASS database assertions: product, SKU, gallery, stock, delivered COD with explicit collection receipt.');
    } else if (style) {
      const password = 'Browser-only-Password-2026';
      const send = async (method, endpoint, body, token) => {
        const response = await fetch(url + '/' + endpoint, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
        if (!response.ok) throw new Error('Style fixture request failed: ' + endpoint + ' ' + response.status);
        return response.json();
      };
      const email = fixture + '@example.com', otherEmail = 'browser-' + fixture + '@example.com';
      const buyer = await send('POST', 'auth/register', { name: 'Khách hồ sơ phong cách', email, password });
      const other = await send('POST', 'auth/register', { name: 'Khách hồ sơ mới', email: otherEmail, password });
      const address = await send('POST', 'users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, buyer.accessToken);
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-style-browser.cjs')({ root, email, otherEmail, password,
        changeStyle: async () => {
          const before = await send('GET', 'users/me/style', null, buyer.accessToken);
          await send('PUT', 'users/me/style', { size: 'XS', style: 'Thanh lịch', color: 'Đen', budget: '2500000', expectedVersion: before.version }, buyer.accessToken);
        },
      });
      const saved = await db.stylePreference.findUniqueOrThrow({ where: { userId: buyer.user.id } });
      if (saved.size !== 'XL' || saved.style !== 'Thanh lịch' || saved.color !== 'Đen' || saved.budget.toFixed(0) !== '2500000' || saved.version !== 4) throw new Error('Style profile persistence mismatch');
      if (await db.stylePreference.count({ where: { userId: other.user.id } }) !== 0) throw new Error('Reading defaults created a profile');
      if (!(await db.address.findFirst({ where: { id: address.id, userId: buyer.user.id } }))) throw new Error('Style write altered address data');
      console.log('PASS database assertions: version4 exact preferences, other account remains default, address preserved.');
    } else if (reviews) {
      const password = 'Browser-only-Password-2026';
      const post = async (path, body, token, headers = {}) => {
        const response = await fetch(url + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...headers }, body: JSON.stringify(body) });
        if (!response.ok) throw new Error('Review fixture request failed: ' + path + ' ' + response.status);
        return response.json();
      };
      const buyerEmail = fixture + '@example.com', otherEmail = 'browser-' + fixture + '@example.com';
      const buyer = await post('auth/register', { name: 'Khách đã nhận hàng', email: buyerEmail, password });
      await post('auth/register', { name: 'Khách chưa mua', email: otherEmail, password });
      const address = await post('users/me/addresses', { recipient: 'Khách kiểm thử', phone: '0901234567', address: '12 Nguyễn Huệ, TP.HCM', label: 'Nhà' }, buyer.accessToken);
      await post('cart/items', { sku: fixture, quantity: 1 }, buyer.accessToken);
      const order = await post('orders', { addressId: address.id, shippingMethod: 'standard', expectedSubtotal: '490000' }, buyer.accessToken, { 'Idempotency-Key': randomUUID() });
      // Synthetic fixture only: delivery is the eligibility precondition under test.
      await db.order.update({ where: { id: order.id }, data: { status: 'DELIVERED' } });
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-reviews-browser.cjs')({ root, fixture, buyerEmail, otherEmail, password,
        // Only this run's synthetic product can be hidden/restored by the browser scenario.
        setProductAvailable: active => db.product.update({ where: { id: product.id }, data: { active } }),
      });
      const saved = await db.review.findMany({ where: { productId: product.id } });
      if (saved.length !== 1 || saved[0].userId !== buyer.user.id || saved[0].rating !== 5 || saved[0].comment !== 'Mặc rất thoải mái.') throw new Error('Review persistence/ownership mismatch');
      console.log('PASS database assertions: one verified buyer review, exact edited content and rating.');
    } else if (wishlist) {
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-wishlist-browser.cjs')({ root, fixture });
      const saved = await db.wishlistItem.findMany({ where: { user: { email: 'browser-' + fixture + '@example.com' } } });
      if (saved.length !== 1 || saved[0].productId !== product.id) throw new Error('Wishlist was not persisted for first customer');
      if (await db.wishlistItem.count({ where: { user: { email: fixture + '@example.com' } } }) !== 0) throw new Error('Wishlist crossed customer accounts');
      console.log('PASS database assertions: first customer saved product, second customer empty.');
    } else if (browser || payments || promotions) {
      const promotion = promotions ? {code:promotionCode,adminEmail:'admin-'+fixture+'@example.com',password:'Browser-only-Password-2026'} : null;
      if(promotion) {
        const response=await fetch(url+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:promotion.adminEmail,password:promotion.password,name:'Promotion admin'})});
        if(response.status!==201)throw Error('Promotion admin fixture failed');
        const account=await response.json();await db.user.update({where:{id:account.user.id},data:{role:'ADMIN'}});
      }
      await flutter(['build', 'web', '--release', '--dart-define=USE_REMOTE_API=true', '--dart-define=API_BASE_URL=' + url]);
      await require('./verify-api-browser.cjs')({ root, url, fixture, payments, promotion, markFixturePaid:()=>{fixturePaid=true;} });
      if(promotions) {
        const order=await db.order.findFirstOrThrow({where:{user:{email:'browser-'+fixture+'@example.com'}},include:{payment:true,redemption:true}});
        if(order.total.toString()!=='470000'||order.discount.toString()!=='50000'||order.couponCode!==promotionCode||order.status!=='CANCELLED'||!order.redemption?.releasedAt)throw Error('Promotion snapshot or release mismatch');
        const coupon=await db.coupon.findUniqueOrThrow({where:{code:promotionCode}});
        if(coupon.usageLimit!==1 || await db.couponRedemption.count({where:{couponId:coupon.id,releasedAt:null}})!==0)throw Error('Coupon quota was not released');
        console.log('PASS promotion: browser admin creation, server quote, order discount snapshot and quota released on cancellation.');
      }
      if(payments) {
        const order=await db.order.findFirstOrThrow({where:{user:{email:'browser-'+fixture+'@example.com'}},include:{payment:{include:{attempts:true}}}});
        if(order.payment.provider!=='vnpay' || order.payment.status!=='PAID' || order.payment.attempts.length!==1 || order.payment.attempts[0].status!=='PAID')throw Error('VNPay fixture persistence mismatch');
        console.log('PASS persisted VNPay state from signed LOCAL FIXTURE, not a real provider response.');
      }
    } else {
      await flutter(['test', 'test/live_shopping_test.dart', '--reporter', 'expanded', '--dart-define=LIVE_SHOPPING_API_URL=' + url, '--dart-define=LIVE_SHOPPING_FIXTURE=' + fixture]);
    }
    console.log('PASS real PostgreSQL shopping; normal development database untouched.');
  } finally {
    await operationsHeartbeat?.onModuleDestroy();
    if(operationsQueue){await operationsQueue.obliterate({force:true});await operationsQueue.close();}
    for(const release of releaseTryonGates)await release();
    await tryonWorker?.onModuleDestroy();
    if(tryonQueue){await tryonQueue.obliterate({force:true});await tryonQueue.close();}
    await mailWorker?.onModuleDestroy();
    await recoveryWorker?.onModuleDestroy();
    if (recoveryQueue) { await recoveryQueue.obliterate({ force: true }); await recoveryQueue.close(); }
    // Restrict every cleanup to this run's exact account emails/product IDs.
    try {
      const users = await db.user.findMany({ where: { email: { in: [fixture + '@example.com', 'browser-' + fixture + '@example.com', 'admin-' + fixture + '@example.com'] } }, select: { id: true } });
      const owner = { userId: { in: users.map(user => user.id) } };
      if(tryon) {
        const storage=app.get(requireBackend('./dist/integrations/storage/storage.service').StorageService);
        const images=await db.imageAsset.findMany({where:owner}),results=await db.tryOnResult.findMany({where:{job:owner}});
        await storage.deleteObjects([...images.map(r=>r.objectKey),...results.map(r=>r.objectKey)]);
      }
      if (admin) {
        const { StorageService } = requireBackend('./dist/integrations/storage/storage.service');
        const assets = await db.catalogAsset.findMany({ where: { actorId: owner.userId } });
        await app.get(StorageService).deleteObjects(assets.map(asset => asset.objectKey));
        await db.catalogAsset.deleteMany({ where: { id: { in: assets.map(asset => asset.id) } } });
      }
      await db.$transaction(async tx => {
        if(tryon) {
          await tx.tryOnResult.deleteMany({where:{job:owner}});await tx.outboxEvent.deleteMany({where:{job:owner}});
          await tx.aIJob.deleteMany({where:owner});await tx.aiUsage.deleteMany({where:owner});await tx.imageAsset.deleteMany({where:owner});
        }
        if(stylist||operations)await tx.aiUsage.deleteMany({where:owner});
        if(support||staffMode)await tx.supportTicket.deleteMany({where:{email:fixture+'@example.com'}});
        const contentEvents = await tx.adminAuditEvent.findMany({
          where: { actorId: owner.userId, action: 'CONTENT_DRAFT_SAVED' }, select: { targetId: true },
        });
        await tx.storeContent.deleteMany({ where: { id: { in: contentEvents.map(event => event.targetId) } } });
        await tx.adminAuditEvent.deleteMany({ where: { actorId: owner.userId } });
        await tx.review.deleteMany({ where: owner });
        await tx.inventoryMovement.deleteMany({ where: { order: owner } });
        await tx.refund.deleteMany({ where: { payment: { order: owner } } });
        await tx.paymentAttempt.deleteMany({ where: { payment: { order: owner } } });
        await tx.couponRedemption.deleteMany({where:{order:owner}});
        if(promotions || returns || refunds) await tx.coupon.deleteMany({where:{code:promotionCode}});
        await tx.payment.deleteMany({ where: { order: owner } });
        await tx.orderItem.deleteMany({ where: { order: owner } });
        await tx.order.deleteMany({ where: owner });
        await tx.user.deleteMany({ where: { id: owner.userId } });
        const products = await tx.product.findMany({ where: { slug: { in: [fixture, fixture + '-admin'] } }, select: { id: true } });
        const productIds = { in: products.map(p => p.id) };
        await tx.inventoryMovement.deleteMany({ where: { inventory: { variant: { productId: productIds } } } });
        await tx.inventory.deleteMany({ where: { variant: { productId: productIds } } });
        await tx.productVariant.deleteMany({ where: { productId: productIds } });
        await tx.product.deleteMany({ where: { id: productIds } });
        if (category) await tx.category.delete({ where: { id: category.id } });
        if (brand) await tx.brand.delete({ where: { id: brand.id } });
        await tx.category.deleteMany({ where: { slug: fixture + '-taxonomy' } });
        await tx.brand.deleteMany({ where: { slug: fixture + '-taxonomy' } });
      });
    } finally {
      await app.close();
      await suiteLock?.end();
      if (smtp) await new Promise(resolve => smtp.close(resolve));
    }
  }
}
const deadline = setTimeout(() => { console.error('Integration verification exceeded 10 minutes.'); process.exit(1); }, 600000);
main().catch(error => { console.error(error.message); process.exitCode = 1; }).finally(() => clearTimeout(deadline));
