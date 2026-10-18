const fs=require('fs');
const colors={ink:'#252329',muted:'#67636A',accent:'#65394D',success:'#286047',danger:'#AD303B',warning:'#805A16',surface:'#FFFFFF',canvas:'#F7F8F7',soft:'#ECE5E9',controlLine:'#8E8A91'};
const luminance=hex=>{const c=hex.slice(1).match(/../g).map(h=>parseInt(h,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return c[0]*.2126+c[1]*.7152+c[2]*.0722};
const pairs=[['ink','surface'],['muted','surface'],['muted','canvas'],['accent','surface'],['accent','soft'],['surface','accent'],['surface','ink'],['success','surface'],['danger','surface'],['warning','surface']];
pairs.push(['controlLine','surface']);
const results=pairs.map(([foreground,background])=>{const a=luminance(colors[foreground]),b=luminance(colors[background]);const ratio=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);const requiredRatio=foreground==='controlLine'?3:4.5;return {foreground,background,ratio:Number(ratio.toFixed(2)),requiredRatio,pass:ratio>=requiredRatio};});
fs.writeFileSync('docs/qa/contrast.json',JSON.stringify(results,null,2));
console.log(results);if(results.some(r=>!r.pass))process.exitCode=1;
