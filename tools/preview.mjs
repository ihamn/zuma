// 无头光栅预览器：不开浏览器也能"看见"轨道 / 遮挡层级 / 球尺寸。
// 复用与游戏相同的装配逻辑（scene.js）与分层顺序（与 render.js 一致）。
//
// 用法：
//   node tools/preview.mjs <关卡序号> [输出边长] [输出文件] [zoom] [中心x] [中心y] [debug]
// 世界坐标固定 900x900（= 设计基准），zoom>1 时以 (中心x,中心y) 为中心放大。

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { viewFor, BASE_COLOR, WRONG_COLOR, COMPLEMENT } from '../src/config.js';
import { LEVELS } from '../src/levels.js';
import { assembleScene, advanceScene, sceneInfo, fireShot, syncBeads, setMode } from '../src/scene.js';
import { elemColor } from '../src/elements.js';
import { removeRange, chainRuns } from '../src/chain.js';
import { isComplement } from '../src/config.js';
import { aimAt } from '../src/ribosome.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');

let VIEWW = 900, VIEWH = 900;   // 真实视口尺寸（用 view=WxH 指定，比如手机竖屏 400x850）
const SS = 2;
// 位置参数只取不带 key=value 的那些，仿真选项（frames=/cut=）另算
// 先扫一遍 view=，其余位置参数在它之后才算
for (let ai = 2; ai < process.argv.length; ai++) {
  const a = process.argv[ai];
  if (a.indexOf('view=') === 0) { const vv = a.slice(5).split('x'); VIEWW = parseInt(vv[0], 10); VIEWH = parseInt(vv[1], 10); }
}
const POS = process.argv.slice(2).filter(function (a) { return a.indexOf('=') < 0 && a !== 'autofire'; });
const LEVEL_INDEX = parseInt(POS[0] || '0', 10);
const OUT_WH = (POS[1] || '900').split('x');
const OUT_W = parseInt(OUT_WH[0], 10);
const OUT_H = parseInt(OUT_WH[1] || OUT_WH[0], 10);
const OUT_FILE = POS[2] || path.join(ROOT, 'preview-L' + LEVEL_INDEX + '.png');
const ZOOM = parseFloat(POS[3] || '1');
const CX = POS[4] ? parseFloat(POS[4]) : VIEWW / 2;
const CY = POS[5] ? parseFloat(POS[5]) : VIEWH / 2;
const DEBUG = POS[6] === 'debug';

// ---------- 极简 PNG 编码 ----------
const CRC_TABLE = (function () {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
function writePng(file, w, h, rgb) {
  const stride = w * 3;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    rgb.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 6 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
  fs.writeFileSync(file, png);
  return png.length;
}

// ---------- 光栅器（带世界->缓冲变换） ----------
function rgbOf(hex) {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)];
}
class Raster {
  constructor(w, h, k, ox, oy) {
    this.w = w; this.h = h; this.k = k; this.ox = ox; this.oy = oy;
    this.buf = Buffer.alloc(w * h * 3);
  }
  clear(rgb) {
    for (let i = 0; i < this.buf.length; i += 3) { this.buf[i] = rgb[0]; this.buf[i + 1] = rgb[1]; this.buf[i + 2] = rgb[2]; }
  }
  disc(cxw, cyw, radw, rgb) {
    const k = this.k;
    const cx = (cxw - this.ox) * k, cy = (cyw - this.oy) * k, rad = radw * k;
    if (cx + rad < 0 || cy + rad < 0 || cx - rad > this.w || cy - rad > this.h) return;
    const x0 = Math.max(0, Math.floor(cx - rad)), x1 = Math.min(this.w - 1, Math.ceil(cx + rad));
    const y0 = Math.max(0, Math.floor(cy - rad)), y1 = Math.min(this.h - 1, Math.ceil(cy + rad));
    const r2 = rad * rad;
    for (let y = y0; y <= y1; y++) {
      const dy = y - cy;
      for (let x = x0; x <= x1; x++) {
        const dx = x - cx;
        if (dx * dx + dy * dy <= r2) {
          const i = (y * this.w + x) * 3;
          this.buf[i] = rgb[0]; this.buf[i + 1] = rgb[1]; this.buf[i + 2] = rgb[2];
        }
      }
    }
  }
  polyline(pts, i0, i1, widthW, rgb, stride, off) {
    const radW = widthW / 2;
    const dx = off || 0, dy = off ? off * 1.3 : 0;
    for (let i = i0; i < i1; i += stride) {
      const a = { x: pts[i].x + dx, y: pts[i].y + dy };
      const bb = pts[Math.min(i1, i + stride)];
      const b = { x: bb.x + dx, y: bb.y + dy };
      const d = Math.hypot(b.x - a.x, b.y - a.y);
      const n = Math.max(1, Math.ceil(d / Math.max(0.5, radW * 0.5)));
      for (let kk = 0; kk <= n; kk++) {
        const t = kk / n;
        this.disc(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, radW, rgb);
      }
    }
  }
  downsample(ss, outW, outH) {
    const out = Buffer.alloc(outW * outH * 3);
    const inv = 1 / (ss * ss);
    for (let y = 0; y < outH; y++) {
      for (let x = 0; x < outW; x++) {
        let r = 0, g = 0, b = 0;
        for (let sy = 0; sy < ss; sy++) {
          for (let sx = 0; sx < ss; sx++) {
            const i = ((y * ss + sy) * this.w + (x * ss + sx)) * 3;
            r += this.buf[i]; g += this.buf[i + 1]; b += this.buf[i + 2];
          }
        }
        const o = (y * outW + x) * 3;
        out[o] = r * inv; out[o + 1] = g * inv; out[o + 2] = b * inv;
      }
    }
    return out;
  }
}

// ---------- 装配 ----------
const level = LEVELS[LEVEL_INDEX];
if (!level) { console.log('preview: 关卡序号越界'); process.exit(1); }
const view = viewFor(VIEWW, VIEWH);   // 世界坐标 = 真实视口坐标
const sc = assembleScene(level, view, 20260101 + LEVEL_INDEX * 977);
const mt = sc.metrics;

// 仿真选项：frames=N 先跑 N 帧；cut=i0-i1 在第 3 帧切掉一段（用来看空隙与回缩）
let FRAMES = 0, CUT = null, AUTOFIRE = false, AUTOFIRE_ANY = false, MARKS = null, MODE = 'match';
for (let ai = 2; ai < process.argv.length; ai++) {
  const a = process.argv[ai];
  if (a.indexOf('frames=') === 0) FRAMES = parseInt(a.slice(7), 10) || 0;
  if (a === 'autofire') AUTOFIRE = true;
  if (a === 'autofire=any') { AUTOFIRE = true; AUTOFIRE_ANY = true; }
  // mode=seven 用七球模式出图（§57）：球本身就是元素色（火水冰雷草岩风），可能还有草原核
  if (a.indexOf('mode=') === 0) MODE = a.slice(5);
  // marks=1,1,0,2,0 —— 直接给链上第 1..n 颗球设状态（0/1/2）。
  // 给"2 态 / 爆炸"做确定性视觉检查用（autofire 抓不稳：错配的小球常常在出图前就被炸掉了）。
  if (a.indexOf('marks=') === 0) {
    MARKS = a.slice(6).split(',').map(function (x) { return parseInt(x, 10) || 0; });
  }
  if (a.indexOf('view=') === 0) { const vv = a.slice(5).split('x'); VIEWW = parseInt(vv[0], 10); VIEWH = parseInt(vv[1], 10); }
  if (a.indexOf('cut=') === 0) { const p = a.slice(4).split('-'); CUT = [parseInt(p[0], 10), parseInt(p[1], 10)]; }
}
// ⚠ 必须放在参数解析之后 —— MODE 是 let 声明的，放在前面会踩 TDZ（Cannot access before initialization）
if (MODE !== 'match') setMode(sc, MODE);
// marks=1,1,0,2,0：直接布置状态，用来做**确定性**的视觉检查。
// 例：marks=1,2,0,1,0,2,1 —— 两颗 2 都处于"稳定"形态（120 与 021），不会被结算掉。
if (MARKS) {
  sc.stopAdding = true;
  const bs = sc.chain.balls;
  for (let i = 0; i < MARKS.length && i < bs.length; i++) {
    const m = MARKS[i];
    bs[i].paired = m !== 0;
    bs[i].wrongMark = m === 2;
    bs[i].pairBase = m === 0 ? null : COMPLEMENT[bs[i].base][0];
    bs[i].dock = m !== 0 ? 1 : null;
  }
  syncBeads(sc);
  console.log('  marks 布置: ' + MARKS.join(''));
}

function describeRuns(ch) {
  const rs = chainRuns(ch);
  const parts = rs.map(function (r) {
    return '[' + r.i0 + '-' + r.i1 + '] wp ' + ch.balls[r.i1].wp.toFixed(1) + '~' + ch.balls[r.i0].wp.toFixed(1);
  });
  return '段数=' + rs.length + '  ' + parts.join('  |  ');
}
const report = [];
for (let f = 0; f < FRAMES; f++) {
  if (CUT && f === 3) { removeRange(sc.chain, CUT[0], CUT[1]); report.push('  第3帧切掉 ' + (CUT[1] - CUT[0] + 1) + ' 颗'); }
  if (AUTOFIRE) {
    const bs = sc.chain.balls;
    for (let bi = 0; bi < bs.length; bi++) {
      const b = bs[bi];
      if (b.paired) continue;
      if (!AUTOFIRE_ANY && !isComplement(sc.rb.loaded[0], b.base)) continue;
      aimAt(sc.rb, b.x, b.y);
      fireShot(sc);
      break;
    }
  }
  advanceScene(sc, 1 / 60);
  if (CUT && (f === 8 || f === 60 || f === 120 || f === FRAMES - 1)) report.push('  第' + f + '帧 ' + describeRuns(sc.chain));
}
const si = sceneInfo(sc);

const k = ZOOM * SS;
const ox = CX - OUT_W / (2 * ZOOM);
const oy = CY - OUT_H / (2 * ZOOM);
const R = new Raster(OUT_W * SS, OUT_H * SS, k, ox, oy);
R.clear([7, 10, 16]);

const C = {
  bed: [17, 25, 41],
  bedTop: [26, 38, 60],
  laneSpawn: [30, 45, 68],
  laneElim: [25, 38, 57],
  rimSpawn: [72, 105, 152],
  rimElim: [64, 140, 118],
  cave: [150, 30, 50]
};

const BED_W = 2 * (mt.d / 2 + mt.R) + 10 * mt.scale;
const LINKQ = [];
const stride = 4;

if (DEBUG) {
  // 骨架（黄）+ 法线（青）
  R.polyline(sc.path.pts, 0, sc.path.pts.length - 1, 0.8, [200, 180, 60], 4);
  for (let i = 0; i < sc.path.pts.length; i += 40) {
    const p = sc.path.pts[i];
    R.disc(p.x, p.y, 1.4, [0, 255, 255]);
    R.polyline([p, { x: p.x + p.nx * 14, y: p.y + p.ny * 14 }], 0, 1, 0.7, [0, 200, 220], 1);
  }
  sc.issues.forEach(function (it) {
    if (it.x == null) return;
    const col = it.severity === 'error' ? [255, 90, 95] : (it.severity === 'warn' ? [255, 210, 63] : [67, 209, 122]);
    for (let a = 0; a < 24; a++) {
      const t0 = (a / 24) * Math.PI * 2, t1 = ((a + 0.6) / 24) * Math.PI * 2;
      R.disc(it.x + Math.cos(t0) * 16, it.y + Math.sin(t0) * 16, 1.2, col);
    }
  });
}

for (let zi = 0; zi < sc.zLevels.length; zi++) {
  const z = sc.zLevels[zi];
  const runs = sc.runs.spawn;
  for (let i = 0; i < runs.length; i++) {
    const run = runs[i];
    if (run.z !== z) continue;
    if (z > 0) R.polyline(sc.path.pts, run.i0, run.i1, BED_W, [3, 4, 7], stride, 1.6 * mt.scale);
    R.polyline(sc.path.pts, run.i0, run.i1, BED_W, z > 0 ? C.bedTop : C.bed, stride);
  }
  const ids = ['eliminate', 'spawn'];
  for (let kk = 0; kk < ids.length; kk++) {
    const id = ids[kk];
    const poly = sc.railPolys[id];
    const rail = sc.rails[id];
    for (let i = 0; i < runs.length; i++) {
      const run = runs[i];
      if (run.z !== z) continue;
      R.polyline(poly, run.i0, run.i1, 2 * rail.radius + 4 * mt.scale, id === 'spawn' ? C.laneSpawn : C.laneElim, stride);
      R.polyline(poly, run.i0, run.i1, 1.1 * mt.scale, id === 'spawn' ? C.rimSpawn : C.rimElim, stride);
    }
  }
  for (let kk = 0; kk < ids.length; kk++) {
    const list = sc.beads[ids[kk]];
    for (let i = 0; i < list.length; i++) {
      const b = list[i];
      if (b.z !== z) continue;
      if (b.partner) R.polyline([b, b.partner], 0, 1, 1.2, [120, 150, 178], 1);
      // 七球模式下 syncBeads 已经算好了 b.col（元素色）；匹配模式退回碱基色
      const col = rgbOf(b.wrong ? WRONG_COLOR : (b.col || BASE_COLOR[b.base] || '#8899aa'));
      if (b.partner) LINKQ.push({ b: b, col: col, wrong: b.wrong === true });
      if (b.pairGlow) { const gc = rgbOf(b.pairGlow); const rr = b.r + 1.8 * mt.scale;
        for (let aa = 0; aa < 48; aa++) { const th2 = aa / 48 * Math.PI * 2;
          R.disc(b.x + Math.cos(th2) * rr, b.y + Math.sin(th2) * rr, Math.max(1, b.r * 0.15), gc); } }
      R.disc(b.x, b.y, b.r, col);
      // §57 元素附着：内圈一道元素色环（和 render.js 同一套几何：0.80r、宽约 0.28r）
      if (b.elem) {
        const ec = rgbOf(elemColor(b.elem));
        for (let aa = 0; aa < 44; aa++) {          // 深色隔离环
          const th2 = aa / 44 * Math.PI * 2;
          R.disc(b.x + Math.cos(th2) * b.r * 0.92, b.y + Math.sin(th2) * b.r * 0.92, Math.max(1, b.r * 0.08), [6, 10, 18]);
        }
        for (let aa = 0; aa < 48; aa++) {          // 元素带：4 段断开（同 render.js）
          const th2 = aa / 48 * Math.PI * 2;
          const segT = th2 % (Math.PI / 2);
          if (segT < 0.24 || segT > Math.PI / 2 - 0.24) continue;
          R.disc(b.x + Math.cos(th2) * b.r * 0.78, b.y + Math.sin(th2) * b.r * 0.78, Math.max(1, b.r * 0.17), ec);
        }
      }
      // §57 冻结：外圈一道冰白环
      if (b.frozen > 0) {
        const rr3 = b.r * 1.04;
        for (let aa = 0; aa < 48; aa++) {
          const th3 = aa / 48 * Math.PI * 2;
          R.disc(b.x + Math.cos(th3) * rr3, b.y + Math.sin(th3) * rr3, Math.max(1, b.r * 0.13), [214, 246, 255]);
        }
      }
      R.disc(b.x - b.r * 0.3, b.y - b.r * 0.35, b.r * 0.34, [Math.min(255, col[0] + 90), Math.min(255, col[1] + 90), Math.min(255, col[2] + 90)]);
    }
  }
}

// §57 草原核：绿球 + 白色外环
if (sc.cores && sc.cores.length) {
  for (let ci = 0; ci < sc.cores.length; ci++) {
    const c = sc.cores[ci];
    const cr = mt.r * 0.78;
    R.disc(c.x, c.y, cr, [142, 222, 82]);
    for (let aa = 0; aa < 40; aa++) {
      const th4 = aa / 40 * Math.PI * 2;
      R.disc(c.x + Math.cos(th4) * (cr + 3), c.y + Math.sin(th4) * (cr + 3), Math.max(1, cr * 0.2), [235, 255, 200]);
    }
  }
}

// 配对连线：在所有珠子之后画（画在球之上）
for (let li = 0; li < LINKQ.length; li++) {
  const bb = LINKQ[li].b, col = LINKQ[li].col, wr = LINKQ[li].wrong;
  const ddx = bb.partner.x - bb.x, ddy = bb.partner.y - bb.y;
  const LL = Math.hypot(ddx, ddy) || 1, ppx = -ddy / LL, ppy = ddx / LL;
  const w2 = Math.max(3, 3.4 * mt.scale);
  if (!wr) {
    R.polyline([{ x: bb.x + ddx * 0.26, y: bb.y + ddy * 0.26 },
                { x: bb.x + ddx * 0.74, y: bb.y + ddy * 0.74 }], 0, 1, w2, col, 1);
  } else {
    const am = Math.max(2.5, 3.4 * mt.scale);
    R.polyline([{ x: bb.x + ddx * 0.26, y: bb.y + ddy * 0.26 },
                { x: bb.x + ddx * 0.42 + ppx * am, y: bb.y + ddy * 0.42 + ppy * am },
                { x: bb.x + ddx * 0.58 - ppx * am, y: bb.y + ddy * 0.58 - ppy * am },
                { x: bb.x + ddx * 0.74, y: bb.y + ddy * 0.74 }], 0, 1, w2, col, 1);
  }
}

const end = sc.path.pointAt(sc.path.length);
R.disc(end.x, end.y, mt.R * 1.5, C.cave);
R.disc(end.x, end.y, mt.R * 0.9, [8, 4, 8]);
R.disc(view.cx, view.cy, 30 * mt.scale, [34, 48, 63]);
R.disc(view.cx, view.cy, 30 * mt.scale * 0.55, [120, 170, 220]);

const out = R.downsample(SS, OUT_W, OUT_H);
const bytes = writePng(OUT_FILE, OUT_W, OUT_H, out);

const errs = sc.issues.filter(function (i) { return i.severity === 'error'; });
const bridges = sc.issues.filter(function (i) { return i.code === 'BRIDGE'; });
console.log('preview: ' + level.name + '  视口=' + VIEWW + 'x' + VIEWH + '  出图=' + OUT_W + 'x' + OUT_H + '  zoom=' + ZOOM + '  中心=(' + CX + ',' + CY + ')  ->  ' + path.relative(ROOT, OUT_FILE) + '（' + (bytes / 1024).toFixed(0) + 'KB）');
report.forEach(function (l) { console.log(l); });
console.log('  加球(并入)=' + si.stats.merges + '  并入中=' + si.merges);
console.log('  命中: 配对=' + si.stats.pairs + ' 错配=' + si.stats.mismatches + ' 发射=' + si.stats.fired + ' 三消道小球=' + si.paired);
console.log('  珠串: n=' + si.balls + ' 队头=' + si.headWp.toFixed(0) + '/' + si.curveLength.toFixed(0) + ' (' + (si.progress * 100).toFixed(1) + '%) 速度=' + si.speed.toFixed(1) + ' 段数=' + chainRuns(sc.chain).length);
console.log('  railOrder=' + level.railOrder + '  L=' + sc.path.length.toFixed(0) + '  R=' + mt.R.toFixed(1) + '  r=' + mt.r.toFixed(1) + '  d=' + mt.d.toFixed(1) + '  p=' + mt.p.toFixed(1) + '  珠(大/小)=' + sc.beads.spawn.length + '/' + sc.beads.eliminate.length + '  层=' + JSON.stringify(sc.zLevels) + '  桥=' + bridges.length + '  error=' + errs.length);

