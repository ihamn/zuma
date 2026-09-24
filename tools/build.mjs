// 极简打包器：把 src/ 的 ES 模块内联成单文件 zuma.html。
// 动机：Android 浏览器用 file:// 打开时会拦 module import，所以交付物必须是单文件。
// 约束：源码里只能写单行 import、不能用 export default / export {}。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(HERE, '..');

const IMPORT_LINE = /^[ \t]*import[^\n;]*;[ \t]*$/gm;
const EXPORT_KW = /^[ \t]*export[ \t]+(?=(const|let|var|function|class|async))/gm;
const FROM_RE = /from[ \t]+'([^']+)'/g;

function depsOf(code) {
  const out = [];
  let m;
  FROM_RE.lastIndex = 0;
  while ((m = FROM_RE.exec(code)) !== null) out.push(m[1]);
  return out;
}

function stripModule(code) {
  return code.replace(IMPORT_LINE, '').replace(EXPORT_KW, '');
}

export function bundle(entryRel) {
  const seen = new Set();
  const chunks = [];
  const files = [];

  function visit(rel) {
    const abs = path.resolve(ROOT, rel);
    if (seen.has(abs)) return;
    seen.add(abs);
    const code = fs.readFileSync(abs, 'utf8');
    const deps = depsOf(code);
    for (let i = 0; i < deps.length; i++) {
      const d = deps[i];
      if (d.charAt(0) !== '.') throw new Error('bundle: 不支持非相对导入 ' + d + '（' + rel + '）');
      visit(path.relative(ROOT, path.resolve(path.dirname(abs), d)));
    }
    files.push(path.relative(ROOT, abs));
    chunks.push('// ===== ' + path.relative(ROOT, abs) + ' =====\n' + stripModule(code));
  }

  visit(entryRel);
  const js = chunks.join('\n');

  const leftoverImport = js.match(/^[ \t]*import[^\n]*$/m);
  if (leftoverImport) throw new Error('bundle: 仍有未处理的 import -> ' + leftoverImport[0]);
  const leftoverExport = js.match(/^[ \t]*export[^\n]*$/m);
  if (leftoverExport) throw new Error('bundle: 仍有未处理的 export -> ' + leftoverExport[0]);
  return { js: js, files: files };
}

const ENTRY_TAG = '<script type="module" src="./src/main.js"></script>';

export function buildHtml() {
  const b = bundle('src/main.js');
  const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
  if (html.indexOf(ENTRY_TAG) < 0) throw new Error('index.html 缺少入口标签 ' + ENTRY_TAG);
  // 用函数式替换，避免 $& / $1 被当作替换模式解释
  const out = html.replace(ENTRY_TAG, function () { return '<script>\n' + b.js + '\n</script>'; });
  return { html: out, files: b.files };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const t0 = Date.now();
  const out = buildHtml();
  fs.writeFileSync(path.join(ROOT, 'zuma.html'), out.html);
  console.log('[build] 内联 ' + out.files.length + ' 个模块 -> zuma.html（' + out.html.length + ' 字节, ' + (Date.now() - t0) + 'ms）');
  for (let i = 0; i < out.files.length; i++) console.log('        + ' + out.files[i]);
}

