const path = require('node:path');
const fs = require('node:fs');
const { Client } = require('../backend/node_modules/pg');
require('../backend/node_modules/dotenv').config({ path:path.resolve(__dirname,'../backend/.env'),quiet:true });
async function main() {
  const original = new URL(process.env.DATABASE_URL);
  const file=path.resolve(__dirname,'../backend/.env.test');
  const saved=fs.existsSync(file) ? require('../backend/node_modules/dotenv').parse(fs.readFileSync(file)) : undefined;
  const configured=process.env.TEST_DATABASE_URL || saved?.TEST_DATABASE_URL;
  const target = configured ? new URL(configured) : new URL(original);
  if(!configured) target.pathname = original.pathname + '_test';
  const name = target.pathname.slice(1);
  if(!/^[a-zA-Z0-9_]+_test$/.test(name) || target.toString() === original.toString()) throw new Error('A separate database ending in _test is required.');
  if(saved && saved.TEST_DATABASE_URL!==target.toString())throw new Error('.env.test already points elsewhere; inspect it before changing databases.');
  const admin = new URL(target);admin.pathname='/postgres';
  const db = new Client({connectionString:admin.toString()});await db.connect();
  try {
    const exists = await db.query('SELECT 1 FROM pg_database WHERE datname=$1',[name]);
    if(!exists.rowCount) await db.query('CREATE DATABASE "'+name+'" WITH ENCODING \'UTF8\' TEMPLATE template0');
  } finally { await db.end(); }
  if(!saved) fs.writeFileSync(file,'TEST_DATABASE_URL='+target.toString()+'\n',{flag:'wx'});
  console.log('Dedicated test database is ready. No database was dropped or reset.');
}
main().catch((error)=>{console.error(error.code ?? error.message);process.exitCode=1;});
