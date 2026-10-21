const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const { spawn } = require('node:child_process');
function buildOptions(binary, folder, inherited) {
  return { binary, args: [
    '--listen','127.0.0.1:8025','--smtp','127.0.0.1:1025',
    '--database',path.join(folder,'mailpit.db'),'--max','500','--max-age','1d',
    '--allowed-hosts','localhost,127.0.0.1','--disable-version-check',
    '--ignore-duplicate-ids','--smtp-disable-rdns','--block-remote-css-and-fonts',
    '--max-message-size','1','--quiet','--log-file',path.join(folder,'mailpit.log'),
  ], options: { cwd:folder, windowsHide:true, detached:true, stdio:'ignore',
    env:Object.fromEntries(Object.entries(inherited).filter(([key])=>!/^MP_/i.test(key))),
  }};
}
async function healthy() {
  try { const r=await fetch('http://127.0.0.1:8025/livez',{signal:AbortSignal.timeout(1000)});return r.ok; } catch {return false;}
}
async function freePort(port) {
  await new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',()=>reject(Error('Local inbox port '+port+' is already occupied')));s.listen(port,'127.0.0.1',()=>s.close(resolve));});
}
async function main(action) {
  const folder=fs.realpathSync(path.resolve(__dirname,'../.tools/mailpit')),
    binary=fs.realpathSync(path.join(folder,'mailpit.exe')), stateFile=path.join(folder,'process.json');
  let state;try{state=JSON.parse(fs.readFileSync(stateFile));}catch{}
  let running=false;try{if(state?.pid&&state.binary===binary){process.kill(state.pid,0);running=true;}}catch{}
  if(action==='status') {if(!running||!await healthy())throw Error('Local inbox is not running');console.log('Mailpit local inbox: http://127.0.0.1:8025; SMTP127.0.0.1:1025');return;}
  if(action!=='start')throw Error('Expected start or status');
  if(running&&await healthy()){console.log('Mailpit already running: http://127.0.0.1:8025');return;}
  await freePort(8025);await freePort(1025);
  const config=buildOptions(binary,folder,process.env),child=spawn(binary,config.args,config.options);
  await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);});
  fs.writeFileSync(stateFile,JSON.stringify({pid:child.pid,binary,startedAt:new Date().toISOString()},null,2));child.unref();
  for(let i=0;i<30;i++){if(await healthy()){console.log('Mailpit started: http://127.0.0.1:8025; local capture only');return;}await new Promise(r=>setTimeout(r,100));}
  child.kill();throw Error('Local inbox startup failed; inspect private Mailpit log');
}
module.exports={buildOptions};
if(require.main===module)main(process.argv[2]).catch(e=>{console.error(e.message);process.exitCode=1;});
