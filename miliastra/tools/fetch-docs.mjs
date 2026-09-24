// 用法：
//   node miliastra/tools/fetch-docs.mjs                 # 下载官方目录 + 全文（缓存到 docs/official/）
//   node miliastra/tools/fetch-docs.mjs --list          # 打印目录树（带 id）
//   node miliastra/tools/fetch-docs.mjs --grep=路径      # 按标题搜
//   node miliastra/tools/fetch-docs.mjs --dump=<id>     # 打印某一篇正文
//   node miliastra/tools/fetch-docs.mjs --save          # 219 篇全部存成 md（可离线 grep）
//
// ★ 为什么要这个工具：官方文档站是 Vue 单页应用，正文不在 HTML 里。
//   它的内容接口 api-ugc.mihoyo.com 在部分网络环境下 **DNS 解析不了**，
//   但**静态资产** act-webstatic.mihoyo.com 是通的：
//       /ugc-tutorial/knowledge/cn/zh-cn/catalog.json      目录树（219 篇）
//       /ugc-tutorial/knowledge/cn/zh-cn/textMap.json      id -> 全文
//       /ugc-tutorial/knowledge/cn/zh-cn/headingsMap.json  id -> 标题目录
//   所以这里只依赖静态资产，拿到的就是**官方原文**，不是社区整理的二手镜像。
//
// ⚠ 不要再用 GitHub 上的 Miliastra-knowledge 做唯一来源 ——
//   那份镜像只有 160 篇，官方是 219 篇（本次就是被用户指出来的）。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DIR = path.resolve(HERE, '../docs/official');
const BASE = 'https://act-webstatic.mihoyo.com/ugc-tutorial/knowledge/cn/zh-cn';

const FILES = {
  catalog: { url: BASE + '/catalog.json', file: 'catalog.json' },
  textMap: { url: BASE + '/textMap.json', file: 'textMap.json' },
  headingsMap: { url: BASE + '/headingsMap.json', file: 'headingsMap.json' }
};

function fetchTo(url, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  // 用 curl：web_fetch 不收 application/json 之外的 content-type，而这里够用，
  // 但 curl 更省事且能拿到大文件（textMap 有 1 MB）。
  execFileSync('curl', ['-s', '--max-time', '120', '-o', dest, url], { stdio: 'inherit' });
  const n = fs.statSync(dest).size;
  if (n < 100) throw new Error('下载失败（' + n + ' 字节）: ' + url);
  return n;
}

const args = process.argv.slice(2);
const flag = function (name) {
  const a = args.filter(function (x) { return x.indexOf('--' + name + '=') === 0; })[0];
  return a ? a.slice(name.length + 3) : null;
};
const has = function (name) { return args.indexOf('--' + name) >= 0; };

// 1) 确保本地有缓存
const need = [];
for (const k of Object.keys(FILES)) {
  const dest = path.join(DIR, FILES[k].file);
  if (!fs.existsSync(dest) || fs.statSync(dest).size < 100) need.push(k);
}
if (need.length) {
  console.log('[fetch-docs] 下载官方文档资产 ...');
  for (const k of need) {
    const n = fetchTo(FILES[k].url, path.join(DIR, FILES[k].file));
    console.log('  ' + FILES[k].file + '  ' + n + ' 字节  <- ' + FILES[k].url);
  }
}

const catalog = JSON.parse(fs.readFileSync(path.join(DIR, 'catalog.json'), 'utf8'));
const textMap = JSON.parse(fs.readFileSync(path.join(DIR, 'textMap.json'), 'utf8'));

// 展平目录树
function flatten(nodes, depth, out) {
  if (!out) out = [];
  for (const n of nodes) {
    const id = n.real_id || n.path_id;
    out.push({ depth: depth, title: n.title, id: id, chars: (textMap[id] || '').length });
    flatten(n.children || [], depth + 1, out);
  }
  return out;
}
const flat = flatten(catalog, 0);

if (has('list')) {
  console.log('');
  console.log('[官方目录] 共 ' + flat.length + ' 篇');
  for (const r of flat) {
    console.log('  ' + '  '.repeat(r.depth) + r.title + '   [' + r.id + ']  ' + r.chars + ' 字');
  }
  process.exit(0);
}

const g = flag('grep');
if (g) {
  const hit = flat.filter(function (r) { return r.title.indexOf(g) >= 0; });
  console.log('[grep ' + g + '] 命中 ' + hit.length + ' 篇');
  for (const r of hit) console.log('  ' + r.title + '   [' + r.id + ']  ' + r.chars + ' 字');
  process.exit(0);
}

const d = flag('dump');
if (d) {
  const body = textMap[d];
  if (!body) { console.log('没有这篇：' + d); process.exit(1); }
  const meta = flat.filter(function (r) { return r.id === d; })[0];
  console.log('=== ' + (meta ? meta.title : d) + ' [' + d + '] ' + body.length + ' 字 ===');
  console.log('');
  console.log(body);
  process.exit(0);
}

if (has('save')) {
  const outDir = path.join(DIR, 'md');
  fs.mkdirSync(outDir, { recursive: true });
  let n = 0;
  for (const r of flat) {
    const body = textMap[r.id];
    if (!body) continue;
    const head = '# ' + r.title + String.fromCharCode(10) + String.fromCharCode(10) +
      '> 官方文档 [' + r.id + ']  https://act.mihoyo.com/ys/ugc/tutorial/detail/' + r.id + String.fromCharCode(10) +
      String.fromCharCode(10);
    fs.writeFileSync(path.join(outDir, r.id + '_' + r.title.replace(/[\/:*?"<>|]/g, '_') + '.md'), head + body);
    n += 1;
  }
  console.log('[fetch-docs] 已写出 ' + n + ' 篇到 docs/official/md/（可离线 grep）');
  process.exit(0);
}

console.log('[fetch-docs] 官方文档已缓存到 miliastra/docs/official/');
console.log('  共 ' + flat.length + ' 篇，全文 ' +
  Object.keys(textMap).length + ' 条，总计 ' +
  Math.round(Object.values(textMap).reduce(function (a, b) { return a + b.length; }, 0) / 10000) + ' 万字');
console.log('');
console.log('  --list        打印目录树');
console.log('  --grep=关键词  按标题搜');
console.log('  --dump=<id>   打印某篇正文');
console.log('  --save        全部存成 md');
