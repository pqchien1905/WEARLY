// Read-only acceptance of the running catalog, pagination, filters and images.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {createHash}=require('node:crypto');
const root=path.resolve(__dirname,'..');
const sharp=require('node:module').createRequire(path.join(root,'backend/package.json'))('sharp');
const api='http://localhost:3000/api/v1/';
async function json(route){const r=await fetch(api+route,{signal:AbortSignal.timeout(8000)});assert.equal(r.status,200,route);return r.json();}
(async()=>{
  const items=[];let total;
  for(let page=1;page<=100;page++){
    const batch=await json('products?limit=12&page='+page);
    total ??= batch.total; assert.equal(batch.total,total,'Catalog changed during audit');
    items.push(...batch.items); if(items.length>=total)break;
    assert(batch.items.length>0,'Pagination ended early');
  }
  assert(items.length>0,'No products available');assert.equal(items.length,total);
  for(const field of ['id','slug','name']) assert.equal(new Set(items.map(p=>p[field])).size,total,'Duplicate '+field);
  const covers=new Set(),images=new Map();
  for(const p of items){
    assert(p.images.length>0,'Missing images: '+p.slug);
    assert(p.variants.length>0,'Missing variants: '+p.slug);
    for(const i of p.images){
      let bytes;
      if(i.url.startsWith('assets/images/')){
        const file=path.resolve(root,'frontend',i.url);
        assert(file.startsWith(path.resolve(root,'frontend/assets/images')+path.sep));
        bytes=fs.readFileSync(file);
      }else{
        assert(i.url.startsWith('catalog/images/'),'Unexpected external catalog image');
        const r=await fetch(api+i.url,{signal:AbortSignal.timeout(8000)});
        assert.equal(r.status,200,'Image unavailable: '+p.slug);assert(r.headers.get('content-type').startsWith('image/'));
        bytes=Buffer.from(await r.arrayBuffer());
      }
      const metadata=await sharp(bytes).metadata();assert(metadata.width>0&&metadata.height>0);
      const hash=createHash('sha256').update(bytes).digest('hex');images.set(i.url,hash);
      if(i===p.images[0]){assert(!covers.has(hash),'Duplicate cover: '+p.slug);covers.add(hash);}
    }
    const detail=await json('products/'+encodeURIComponent(p.slug));assert.equal(detail.id,p.id);
  }
  const facets=await json('products/facets'),categories=await json('categories');
  assert(!categories.some(c=>/fixture|test|refunds-|returns-|shipment-/i.test(c.name)),'Test taxonomy is visible');
  for(const size of facets.sizes){
    const batch=await json('products?size='+encodeURIComponent(size));
    assert(batch.total>0,'Empty size filter '+size);
    assert(batch.items.every(p=>p.variants.some(v=>v.size===size)));
  }
  const output={products:total,uniqueCovers:covers.size,verifiedImages:images.size,categories:categories.map(c=>c.name),sizes:facets.sizes,styles:facets.styles};
  fs.mkdirSync(path.join(root,'.tools/catalog-curation'),{recursive:true});
  fs.writeFileSync(path.join(root,'.tools/catalog-curation/verification.json'),JSON.stringify(output,null,2));
  console.log(JSON.stringify(output));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
