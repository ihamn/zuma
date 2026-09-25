// sim-render.mjs —— 把试玩台导出的控件树（sim-play.mjs --json=…）画成 PNG，好"看见"画面。
//
// 为什么值得有：我看不到真机屏幕，用户也未必每次都能截图；而"球到底在不在轨道上、
// HUD 排得对不对、颜色有没有反色"这些事，一张图比一百行日志快。
//
// 它画的是**沙箱里真实控件树**（位置/尺寸/颜色/文字都来自运行时），不是我们自己的模型 ——
// 所以它同时是一次几何验收：球如果没落在轨道上，图上一眼就能看出来。
//
// ★ 它画不了：控件模板里的**图片素材**（球面的碱基字母是图片，不是文字）。
//   所以球只画成一个圆，颜色是真的、字母要等真机。
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
const pick = (arg, dflt, ext) => {
  const p = path.resolve(arg || dflt);
  if (fs.existsSync(p)) return p;
  const q = path.resolve(ROOT, arg || dflt);
  return fs.existsSync(q) || !arg ? q : p;
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
import json, sys, os
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding='utf-8'))
W, H = data['canvas']['w'], data['canvas']['h']
img = Image.new('RGB', (W, H), (16, 20, 24))
d = ImageDraw.Draw(img)

def load_font(size, bold=False):
    # 中文必须用系统里的 CJK 字体，Pillow 自带字体画不了汉字（会变成方框）
    for name in (('msyhbd.ttc' if bold else 'msyh.ttc'), 'msyh.ttc', 'simhei.ttf', 'simsun.ttc'):
        p = os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'Fonts', name)
        if os.path.exists(p):
            try: return ImageFont.truetype(p, max(8, int(size)))
            except Exception: pass
    return ImageFont.load_default()

# 与游戏里的 Z 层级大致对齐：先画"球"，再画文字
images = [c for c in data['controls'] if c['kind'] == 'image' and c['visible'] and c['active'] and c['w'] > 1]
texts  = [c for c in data['controls'] if c['kind'] == 'textbox' and c['visible'] and c['active'] and (c.get('text') or '')]

for c in images:
    r, g, b, a = (c.get('color') or [255, 255, 255, 255])
    x, y, w, h = c['x'], c['y'], c['w'], c['h']
    box = [x - w/2, y - h/2, x + w/2, y + h/2]
    if (r, g, b) == (255, 255, 255):
        # 白色 = 碱基丢了（模拟器 32 位整数的假象，见 sim-play.mjs 顶部）——
        # 画成空心 + 问号，免得被当成"本来就该是白球"
        d.ellipse(box, outline=(150, 150, 150), width=2)
        fq = load_font(max(10, h * 0.6))
        qw = d.textlength('?', font=fq)
        d.text((x - qw/2, y - h * 0.42), '?', font=fq, fill=(150, 150, 150))
    else:
        d.ellipse(box, fill=(r, g, b), outline=(0, 0, 0), width=1)

for c in texts:
    size = c.get('fontSize') or 24
    f = load_font(size)
    lines = c['text'].split('\n')
    lh = size * 1.35
    total = lh * len(lines)
    x, y, w, h = c['x'], c['y'], c['w'], c['h']
    top = y - total / 2
    for i, line in enumerate(lines):
        lw = d.textlength(line, font=f)
        align = str(c.get('align') or 'Left')
        if 'Right' in align:   lx = x + w/2 - lw
        elif 'Middle' in align: lx = x - lw/2
        else:                  lx = x - w/2
        d.text((lx, top + i * lh), line, font=f, fill=(240, 240, 240))

d.text((8, 6), os.path.basename(data.get('script', '?')) + '  第 %s 关  %s 帧%s' % (
    data.get('level'), data.get('frames'), '（带机器人点击）' if data.get('play') else ''), font=load_font(18), fill=(120, 200, 140))
if data.get('intBits') == 32:
    # 把"这是模拟器假象"直接写进图里，免得以后有人盯着白球查半天
    d.text((8, H - 26), '⚠ 模拟器（Fengari）整数是 32 位 → rng 取到 nil：带 ? 的空心白球是假象，不是游戏 bug',
           font=load_font(20), fill=(230, 160, 90))
img.save(dst)
print(dst)
`;

const { cmd, prefix } = findPython();
const out = execFileSync(cmd, [...prefix, '-c', py, jsonPath, pngPath], { encoding: 'utf8' }).trim();
const n = JSON.parse(fs.readFileSync(jsonPath, 'utf8')).controls
  .filter((c) => c.kind === 'image' && c.visible && c.active && c.w > 1).length;
console.log('试玩截图：' + path.relative(process.cwd(), out) + '（' + n + ' 个球）');
