// Review with no args. --apply archives duplicate/incomplete entries in place;
// it never deletes inventory, orders, images, or product identifiers.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const root = path.resolve(__dirname, '..');
const requireBackend = require('node:module').createRequire(path.join(root, 'backend/package.json'));
const { PrismaService } = requireBackend('./dist/database/prisma.service');
const { ConfigService } = requireBackend('@nestjs/config');
const normal = requireBackend('dotenv').parse(fs.readFileSync(path.join(root, 'backend/.env')));
const target = new URL(normal.DATABASE_URL);
if (!['localhost','127.0.0.1'].includes(target.hostname) || target.pathname !== '/wearly') throw Error('This reviewed curation is only for the local wearly catalog.');
const config = new ConfigService(normal); config.skipProcessEnv = true;
const db = new PrismaService(config);
const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
async function plan(tx) {
  const rows = await tx.product.findMany({ include: { images: { orderBy: { position: 'asc' } } }, orderBy: [{ createdAt:'asc' },{id:'asc'}] });
  const keepSeed = new Set(['nep-1','nep-2','nep-4','nep-6','nep-7','nep-8']);
  // The old seed cycles seven photos through 32 names. Its jogger is also in
  // the later imported catalog, where the photograph and color are correct.
  const importedJogger = rows.some(p=>p.active && p.slug==='wearly-demo-quan-jogger-hong-dat' && p.images.length);
  if (!importedJogger) keepSeed.add('nep-3');
  const seen = new Set();
  return rows.filter(p=>p.active).map(p=>{
    let reason;
    if (!p.images.some(i=>i.url.trim())) reason='missing_image';
    else if (/^nep-(?:[1-9]|[12]\d|3[0-2])$/.test(p.slug) && !keepSeed.has(p.slug)) reason='repeated_seed_design';
    else if (seen.has(p.images[0].url)) reason='repeated_cover';
    else seen.add(p.images[0].url);
    return { id:p.id, slug:p.slug, name:p.name, updatedAt:p.updatedAt, reason:reason||null };
  });
}
(async()=>{
  try {
    const preview=await plan(db), changes=preview.filter(p=>p.reason);
    const out=path.join(root,'.tools/catalog-curation'); fs.mkdirSync(out,{recursive:true});
    if (!process.argv.includes('--apply')) {
      fs.writeFileSync(path.join(out,'plan.json'),JSON.stringify(preview,null,2));
      console.log(JSON.stringify({active:preview.length,retain:preview.length-changes.length,archive:changes.length,reasons:changes.reduce((a,p)=>(a[p.reason]=(a[p.reason]||0)+1,a),{})}));
      return;
    }
    if (!changes.length) {console.log('Catalog is already curated.');return;}
    const before = await db.product.findMany({orderBy:{id:'asc'}});
    const backup=path.join(out,'products-before-'+Date.now()+'.private.json');
    fs.writeFileSync(backup,JSON.stringify(before,null,2),{flag:'wx',mode:0o600});
    const protectedTables=['Order','OrderItem','Payment','PaymentAttempt','Refund','Inventory','InventoryMovement','ProductVariant','ProductImage','User','Address','Cart','CartItem'];
    const fingerprints=async tx=>{
      const result={};
      for (const table of protectedTables) result[table]=await tx.$queryRawUnsafe(`SELECT count(*)::int AS count,md5(COALESCE(string_agg(row_to_json(t)::text,E'\\n' ORDER BY row_to_json(t)::text),'')) AS digest FROM "${table}" t`);
      return result;
    };
    await db.$transaction(async tx=>{
      await tx.$queryRawUnsafe('SELECT id FROM "Product" ORDER BY id FOR UPDATE');
      if(digest(await plan(tx))!==digest(preview)) throw Error('Catalog changed after review; rerun the preview.');
      const prior=await fingerprints(tx);
      const actor=await tx.user.findFirstOrThrow({where:{username:'admin',role:'ADMIN',active:true},select:{id:true}});
      for(const p of changes){
        await tx.product.update({where:{id:p.id,updatedAt:p.updatedAt},data:{active:false}});
        await tx.adminAuditEvent.create({data:{actorId:actor.id,action:'PRODUCT_UPDATED',targetId:p.id,details:{before:{active:true},after:{active:false},reason:p.reason,operation:'catalog-curation'}}});
      }
      if(digest(prior)!==digest(await fingerprints(tx)))throw Error('Protected business data changed during curation.');
    },{isolationLevel:'Serializable',timeout:30000});
    console.log(JSON.stringify({archived:changes.length,retained:preview.length-changes.length,protectedTables:protectedTables.length,backup:path.relative(root,backup)}));
  } finally {await db.$disconnect();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
