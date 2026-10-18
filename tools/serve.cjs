const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../apps/storefront/build/web');
const mime = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.jpg':'image/jpeg','.png':'image/png','.ttf':'font/ttf','.svg':'image/svg+xml'};
http.createServer((req,res) => {
  const clean = decodeURIComponent(req.url.split('?')[0]);
  const file = path.resolve(root, '.' + (clean === '/' ? '/index.html' : clean));
  if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file,(error,data) => { if(error) {res.writeHead(404);res.end('Not found');return;} res.writeHead(200,{'Content-Type':mime[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'});res.end(data); });
}).listen(4173,'127.0.0.1',()=>console.log('Wearly preview: http://127.0.0.1:4173'));
