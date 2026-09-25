// sim-render.mjs —— 把试玩台导出的控件树（sim-play.mjs --json=…）画成 PNG，好"看见"画面。
//
// 为什么值得有：我看不到真机屏幕，用户也未必每次都能截图；而"球到底在不在轨道上、
// HUD 排得对不对、颜色有没有反色、瞄准线朝哪"这些事，一张图比一百行日志快。
//
// 它画的是**沙箱里真实控件树**（位置/尺寸/颜色/透明度/对齐/旋转/径向填充都来自运行时），
// 不是我们自己的模型 —— 所以它同时是一次几何验收：球如果没落在轨道上，图上一眼就能看出来。
//
// ★ 它画不了：控件模板里的**图片素材**。球面的碱基字母现在是**文本框**（letters=1）所以看得见，
//   但素材自带的图案（如果有）看不到。
// ★ 模拟器不实现径向填充（studio 文档：径向 90/180/360 未实现），这里自己按 fillAmount 画成弧，
//   好让"冷却环"在预览里也看得出进度。
//
// 用法：
//   node miliastra/tools/sim-play.mjs --level=1 --json=miliastra/out/sim-L1.json
//   node miliastra/tools/sim-render.mjs miliastra/out/sim-L1.json miliastra/out/sim-L1.png
//   （不带参数时：读 out/sim.json，写 out/sim.png）

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { ROOT } from './lib/lua-runner.mjs';
import { findPython, hasModule } from './lib/python.mjs';

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
// 相对路径先按当前目录算（和 sim-play.mjs 的 --json 一致），再退回 miliastra/
const pick = (arg, dflt) => {
  const p = path.resolve(arg || dflt);
  if (fs.existsSync(p)) return p;
  return path.resolve(ROOT, arg || dflt);
};
const jsonPath = pick(args[0], path.join('out', 'sim.json'));
const pngPath = path.resolve(args[1] || jsonPath.replace(/\.json$/, '') + '.png');

if (!fs.existsSync(jsonPath)) {
  throw new Error('先跑试玩台导出控件树：node miliastra/tools/sim-play.mjs --json=' + path.relative(ROOT, jsonPath));
}
if (!hasModule('PIL')) {
  throw new Error('要画图得先有 Pillow：\n  ' + findPython().cmd + ' -m pip install pillow');
}

const py = String.raw`
import json, sys, os, math
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding='utf-8'))
W, H = data['canvas']['w'], data['canvas']['h']
img = Image.new('RGBA', (W, H), (16, 20, 24, 255))
d = ImageDraw.Draw(img, 'RGBA')

def load_font(size, bold=False):
    for name in (('msyhbd.ttc' if bold else 'msyh.ttc'), 'msyh.ttc', 'simhei.ttf', 'simsun.ttc'):
        p = os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'Fonts', name)
        if os.path.exists(p):
            try: return ImageFont.truetype(p, max(8, int(size)))
            except Exception: pass
    return ImageFont.load_default()

def rgba(c, scale=1.0):
    r, g, b, a = c
    return (int(r), int(g), int(b), max(0, min(255, int(a * scale))))

def ell(cx, cy, rx, ry, fill, outline=None, width=1):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill, outline=outline, width=width)

def soft_ell(cx, cy, rx, ry, fill, soft):
    """柔边近似：核心 + 几圈递减透明度（图片控件没有真渐变，靠这个看个大概）"""
    if not soft:
        ell(cx, cy, rx, ry, fill); return
    steps = 5
    for i in range(steps, 0, -1):
        k = 1.0 + (soft / 100.0) * (i / steps)
        ell(cx, cy, rx * k, ry * k, (fill[0], fill[1], fill[2], int(fill[3] * 0.16)))
    ell(cx, cy, rx, ry, fill)

images = [c for c in data['controls'] if c['kind'] == 'image' and c['visible'] and c['active'] and c['w'] > 0.5]
texts  = [c for c in data['controls'] if c['kind'] == 'textbox' and c['visible'] and c['active'] and (c.get('text') or c.get('bgColor', [0,0,0,0])[3] > 0)]

for c in images:
    col = rgba(c.get('color') or [255, 255, 255, 255])
    x, y, w, h, rot, soft = c['x'], c['y'], c['w'], c['h'], c.get('rot') or 0, c.get('soft') or 0
    fill = c.get('fill')
    # 径向填充（冷却环）：画成弧，起点在正上方（Enum.ImageFillRadialType.Top）
    if fill and fill['type'].startswith('Radial'):
        amount = max(0.0, min(1.0, fill.get('amount', 1)))
        r = max(w, h) / 2
        lw = max(3, r * 0.18)
        d.arc([x - r, y - r, x + r, y + r], -90, -90 + 360 * amount, fill=col, width=int(lw))
        continue
    if rot:
        # 有旋转 = 一根"棒"（瞄准线 / 连线 / 轨道路面）：按中心旋转画成多边形
        # ★ 符号：控件空间的 y 向上、图片的 y 向下，所以要取反
        ang = math.radians(-rot)
        ca, sa = math.cos(ang), math.sin(ang)
        pts = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            px, py = sx * w / 2, sy * h / 2
            pts.append((x + px * ca - py * sa, y + px * sa + py * ca))
        d.polygon(pts, fill=col)
        continue
    if (col[0], col[1], col[2]) == (255, 255, 255) and col[3] == 255:
        # 纯白 = 碱基丢了（模拟器 32 位整数的假象之一）—— 画成空心 + 问号
        ell(x, y, w/2, h/2, None, outline=(150, 150, 150), width=2)
        fq = load_font(max(10, h * 0.6))
        qw = d.textlength('?', font=fq)
        d.text((x - qw/2, y - h * 0.42), '?', font=fq, fill=(150, 150, 150))
    else:
        soft_ell(x, y, w/2, h/2, col, soft)

for c in texts:
    size = c.get('fontSize') or 24
    f = load_font(size)
    x, y, w, h = c['x'], c['y'], c['w'], c['h']
    bg = c.get('bgColor') or [0, 0, 0, 0]
    if bg[3] > 0:
        d.rectangle([x - w/2, y - h/2, x + w/2, y + h/2], fill=rgba(bg))
    lines = (c.get('text') or '').split('\n')
    lh = size * 1.35
    top = y - lh * len(lines) / 2
    for i, line in enumerate(lines):
        lw = d.textlength(line, font=f)
        align = str(c.get('align') or 'Left')
        if 'Right' in align:    lx = x + w/2 - lw
        elif 'Middle' in align: lx = x - lw/2
        else:                   lx = x - w/2
        d.text((lx, top + i * lh), line, font=f, fill=rgba(c.get('fontColor') or [240, 240, 240, 255]))

d.text((8, 6), os.path.basename(data.get('script', '?')) + '  第 %s 关  %s 帧%s' % (
    data.get('level'), data.get('frames'), '（带机器人点击）' if data.get('play') else ''), font=load_font(18), fill=(120, 200, 140))
if data.get('intBits') == 32:
    d.text((8, H - 26), '⚠ 模拟器（Fengari）整数是 32 位 → rng 会取到 nil：带 ? 的空心白球是假象，不是游戏 bug',
           font=load_font(20), fill=(230, 160, 90))
img.convert('RGB').save(dst)
print(dst)
`;

const { cmd, prefix } = findPython();
const out = execFileSync(cmd, [...prefix, '-c', py, jsonPath, pngPath], { encoding: 'utf8' }).trim();
const all = JSON.parse(fs.readFileSync(jsonPath, 'utf8')).controls;
const vis = all.filter((c) => c.kind === 'image' && c.visible && c.active && c.w > 0.5).length;
console.log('试玩截图：' + path.relative(process.cwd(), out) + '（可见图片控件 ' + vis + ' 个 / 控件总数 ' + all.length + '）');
