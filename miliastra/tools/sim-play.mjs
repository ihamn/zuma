// sim-play.mjs —— 在**千星奇域客户端 Lua 运行时**里跑我们的脚本（本地试玩台）。
//
// 为什么要有它：真机（云电脑上的千星沙箱）拿到反馈要几分钟一轮，而且只能看到最后结果。
// 这个工具用社区的模拟器运行时（qxqy / miliastra-beyond-simulator 的 client/lua-runtime）
// 在本地把 zuma.lua 真跑起来：控件真的是 Instantiate 出来的、光标事件真的是派发的，
// 于是"画面上会出现什么"在**上传之前**就能看见。
//
// 它不是什么：**不是真机证明**。模拟器与真机必然有差异（官方契约 §14 的 imageType、
// Fengari 的 32 位整数……），这里过了不等于真机过了。真机结论只能来自真机。
//
// 用法：
//   node miliastra/tools/sim-play.mjs                          # 跑 90 帧，打印日志 + 控件统计
//   node miliastra/tools/sim-play.mjs --frames=600 --play      # 带"机器人点击"，看得出球被读掉
//   node miliastra/tools/sim-play.mjs --level=6 --frames=300   # 换一关（6 = 洞穴，有轨道会动）
//   node miliastra/tools/sim-play.mjs --json=miliastra/out/sim.json   # 导出控件树（给 sim-render.py 画图）
//
// 模拟器在哪儿：默认找 D:/miliastra-beyond-simulator（可用 ZUMA_SIM 覆盖）。
// 找不到就**跳过**（退出码 0）—— 手机端没有这个仓库，不该因此让 run-all 变红。

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT } from './lib/lua-runner.mjs';
import { checkControlBudget } from './lib/platform-limits.mjs';

const args = process.argv.slice(2);
const flag = (name, dflt) => {
  const hit = args.find((a) => a === '--' + name || a.startsWith('--' + name + '='));
  if (!hit) return dflt;
  const eq = hit.indexOf('=');
  return eq >= 0 ? hit.slice(eq + 1) : true;
};
const scriptArg = args.find((a) => !a.startsWith('--'));

const SIM_CANDIDATES = [
  process.env.ZUMA_SIM,
  'D:/miliastra-beyond-simulator',
  path.resolve(ROOT, '..', '..', 'miliastra-beyond-simulator'),
  path.resolve(ROOT, '..', 'miliastra-beyond-simulator'),
].filter(Boolean);

function findRuntime() {
  for (const dir of SIM_CANDIDATES) {
    const entry = path.join(dir, 'client', 'lua-runtime', 'src', 'index.js');
    if (fs.existsSync(entry)) return entry;
  }
  return null;
}

const entry = findRuntime();
if (!entry) {
  console.log('试玩台：跳过（没找到模拟器运行时 client/lua-runtime/src/index.js）');
  console.log('  找过：' + SIM_CANDIDATES.join('\n        '));
  console.log('  想要的话：把 miliastra-beyond-simulator 放到其中一个位置，或设 ZUMA_SIM 指过去。');
  process.exit(0);
}

const scriptPath = path.resolve(ROOT, scriptArg || path.join('out', 'zuma.lua'));
const frames = Number(flag('frames', 90));
const play = !!flag('play', false);
const level = Number(flag('level', 1));
const jsonPath = flag('json', null);
const clickEvery = Number(flag('clickEvery', 6));
const canvasW = Number(flag('w', 1600));
const canvasH = Number(flag('h', 900));

if (!fs.existsSync(scriptPath)) throw new Error('脚本不存在：' + scriptPath);
const source = fs.readFileSync(scriptPath, 'utf8');

const { createRuntime, walkControls, unpackRgba } = await import(pathToFileURL(entry).href);

const rt = createRuntime({ canvasWidth: canvasW, canvasHeight: canvasH });

// 游戏里"客户端控件容器画布" + 4 个控件模板（与 pc/manual.html 里让用户建的一一对应）
const root = rt.addRoot({ name: 'Canvas', kind: 'container' })
rt.registerTemplate(1, { kind: 'image', name: 'Ball' })
rt.registerTemplate(2, { kind: 'textbox', name: 'Text' })
rt.registerTemplate(3, { kind: 'cursor', name: 'CursorArea' })
rt.registerTemplate(4, { kind: 'container', name: 'PlayArea' })

const mounted = rt.mountScript({
  path: 'main',
  source,
  control: root,
  params: {
    ballPrefab: 1, shotPrefab: 1, hudPrefab: 2, cursorPrefab: 3, playPrefab: 4,
    levelIndex: level, diag: 1, autoNext: 0, ballCount: 96, shotCount: 8,
  },
})

// ---- 坐标：控件 anchoredPosition 是"相对父级中心、y 向上"，游戏里用的是"画布像素、原点左上、y 向下"。
//      两者互换就是游戏自己的 view 公式（config.viewFor: cx=w/2, cy=h/2），所以这里反转回去。----
function absPos(c) {
  let x = 0
  let y = 0
  for (let n = c; n; n = n.parent) {
    x += n.anchoredPositionX || 0
    y += n.anchoredPositionY || 0
  }
  return { x: canvasW / 2 + x, y: canvasH / 2 - y }
}

// 枚举字段在运行时里可能是 EnumItem（有 Name），也可能已经是字符串 —— 统一取名字
const enumName = (v) => (v && typeof v === 'object' && v.Name != null ? String(v.Name) : (v == null ? null : String(v)))

function snapshot() {
  const out = []
  walkControls(root, (c) => {
    const p = absPos(c)
    const item = {
      kind: c.kind,
      name: c.name || '',
      id: c.Id,
      active: c.active === true,
      visible: c.visible !== false,
      x: +p.x.toFixed(2),
      y: +p.y.toFixed(2),
      // 缩放：动效靠它做"弹出/淡出"（sim-render 会乘进尺寸里）
      scale: +(c.localScaleX ?? 1).toFixed(3),
      w: +((c.sizeDeltaX || 0) * (c.localScaleX ?? 1)).toFixed(2),
      h: +((c.sizeDeltaY || 0) * (c.localScaleY ?? 1)).toFixed(2),
      rot: +(c.localRotationZ || 0).toFixed(3),   // 瞄准线/连线靠它摆方向（sim-render 会画出来）
      pivot: +(c.pivotX ?? 0.5),                  // 旋转绕哪一点：0.5 = 绕中心
    }
    if (c.kind === 'image') {
      const [r, g, b, a] = unpackRgba(Number(c.imageColor) >>> 0)
      item.color = [r, g, b, a]
      // 柔边（发光）：图片控件没有描边，靠它糊一圈
      if (c.enableSoftEdge) item.soft = +(c.softEdgeWidthX ?? 0)
      // 径向填充：冷却环用它画弧
      const ft = enumName(c.fillType)
      if (ft && ft !== 'Unused') {
        item.fill = { type: ft, amount: +(c.fillAmount ?? 1), from: enumName(c.fillRadialType) }
      }
    } else if (c.kind === 'textbox') {
      item.text = c.text || ''
      item.fontSize = c.fontSize
      item.align = enumName(c.horizontalAlignment)
      item.valign = enumName(c.verticalAlignment)
      const [fr, fg, fb, fa] = unpackRgba(Number(c.fontColor ?? 0xffffffff) >>> 0)
      item.fontColor = [fr, fg, fb, fa]
      const [br, bg, bb, ba] = unpackRgba(Number(c.bgColor ?? 0) >>> 0)
      item.bgColor = [br, bg, bb, ba]
      item.outline = c.enableOutline === true
    }
    out.push(item)
  })
  return out
}

// 供机器人点击用：找一块铺满画布、能接收光标事件的区域
function findCursorArea() {
  let hit = null
  walkControls(root, (c) => {
    if (!hit && c.kind === 'cursor' && c.active === true) hit = c
  })
  return hit
}

// ---- 机器人：把光标挪到一颗"可见的球"中心再点一下，和真人操作同一条路径 ----
function pickTarget() {
  let best = null
  walkControls(root, (c) => {
    if (c.kind !== 'image' || c.active !== true || c.visible === false) return
    if ((c.sizeDeltaX || 0) < 4) return
    const p = absPos(c)
    // 越靠下（y 大）越可能是还没读出的球；随便挑一颗就行，这里只要"看得出在玩"
    if (!best || p.y > best.y) best = { x: p.x, y: p.y }
  })
  return best
}

const cursorArea = findCursorArea();
for (let f = 0; f < frames; f++) {
  if (play && cursorArea && f % clickEvery === 0) {
    const t = pickTarget()
    // ★★ 坐标系别搞混（官方《客户端控件 API 文档》）：
    //   GetCursorUIPos / CursorEventData:GetUIPos() 是「**以画布左下角为原点**、y 向上」，
    //   而上面 absPos() 算的是「左上角为原点、y 向下」的屏幕坐标。
    //   直接把屏幕坐标塞进去 = 上下镜像 → 瞄准会朝反方向（这个坑我自己踩过一次：
    //   截图里瞄准线朝上，游戏其实没错，是机器人点错了地方）。
    if (t) rt.injectCursor(cursorArea, 'CursorClick', { x: t.x, y: canvasH - t.y, dragging: false, touchId: 1 })
  }
  rt.step(1 / 30)
}

// --probe=xxx.lua：跑完帧数之后在**同一个 Lua 环境里**执行一段探针（用 print 输出，会进日志）。
// 用处：控件树只能说"画出来是什么"，模型里到底有没有 base / 状态对不对，得问 Lua 自己。
// ⚠ 脚本跑在**独立的 Lua 线程**里（mountScript 用 newLuaThread），全局 `ZUMA` 不在主状态里 ——
//   所以探针必须塞进 rec.env，别用 rt.L。
const probePath = flag('probe', null)
if (probePath) {
  const src = fs.readFileSync(path.resolve(probePath), 'utf8')
  try {
    rt.runChunk(mounted.env || rt.L, src, 'probe')
  } catch (e) {
    console.log('[zuma] probe 出错：' + (e && e.message ? e.message : e))
  }
}

console.log('='.repeat(70));
console.log('试玩台：' + path.relative(ROOT, scriptPath) + '（' + source.length + ' 字符）');
console.log('  画布 ' + canvasW + 'x' + canvasH + '，第 ' + level + ' 关，跑 ' + frames + ' 帧' + (play ? '，带机器人点击' : ''));
console.log('  运行时：' + entry);
console.log('='.repeat(70));

// ★★ 已知假象（写在代码里，别让人对着白球查半天）：
//   这个模拟器跑在 Fengari 上，**整数是 32 位** —— `0xFFFFFFFF` 会变成 -1，
//   于是 rng.lua 里 `(x & 0xFFFFFFFF)` 收不回无符号数，step() 的取值域会变成 [-0.5, 0.5)，
//   rng.pick 约一半的抽签取到 nil → 碱基变成 nil → 球画成白色、字母回落成第一张图。
//   真机是 Lua 5.3（64 位整数），不会这样；对拍/本地测试用的是原生 64 位 Lua，所以是绿的。
//   证据：官方契约 §18「Fengari 的整数仍是 32 位，这是已知的底层限制，不能作为客户端整数结论」。
//   实测（2026-09-25）：Fengari 下 20000 次 step() 有 10101 次越界，rng.pick 200 次有 105 次取到 nil。
let intBits = 64;
try {
  rt.runChunk(mounted.env || rt.L, "if 0xFFFFFFFF == -1 then print('[zuma] 整数位宽探针：32 位（Fengari）') else print('[zuma] 整数位宽探针：64 位') end", 'int-probe');
  intBits = (rt.logs || []).some((l) => String(l.text).includes('32 位')) ? 32 : 64;
} catch { /* 探针失败就当 64 位，不影响主流程 */ }

console.log('\n--- 日志（print / printerr / lua-error）---');
const logs = rt.logs || [];
if (!logs.length) console.log('  （没有任何日志）');
for (const l of logs) console.log('  [' + l.level + '] ' + l.text);
if (rt.mountErrors && rt.mountErrors.length) {
  console.log('\n--- mountErrors ---');
  for (const e of rt.mountErrors) console.log('  ' + e);
}

const snap = snapshot();
const visibleImages = snap.filter((c) => c.kind === 'image' && c.visible && c.active);
const texts = snap.filter((c) => c.kind === 'textbox' && c.text);
console.log('\n--- 沙箱里的控件树 ---');
console.log('  控件总数（含画布）：' + snap.length);
// ★ 官方硬限制：单个界面控件组内界面控件最大 1000（我们全挂在同一个画布容器下 = 一组）
{
  const r = checkControlBudget(snap.length - 1);       // 减掉画布本身
  console.log('  控件预算：' + r.count + ' / ' + r.max +
    (r.ok ? ' ✓ 还剩 ' + (r.max - r.count) : ' ★★ 超了 ' + r.over + ' 个'));
}
console.log('  可见图片控件：' + visibleImages.length);
const colors = {};
for (const c of visibleImages) {
  const hex = '#' + c.color.slice(0, 3).map((v) => v.toString(16).padStart(2, '0')).join('');
  colors[hex] = (colors[hex] || 0) + 1;
}
console.log('  球面颜色分布：' + JSON.stringify(colors));
console.log('  文本：' + (texts.length ? texts.map((t) => JSON.stringify(t.text)).join(' | ') : '（没有文本）'));

if (intBits === 32) {
  console.log('\n⚠ 这个模拟器的 Lua 整数是 32 位（Fengari）：rng 会约一半取到 nil，');
  console.log('  所以画面上**白球 / 字母缺失**是模拟器假象，不是游戏的 bug（真机是 64 位 Lua 5.3）。');
  console.log('  颜色分布里出现一堆 #ffffff 就是这个原因，别拿它当验收结论。');
}

if (jsonPath) {
  const out = path.resolve(jsonPath);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify({
    canvas: { w: canvasW, h: canvasH },
    script: path.relative(ROOT, scriptPath),
    level, frames, play,
    intBits,          // 32 = Fengari：白球是假象（sim-render 会把它画进图里）
    controls: snap,
  }, null, 1));
  console.log('\n控件树已导出：' + path.relative(process.cwd(), out) + '（画图：node miliastra/tools/sim-render.mjs）');
}

rt.destroy();
process.exit(0);
