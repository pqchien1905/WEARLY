// Creates collection metadata from the approved local catalog. No products,
// images, prices or stock are inserted. Existing collection edits are preserved.
const fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
const root=path.resolve(__dirname,'..');
const fromBackend=require('node:module').createRequire(path.join(root,'backend/package.json'));
const env=fromBackend('dotenv').parse(fs.readFileSync(path.join(root,'backend/.env')));
const target=new URL(env.DATABASE_URL);
if(!['localhost','127.0.0.1'].includes(target.hostname)||target.pathname!='/wearly')throw Error('This catalog setup is restricted to the reviewed local database');
const choices=[
  ['everyday','Everyday, theo cách bạn.','Những lựa chọn tối giản để kết hợp mỗi ngày. Bắt đầu từ một thiết kế hợp với bạn.','Tối giản','ao'],
  ['weekend','Một cuối tuần thảnh thơi.','Khám phá những thiết kế theo phong cách thư giãn, dành cho nhịp sống thường ngày của bạn.','Thư giãn','quan'],
  ['occasion','Dành cho một dịp riêng.','Những thiết kế thanh lịch đang có tại cửa hàng, từ trang phục đến giày và túi xách.','Thanh lịch','dam'],
  ['statement','Một dấu ấn của riêng bạn.','Thêm nét cá tính vào tủ đồ với những thiết kế nổi bật trong danh mục hiện có.','Cá tính','khoac'],
];
const db=new (fromBackend('pg').Client)({connectionString:env.DATABASE_URL});
(async()=>{await db.connect();try{
  await db.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
  const existing=(await db.query('SELECT * FROM "StoreCollection" ORDER BY position,id')).rows;
  const products=(await db.query(`SELECT p.id,p.name,p.style,c.slug AS category FROM "Product" p JOIN "Category" c ON c.id=p."categoryId"
    WHERE p.active AND EXISTS(SELECT 1 FROM "ProductVariant" v WHERE v."productId"=p.id AND v.active)
    AND EXISTS(SELECT 1 FROM "ProductImage" i WHERE i."productId"=p.id AND i.url<>'') ORDER BY p."createdAt" DESC,p.id`)).rows;
  const plan=choices.flatMap(([slug,title,description,style,category],position)=>{
    const members=products.filter(p=>p.style===style);
    if(!members.length||existing.some(c=>c.style===style||c.slug===slug))return [];
    return [{slug,title,description,style,position,cover:members.find(p=>p.category===category)||members[0],count:members.length}];
  });
  if(process.argv.includes('--apply')&&plan.length){
    const directory=path.join(root,'.tools/collections');fs.mkdirSync(directory,{recursive:true});
    fs.writeFileSync(path.join(directory,'metadata-before-'+Date.now()+'.json'),JSON.stringify(existing,null,2),{flag:'wx'});
    const actor=(await db.query(`SELECT id FROM "User" WHERE username='admin' AND role='ADMIN' AND active`)).rows[0];
    if(!actor)throw Error('Catalog administrator missing');
    for(const row of plan){
      const id=randomUUID();
      await db.query(`INSERT INTO "StoreCollection" (id,slug,title,description,style,position,"coverProductId","updatedAt") VALUES($1,$2,$3,$4,$5,$6,$7,now())`,[id,row.slug,row.title,row.description,row.style,row.position,row.cover.id]);
      await db.query(`INSERT INTO "AdminAuditEvent" (id,"actorId",action,"targetId",details) VALUES($1,$2,'COLLECTION_CREATED',$3,$4)`,[randomUUID(),actor.id,id,JSON.stringify({after:{slug:row.slug,style:row.style,active:true,position:row.position,version:1,coverProductId:row.cover.id}})]);
    }
  }
  await db.query(process.argv.includes('--apply')?'COMMIT':'ROLLBACK');
  console.log(JSON.stringify({mode:process.argv.includes('--apply')?'applied':'preview',collections:plan.map(c=>({slug:c.slug,style:c.style,products:c.count,cover:c.cover.name})),preserved:existing.length}));
}catch(e){await db.query('ROLLBACK');throw e;}finally{await db.end();}})().catch(e=>{console.error(e.message);process.exitCode=1;});
