// 把 lua/src/*.lua 打包成**单文件** out/zuma.lua。
//
// 为什么要打包：千星奇域里"脚本映射"要一个个建，require 的 package.path 也不受我们控制。
// 单文件上传最稳，且不依赖任何 require 搜索路径。
//
// 做法：每个模块包成 __M["名"] = function() ... end，顶部放一个局部 require 覆盖。
// ★ 关键点 1：局部 require 必须在所有模块体**之前**声明 —— Lua 的词法作用域
//   会让模块体里的 require 绑到这个局部变量上。
// ★ 关键点 2：运行时是**按固定名字查找生命周期回调**的（官方："运行时按固定名称查找并调用"），
//   所以最后要把 game 模块的 OnInit/OnStart/OnUpdate/... 暴露成全局。

import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './lib/lua-runner.mjs';

const SRC = path.join(ROOT, 'lua', 'src');
const OUT = path.join(ROOT, 'out', 'zuma.lua');

// 依赖层次顺序（require 是懒解析的，顺序不影响正确性，只影响可读性）
const ORDER = ['rng', 'config', 'elements', 'geometry', 'spines', 'chain', 'run',
  'projectile', 'ribosome', 'board', 'levels_data', 'ui', 'input', 'game'];

const LIFECYCLE = ['OnInit', 'OnStart', 'OnEnable', 'OnDisable', 'OnUpdate', 'OnLevelUpdate', 'OnDestroy'];

const files = fs.readdirSync(SRC).filter((f) => f.endsWith('.lua')).map((f) => f.replace(/\.lua$/, ''));
const names = ORDER.filter((n) => files.includes(n)).concat(files.filter((n) => !ORDER.includes(n)).sort());

const parts = [];
parts.push('-- ============================================================');
parts.push('-- zuma.lua —— 由 miliastra/tools/bundle-lua.mjs 自动生成，**不要手改**。');
parts.push('-- 源文件：miliastra/lua/src/*.lua（那边才是真源）');
parts.push('--');
parts.push('-- 用法：整个文件作为**一个客户端脚本**上传 -> 在客户端控件容器的');
parts.push('--       脚本页签里挂上它 -> 把控件模板索引填进脚本变量（见 lua/src/game.lua 顶部）。');
parts.push('-- ============================================================');
parts.push('');
parts.push('local __M = {}');
parts.push('local __cache = {}');
parts.push('local function __require(name)');
parts.push('  local hit = __cache[name]');
parts.push('  if hit ~= nil then return hit end');
parts.push('  local f = __M[name]');
parts.push('  if not f then error("module not found: " .. tostring(name)) end');
parts.push('  local v = f()');
parts.push('  if v == nil then v = true end');
parts.push('  __cache[name] = v');
parts.push('  return v');
parts.push('end');
parts.push('local require = __require   -- ★ 必须在模块体之前，模块体里的 require 才绑得到它');
parts.push('');

for (const name of names) {
  const body = fs.readFileSync(path.join(SRC, name + '.lua'), 'utf8');
  parts.push('-- ---------------- ' + name + ' ----------------');
  parts.push('__M[' + JSON.stringify(name) + '] = function()');
  parts.push(body.replace(/\s+$/, ''));
  parts.push('end');
  parts.push('');
}

parts.push('-- ---------------- 对外门面 ----------------');
parts.push('-- 字段名与 lua/src 的文件名一致。');
parts.push('ZUMA = {');
for (const name of names) parts.push('  ' + name + ' = __require(' + JSON.stringify(name) + '),');
parts.push('}');
parts.push('');
parts.push('-- ★ 把生命周期回调暴露成**全局**：运行时是按固定名字查找的。');
parts.push('--   这些函数内部引用的是模块级的 G，不依赖 self，所以裸调用完全等价。');
parts.push('local __LIFECYCLE_NAMES = {');
parts.push('  ' + LIFECYCLE.map((n) => JSON.stringify(n)).join(', '));
parts.push('}');
parts.push('for i = 1, #__LIFECYCLE_NAMES do');
parts.push('  local __n = __LIFECYCLE_NAMES[i]');
parts.push('  local __f = ZUMA.game[__n]');
parts.push('  if type(__f) == "function" then _G[__n] = __f end');
parts.push('end');
parts.push('');
parts.push('return ZUMA');
parts.push('');

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, parts.join('\n'));
const bytes = fs.statSync(OUT).size;
console.log('打包：' + names.length + ' 个模块 -> ' + path.relative(ROOT, OUT) + '（' + bytes + ' 字节）');
console.log('  ' + names.join(', '));
console.log('  暴露生命周期：' + LIFECYCLE.join(', '));
