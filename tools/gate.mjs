// 极简口令网关：在公网隧道和你本机服务之间加一道密码。
//
//   node tools/gate.mjs --target 3080 --port 3090 --password ihamn
//
//   --target  本机被保护的服务端口（3080 = DSH 控制台，8080 = 游戏页）
//   --port    网关自己监听的端口（默认 3090），隧道指到这里
//
// 支持：流式响应（SSE）、WebSocket 升级（DSH 控制台需要）、任意 HTTP 方法。
// 口令正确后发一个随机 Cookie；口令本身不会出现在 Cookie 里。
// 注意：这是"挡路障"，不是强认证 —— 口令弱就是弱，配合 HTTPS 隧道用。

import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';

const argv = process.argv.slice(2);
function arg(name, def) {
  const i = argv.indexOf('--' + name);
  return (i >= 0 && argv[i + 1]) ? argv[i + 1] : def;
}

const TARGET_PORT = parseInt(arg('target', '3080'), 10);
const LISTEN_PORT = parseInt(arg('port', '3090'), 10);
const PASSWORD = arg('password', 'ihamn');
const TOKEN = crypto.randomBytes(18).toString('hex');

const LOGIN_HTML = [
  '<!doctype html><meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width,initial-scale=1">',
  '<title>需要口令</title>',
  '<style>',
  'body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;',
  'background:#0b1220;color:#dbe7f5;font:16px system-ui,sans-serif}',
  'form{background:#121c2e;padding:28px 26px;border-radius:14px;border:1px solid #22304a;text-align:center}',
  'h1{font-size:17px;margin:0 0 18px;font-weight:600;color:#9dc0ea}',
  'input{font:inherit;padding:10px 14px;border-radius:9px;border:1px solid #2b3d5c;',
  'background:#0b1220;color:#eaf2ff;width:190px;text-align:center;letter-spacing:.12em}',
  'button{font:inherit;margin-left:8px;padding:10px 16px;border-radius:9px;border:0;',
  'background:#2b6cb0;color:#fff;cursor:pointer}',
  'button:hover{background:#3b82d6}',
  '.err{margin:0 0 14px;color:#ff8a8f;font-size:14px}',
  '</style>',
  '<form method="POST" action="/__gate">',
  '<h1>祖玛 · RNA</h1>',
  '<!--ERR-->',
  '<input name="password" type="password" autofocus autocomplete="current-password" placeholder="口令">',
  '<button type="submit">进入</button>',
  '</form>'
].join('');

function parseCookies(header) {
  const out = {};
  if (!header) return out;
  const parts = header.split(';');
  for (let i = 0; i < parts.length; i++) {
    const eq = parts[i].indexOf('=');
    if (eq < 0) continue;
    out[parts[i].slice(0, eq).trim()] = parts[i].slice(eq + 1).trim();
  }
  return out;
}

function authed(req) {
  return parseCookies(req.headers.cookie || '').gate === TOKEN;
}

const server = http.createServer(function (req, res) {
  const host = req.headers.host || '';

  // 登录提交
  if (req.method === 'POST' && req.url.indexOf('/__gate') === 0) {
    let body = '';
    req.on('data', function (c) { body += c; if (body.length > 4096) req.destroy(); });
    req.on('end', function () {
      const given = new URLSearchParams(body).get('password') || '';
      if (given === PASSWORD) {
        res.writeHead(302, {
          'Set-Cookie': 'gate=' + TOKEN + '; Path=/; HttpOnly; SameSite=Lax',
          'Location': '/'
        });
        res.end();
      } else {
        res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(LOGIN_HTML.replace('<!--ERR-->', '<p class="err">口令不对</p>'));
      }
    });
    return;
  }

  if (!authed(req)) {
    res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(LOGIN_HTML);
    return;
  }

  // 反代到本机目标服务
  const headers = Object.assign({}, req.headers);
  headers.host = '127.0.0.1:' + TARGET_PORT;
  const up = http.request({
    host: '127.0.0.1', port: TARGET_PORT, method: req.method, path: req.url, headers: headers
  }, function (pres) {
    res.writeHead(pres.statusCode, pres.headers);
    pres.pipe(res);                       // 流式转发（SSE 也走这条）
  });
  up.on('error', function () {
    try { res.writeHead(502, { 'Content-Type': 'text/plain' }); res.end('upstream error'); } catch (e) {}
  });
  req.pipe(up);
});

// WebSocket / 其它 Upgrade 请求：先验 Cookie，再裸管道转发
server.on('upgrade', function (req, socket, head) {
  if (!authed(req)) { socket.destroy(); return; }
  const up = net.connect(TARGET_PORT, '127.0.0.1', function () {
    let raw = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
    for (const k in req.headers) raw += k + ': ' + req.headers[k] + '\r\n';
    raw += '\r\n';
    up.write(raw);
    if (head && head.length) up.write(head);
    up.pipe(socket);
    socket.pipe(up);
  });
  up.on('error', function () { socket.destroy(); });
  socket.on('error', function () { up.destroy(); });
});

server.listen(LISTEN_PORT, '0.0.0.0', function () {
  console.log('[gate] 监听 0.0.0.0:' + LISTEN_PORT + '  ->  127.0.0.1:' + TARGET_PORT);
  console.log('[gate] 口令已设置（' + PASSWORD.length + ' 位）。隧道请指向本端口。');
});

