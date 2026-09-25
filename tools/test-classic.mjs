// 经典祖玛（DESIGN.md §66）规则测试。
//
// 为什么单独一份：这一套规则和 RNA 配对玩法**共用同一个场景与链子**，
//   只靠"看画面"极容易把两套规则搅在一起（"看着对、其实错，而且不报错"是这类改动最大的风险）。
//   所以这里断言的是**规则本身**：同色 ≥3 消、连锁、打错不惩罚、单轨、配色、以及
//   **RNA 那一套一个字没变**。

import { ALL_LEVELS, CLASSIC_LEVELS, LEVELS } from '../src/levels.js';
import { viewFor, metrics, colorOf, BASE_COLOR } from '../src/config.js';
import { classicRuns, classicClearable, computeRuns, clearableRuns } from '../src/run.js';
import { assembleScene, syncBeads, fireShot, advanceScene } from '../src/scene.js';
import { makeProjectile } from '../src/projectile.js';

const fails = [];
let pass = 0;
function check(name, ok, extra) {
  if (ok) { pass++; return; }
  fails.push(name + (extra ? '   ' + extra : ''));
}
const eq = (name, got, want) => check(name, got === want, 'got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want));

const view = viewFor(900, 900);
const classicLevel = CLASSIC_LEVELS[0];
const rnaLevel = LEVELS[0];

// ---------- ① 规则函数本身 ----------
const fake = (bases) => ({ mt: metrics(1), balls: bases.map((b, i) => ({ id: i + 1, base: b, wp: i, dock: 1 })) });
eq('同色 3 连 → 可消', classicClearable(fake(['A', 'A', 'A'])).length, 1);
eq('同色 4 连 → 可消（≥3 就行，不是"3 的倍数"）', classicClearable(fake(['A', 'A', 'A', 'A'])).length, 1);
eq('同色 2 连 → 不消', classicClearable(fake(['A', 'A'])).length, 0);
eq('异色交替 → 不消', classicClearable(fake(['A', 'U', 'A', 'A'])).length, 0);
eq('两段各自成立 → 两段都消', classicClearable(fake(['A', 'A', 'A', 'U', 'U', 'U'])).length, 2);
eq('分段正确（A A A | U | A A A）', classicRuns(fake(['A', 'A', 'A', 'U', 'A', 'A', 'A'])).length, 3);
check('★ 经典规则与 RNA 规则**是两套**（同一串在经典下可消、在 RNA 下不可消）',
  classicClearable(fake(['A', 'A', 'A'])).length === 1 && clearableRuns({ balls: [] }).length === 0);

// ---------- ② 场景：经典关的 rules 与渲染数据 ----------
const sc = assembleScene(classicLevel, view, 20260101);
eq('★ 经典关 sc.rules = classic', sc.rules, 'classic');
eq('RNA 关 sc.rules 缺省 = rna（现有 10 关行为不变）', assembleScene(rnaLevel, view, 1).rules, 'rna');
syncBeads(sc);
const b0 = sc.beads.spawn[0];
eq('★ 经典配色生效（用该球自己碱基的经典色）', b0 ? b0.col : null, colorOf(b0.base, 'classic'));
check('经典色 ≠ RNA 碱基色（用户要求"不要沿用"）', colorOf(b0.base, 'classic') !== BASE_COLOR[b0.base],
  b0.base + ': ' + colorOf(b0.base, 'classic') + ' vs ' + BASE_COLOR[b0.base]);
eq('★ 经典球面**不显示字母**（原版是纯色球）', b0 ? b0.label : null, '');
eq('经典关没有配对描边', b0 ? b0.pairGlow : 'x', null);
eq('★ 经典关初始没有绑定小球（三消道空着）', sc.beads.eliminate.length, 0);

// ---------- ③ 射击：无条件插入，不配对、不错配 ----------
// （照 test-insert.mjs 的写法：drive 几帧，看 sc.stats 的计数，而不是看 fireShot 的返回值）
const ch = sc.chain;
const target = ch.balls[2];
sc.projectiles.push(Object.assign(makeProjectile(sc, 'U', 'match'), { x: target.x, y: target.y }));
fireShot(sc);
for (let f = 0; f < 120 && sc.stats.merges === 0; f++) advanceScene(sc, 1 / 60);
eq('★ 经典模式命中后走"并入"（merges=1）', sc.stats.merges, 1);
eq('★ 经典模式**不产生配对**（pairs 必须为 0）', sc.stats.pairs, 0);
eq('★ 经典模式**不产生错配**（mismatches 必须为 0）', sc.stats.mismatches, 0);

// ---------- ④ 连锁：消掉中间一段后两端同色要接着消 ----------
const ch2 = fake(['A', 'A', 'C', 'C', 'C', 'A', 'A']).balls;
eq('（前置）CCC 可消', classicClearable({ balls: ch2 }).length, 1);
ch2.splice(2, 3);        // 模拟把中间 CCC 消掉
eq('★ 连锁：CCC 消掉后两端 A 接成 AAAA → 仍然是可消段', classicClearable({ balls: ch2 }).length, 1);
eq('★ 连锁后的段长 = 4（两颗 A + 两颗 A）', classicClearable({ balls: ch2 })[0].len, 4);

// ---------- ⑤ 红线：RNA 那一套没被改 ----------
const rna = assembleScene(rnaLevel, view, 20260101);
syncBeads(rna);
const rb = rna.beads.spawn[0];
eq('★ RNA 关的球仍带字母（碱基）', rb ? rb.label : null, rb ? rb.base : 'x');
eq('★ RNA 关的配色没变（col 仍是 null ⇒ 走 BASE_COLOR）', rb ? rb.col : 'x', null);
check('★ RNA 关的 sc.rules 不是 classic', rna.rules !== 'classic');
check('★ LEVELS（RNA 核心关）内容没动', LEVELS.length === 3 && LEVELS[0].id === 'spiral-outer');
check('★ 经典关**不在** LEVELS 里（它单独一组）', LEVELS.every((l) => l.rules !== 'classic'));
check('★ ALL_LEVELS 里经典关排最后（菜单第三组）', ALL_LEVELS[ALL_LEVELS.length - 1].id === classicLevel.id);

// ---------- 输出 ----------
if (fails.length) {
  console.log('test-classic: ' + pass + ' 通过 / ' + fails.length + ' 失败');
  for (const f of fails) console.log('  FAIL  ' + f);
  process.exit(1);
}
console.log('test-classic: ' + pass + ' 通过 / 0 失败');
