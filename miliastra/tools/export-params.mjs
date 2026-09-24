// 用法：node miliastra/tools/export-params.mjs
//
// 产出 miliastra/out/params.json + params.md：
//   **移植时要在千星奇域编辑器里填的每一个数值**，以及它在 DESIGN.md 里的出处。
//
// 为什么要有这个：本作的数值散在 config.js / levels.js / 各章说明里，
// 手抄到编辑器里一定会漏、会抄错，而且过一阵就不知道"这个 42 是哪来的"。
// 这里按**系统**分组导出，每组附上出处章节 —— 抄错了能查，改了能追溯。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DESIGN, BASES, COMPLEMENT } from '../../src/config.js';
import { ALL_LEVELS, TUTORIALS } from '../../src/levels.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(HERE, '../out');
fs.mkdirSync(OUT, { recursive: true });

// 按系统分组。每个条目：[常量名, 中文名, 单位, 出处(§)]
const GROUPS = [
  { name: '轨道与几何', ref: '§2 / §5 / §62 / §63', items: [
    ['base', '设计基准边长', '设计单位', '§2.3'],
    ['turns', '螺旋圈数（默认）', '圈', '§5.1 / §62'],
    ['innerRatio', '螺旋内收比（末端半径 / 起端半径）', '比值', '§5.1'],
    ['pathSamples', '骨架采样点数', '点', '§2'],
    ['outerFit', '骨架占视口的比例', '比值', '§2'],
    ['outerFitWide', '横向拉伸上限', '比值', '§2'],
    ['outerFitTall', '竖屏纵向拉伸上限', '比值', '§2'],
    ['railClearance', '两轨之间的净空', '设计单位', '§24'],
    ['minScale', '最小缩放（手机可读性下限）', '比值', '§24']
  ]},
  { name: '球与珠距', ref: '§2 / §4', items: [
    ['spawnRadius', '出球道大球半径 R', '设计单位', '§2.4 / §A12'],
    ['smallDiameterRatio', '小球直径 / 大球直径 = 1/√2', '比值', '§A12'],
    ['beadGap', '同轨相邻球净空（球距 p = 2R + 它）', '设计单位', '§4.3']
  ]},
  { name: '珠串推进（绳模型）', ref: '§4.3', items: [
    ['chainSpeed', '珠串目标速度（= 冒球率 × 球距）', '设计单位/秒', '§4.3 / §54'],
    ['chainAccel', '加速（慢）', '设计单位/秒²', '§4.3'],
    ['chainDecel', '减速（快，约 20:1）', '设计单位/秒²', '§4.3'],
    ['slowDistance', '洞穴前减速带长度（0 = 关）', '设计单位', '§12-B7 冻结'],
    ['slowFactor', '减速带末端速度分母', '比值', '§12-B7 冻结']
  ]},
  { name: '发射与配对', ref: '§4.4 / §U6-U8', items: [
    ['ribosomeRadius', '核糖体半径', '设计单位', '§U6'],
    ['fireCooldown', '两发最小间隔', '秒', '§U7'],
    ['shotSpeed', '弹丸速度', '设计单位/秒', '§U7'],
    ['shotRadiusRatio', '弹丸半径 = 小球半径 × 它', '比值', '§U7'],
    ['shotMaxLife', '弹丸存活上限', '秒', '§U7'],
    ['dockTime', '配对吸附飞行时长', '秒', '§4.2'],
    ['bagBias', '珠子袋偏向可用池的概率', '比值', '§17.5 / §39 / §54']
  ]},
  { name: '消除与爆炸', ref: '§19 / §28 / §30', items: [
    ['backFrames', '消除后退的帧数', '帧', '§36'],
    ['backStopFrames', '后退期间暂停推进的帧数', '帧', '§28.6']
  ]},
  { name: '生命与过关', ref: '§53 / §55 / §56', items: [
    ['startLives', '初始生命', '条', '§A15'],
    ['losingSpeed', '失败演出时珠子被吸入洞穴的速度', '设计单位/秒', '§U11'],
    ['scorePerBall', '每消除一颗的分数', '分', '§U11'],
    ['scoreTarget', '分数过关目标（无尽关用）', '分', '§53'],
    ['winOnClear', '清空过关开关', '布尔', '§52 / §55'],
    ['ballBudget', '球数预算（0 = 无限出球）', '颗', '§55'],
    ['baseRepeat', '同碱基成段概率（原版 mBallRepeat）', '概率', '§54']
  ]},
  { name: '模式与表现', ref: '§46 / §60 / §64', items: [
    ['defaultMode', '默认模式', '枚举', '§46 / §65'],
    ['modeFlashTime', '模式按钮高亮时长', '秒', '§46'],
    ['mergeTime', '加球并入动画时长', '秒', '§U12'],
    ['insertPairs', '并入后是否自动配对', '布尔', '§18'],
    ['retreatTime', '消除后退的视觉缓动时长', '秒', '§36']
  ]}
];

const val = function (k) {
  const v = DESIGN[k];
  if (typeof v === 'number') return Math.abs(v) < 1e-9 && v !== 0 ? v : v;
  return v;
};

const json = {
  generatedBy: 'miliastra/tools/export-params.mjs',
  source: 'Zuma/src（本作的设计真源）',
  unitNote: '全部长度都是"设计单位"，参考视口 900×900。移植时乘一个统一比例即可。',
  groups: GROUPS.map(function (g) {
    return {
      name: g.name, ref: g.ref,
      items: g.items.map(function (it) {
        return { key: it[0], name: it[1], unit: it[2], ref: it[3], value: val(it[0]) };
      })
    };
  }),
  chemistry: { bases: BASES, complement: COMPLEMENT },
  levelCount: { tutorials: TUTORIALS.length, core: ALL_LEVELS.length - TUTORIALS.length, total: ALL_LEVELS.length },
  modes: ['match', 'insert']
};

fs.writeFileSync(path.join(OUT, 'params.json'), JSON.stringify(json, null, 1));

const md = [];
md.push('# 移植参数表（照抄到千星奇域编辑器用）');
md.push('');
md.push('由 miliastra/tools/export-params.mjs 生成，**不要手改**。');
md.push('');
md.push('没有列进这张表的常量（渲染配色、调试开关之类）不需要移植。');
md.push('');
md.push('⚠ 两条**必须一起看**的话：');
md.push('');
md.push('- **冒球率 = chainSpeed / 球距 p** —— 想改难度就改这两个的比值，单改一个会连带改动另一件事；');
md.push('- **静置到洞穴的时间 = 轨道长 / chainSpeed** —— 这就是玩家不做任何事时的时限。');
md.push('');
for (const g of json.groups) {
  md.push('## ' + g.name + '（' + g.ref + '）');
  md.push('');
  md.push('| 常量 | 含义 | 值 | 单位 | 出处 |');
  md.push('|---|---|---|---|---|');
  for (const it of g.items) {
    md.push('| ' + it.key + ' | ' + it.name + ' | ' + it.value + ' | ' + it.unit + ' | ' + it.ref + ' |');
  }
  md.push('');
}
md.push('## 碱基化学（§4.4 / §A16）');
md.push('');
md.push('配对表：' + json.chemistry.bases.map(function (b) {
  return b + '-' + json.chemistry.complement[b].join('/');
}).join('　'));
md.push('');
md.push('⚠ **不对称**：A 是唯一的双配碱基（U 或 T）。移植时别写成对称表。');
md.push('');
md.push('## 关卡');
md.push('');
md.push('新手关 ' + json.levelCount.tutorials + ' + 核心关 ' + json.levelCount.core + ' = ' + json.levelCount.total + ' 关，逐关数据见 paths.md / paths.json。');
md.push('');
md.push('## 模式');
md.push('');
md.push('玩家可切换的只有两个：' + json.modes.join(' / ') + '。');
md.push('（第三个模式 seven（七球·元素）**代码里还在但不上按钮**，见 DESIGN.md §65 —— 移植时不要做它。）');
fs.writeFileSync(path.join(OUT, 'params.md'), md.join(String.fromCharCode(10)));

console.log('[export-params] 分组 ' + json.groups.length +
  '，常量 ' + json.groups.reduce(function (a, g) { return a + g.items.length; }, 0) +
  ' -> miliastra/out/params.json + params.md');
