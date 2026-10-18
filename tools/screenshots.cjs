const { chromium } = require('../.tools/browser/node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async()=>{
  const browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-sandbox']});
  const out=path.resolve(__dirname,'../docs/qa/screenshots'); fs.mkdirSync(out,{recursive:true});
  const errors=[];
  const selected=process.argv[2]?.split(',');
  const widths=process.argv[3]?.split(',').map(Number) || [375,768,1024,1440];
  const prefix=process.argv[4] || '';
  for(const width of widths) {
    const page=await browser.newPage({viewport:{width,height:1000},deviceScaleFactor:1});
    page.on('pageerror',e=>errors.push({width,error:e.message}));
    for(const [name,route] of [['home','/'],['catalog','/shop'],['product','/products/nep-1'],['login','/login'],['stylist','/ai-stylist'],['tryon','/virtual-try-on'],['admin','/admin'],['admin-products','/admin/products'],['admin-inventory','/admin/inventory'],['contact','/contact'],['faq','/faq'],['collections','/collections'],['collection-detail','/collections/everyday']]) {
      if(selected && !selected.includes(name)) continue;
      await page.goto('http://127.0.0.1:4173/#'+route);
      await page.waitForTimeout(2200);
      await page.screenshot({path:path.join(out,`${prefix}${name}-${width}.png`)});
      console.log(`${name} ${width} captured`);
    }
    await page.close();
  }
  fs.writeFileSync(path.join(out,`${prefix}browser-errors.json`),JSON.stringify(errors,null,2));
  await browser.close();
})().catch(e=>{console.error(e);process.exitCode=1});
