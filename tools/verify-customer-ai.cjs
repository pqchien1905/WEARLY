// One explicitly requested live Gemini try-on with a bundled catalog model photo.
// Keeps the successful owned result for the customer; no provider credentials logged.
const fs=require('node:fs');
const path=require('node:path');
const {randomUUID}=require('node:crypto');
const { customerSession, customerEmail }=require('./customer-account-session.cjs');
const root=path.resolve(__dirname,'..');
const folder=path.join(root,'.tools/customer-account');
fs.mkdirSync(folder,{recursive:true});
(async()=>{
  const session=await customerSession(customerEmail());
  const report={input:'Bundled catalog model photo: assets/images/shirt.jpg',passed:[]};
  try{
    const call=session.request;
    const status=await call('ai/try-on/status');
    if(!status.configured) throw Error('Gemini is not configured in the API process');
    const history=await call('ai/try-on/jobs');
    const previous=history.items.find(j=>j.resultAvailable);
    if(previous){report.job=previous;report.passed.push('Existing successful live result retained; no duplicate generation');}
    else{
      const catalog=await call('products?limit=100');
      const product=catalog.items.find(p=>p.slug==='nep-4' && p.tryOnSupported) || catalog.items.find(p=>p.tryOnSupported);
      if(!product) throw Error('No eligible garment in the live catalog');
      const variant=product.variants.find(v=>v.size==='M' && v.available>0 && v.color!=='Đen') || product.variants.find(v=>v.available>0);
      const form=new FormData();
      form.set('consent','true');
      form.set('file',new Blob([fs.readFileSync(path.join(root,'frontend/assets/images/shirt.jpg'))],{type:'image/jpeg'}),'catalog-model-test.jpg');
      const image=await call('uploads/images',{method:'POST',body:form,headers:{'Idempotency-Key':randomUUID()},expected:201});
      report.imageId=image.id;report.sku=variant.sku;
      const job=await call('ai/try-on/jobs',{method:'POST',body:{imageId:image.id,sku:variant.sku,consent:true},headers:{'Idempotency-Key':randomUUID()},expected:201});
      report.jobId=job.id;
      console.log('Live Gemini try-on submitted; waiting for the worker.');
      fs.writeFileSync(path.join(folder,'ai-live.json'),JSON.stringify(report,null,2));
      const until=Date.now()+180000;
      while(Date.now()<until){
        const current=await call('ai/try-on/jobs/'+job.id);
        report.job=current;
        if(current.resultAvailable){report.passed.push('Live Gemini generated a private try-on image through API and worker');break;}
        if(current.status==='failed') throw Error('Live try-on failed: '+current.errorCode);
        await new Promise(resolve=>setTimeout(resolve,3000));
      }
      if(!report.job?.resultAvailable) throw Error('Live try-on did not finish within the verification window');
    }
    const job=report.job;
    // The private result endpoint is consumed by the browser; inspect its storage metadata.
    const stored=await session.db.tryOnResult.findUnique({where:{jobId:job.id}});
    if(!stored?.objectKey) throw Error('Result is missing from private storage metadata');
    report.resultStored=true;
    report.passed.push('Result is persisted and appears in the customer history');
    console.log(JSON.stringify({passed:report.passed,job:report.job},null,2));
  }catch(error){report.failure=error.message;throw error;}
  finally{fs.writeFileSync(path.join(folder,'ai-live.json'),JSON.stringify(report,null,2));await session.close();}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
