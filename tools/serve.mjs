// 极简静态服务器。用法：node tools/serve.mjs [端口]（默认 8080）
//
// 为什么不用 python3 -m http.server：
//   SimpleHTTPRequestHandler **不发 Cache-Control**，浏览器会按启发式缓存 zuma.html，
//   于是"代码改了、也重新 build 了，但手机上还是旧页面" —— 这个坑踩过一次，不再踩。
//   这里显式发 no-store，每次刷新都拿最新的。
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const PORT = parseInt(process.argv[2] || '8080', 10);
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

http.createServer(function (req, res) {
  let p = decodeURIComponent((req.url || '/').split('?')[0]);
  if (p === '/') p = '/index.html';
  const fp = path.normalize(path.join(ROOT, p));
  if (fp.indexOf(ROOT) !== 0) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(fp, function (err, data) {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('not found: ' + p); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(fp).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
      'Pragma': 'no-cache',
      'Expires': '0'
    });
    res.end(data);
  });
}).listen(PORT, '0.0.0.0', function () {
  console.log('serve: http://127.0.0.1:' + PORT + '/   （Cache-Control: no-store）');
  console.log('      http://127.0.0.1:' + PORT + '/zuma.html');
});

