"""Cut ground landmarks out of the game's own background paintings.

Each landmark is extracted from an original .g00 with SSSU, cropped to an
outline polygon, has the painted sky removed by edge-aware region growing from
outside that outline, and is written back as a new single-cut type2 .g00
(straight alpha, as the game's own cut-in sprites). Original files are only
read; outputs use new FL_lm_* names.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
GAME_G00 = ROOT.parent / 'game' / 'g00'  # replaced by --game
WORK = ROOT / 'build/landmarks'

# source: g00 name; tiles: 2x2 cut_xy layout; poly: keep outline in source px;
# height: output sprite height in px. clouds=False removes only blue sky (for
# pale walls and blue tarps); protect: polygons sky removal never enters;
# protect_shift: also protect the outline itself moved down by that many px.
LANDMARKS = {
    'FL_lm_windmill': dict(source='BG707_07_cut_xy', tiles=True, height=480, poly=[
        (650, 300), (1150, 300), (1235, 560), (1595, 1790), (1512, 1800), (1512, 2186),
        (300, 2186), (300, 1800), (265, 1790), (640, 560)]),
    'FL_lm_farm': dict(source='BG021_01', height=360, poly=[
        (292, 818), (286, 520), (350, 360), (486, 62), (704, 156), (1040, 274), (1376, 350),
        (1502, 396), (1535, 478), (1640, 482), (1642, 352), (1795, 160), (1945, 350),
        (1966, 400), (1936, 420), (1936, 742), (1120, 760), (790, 814)],
        protect=[[(1745, 178), (1800, 225), (1880, 270), (1925, 330), (1932, 376), (1594, 376),
                  (1602, 330), (1650, 265), (1700, 215)]]),
    'FL_lm_observatory': dict(source='BG301_01', height=360, clouds=False, protect_shift=10, poly=[
        (300, 842), (300, 490), (378, 452), (834, 248), (841, 170), (880, 105), (960, 70),
        (1060, 66), (1150, 95), (1205, 170), (1207, 285), (1750, 442), (1750, 842)]),
    'FL_lm_hangar': dict(source='BG202_01', height=300, poly=[
        (506, 142), (1150, 0), (2048, 0), (2048, 790), (1500, 784), (700, 772), (506, 768)]),
    'FL_lm_trailer': dict(source='BG101_01', height=200, poly=[
        (325, 268), (900, 148), (1380, 128), (1565, 198), (1705, 378), (1722, 560),
        (1700, 640), (1728, 742), (1700, 776), (700, 780), (325, 706)]),
    'FL_lm_school': dict(source='BG016_01', height=300, clouds=False, protect_shift=12, poly=[
        (392, 712), (392, 488), (480, 362), (560, 418), (697, 405), (922, 384), (998, 296),
        (1035, 326), (1605, 258), (1694, 162), (1767, 214), (2048, 170), (2048, 780),
        (1500, 784), (1000, 742), (700, 724)]),
    'FL_lm_shops': dict(source='BG206_01', height=320, poly=[
        (532, 692), (532, 112), (600, 60), (1170, 88), (1185, 70), (1690, 72), (1712, 270),
        (1712, 692)]),
    'FL_lm_sign': dict(source='BG506_01', height=320, poly=[
        (1638, 250), (1636, 150), (1700, 70), (1780, 62), (1846, 120), (1856, 236),
        (1800, 268), (1800, 640), (1796, 708), (1676, 712), (1672, 640), (1668, 270)]),
    'FL_lm_trees': dict(source='BG702_01', height=180, poly=[
        (40, 768), (40, 560), (100, 480), (250, 466), (420, 478), (560, 520), (600, 600),
        (590, 700), (560, 752)]),
}


def run(*args):
    # SSSU runs from this same Python (it must have siglus-ssu installed), as siglus-ssu.cmd does.
    subprocess.run([sys.executable, '-I', '-X', 'utf8', '-m', 'siglus_ssu', *map(str, args)],
                   check=True, capture_output=True)


def load_source(name: str, tiles: bool) -> Image.Image:
    out = WORK / 'src'
    out.mkdir(parents=True, exist_ok=True)
    if not list(out.glob(name + '*.png')):
        run('-g', '--x', GAME_G00 / (name + '.g00'), out)
    if not tiles:
        return Image.open(out / (name + '.png')).convert('RGB')
    # cut_xy layout: cut0 top-left, cut1 bottom-left, cut2 top-right, cut3 bottom-right.
    parts = [Image.open(out / f'{name}_cut{i:03d}.png').convert('RGB') for i in range(4)]
    w, h = parts[0].size
    canvas = Image.new('RGB', (w * 2, h * 2))
    for part, pos in zip(parts, [(0, 0), (0, h), (w, 0), (w, h)]):
        canvas.paste(part, pos)
    return canvas


def sky_like(p, clouds: bool) -> bool:
    r, g, b = p
    if b > r + 22 and b >= g - 4:
        return True
    return clouds and min(p) > 188 and max(p) - min(p) < 46 and b >= r - 6


def remove_sky(rgb: Image.Image, keep: Image.Image, protect: Image.Image, clouds: bool) -> Image.Image:
    """Grow from every outside pixel into sky-like pixels without crossing painted edges."""
    w, h = rgb.size
    px = rgb.load()
    kp = keep.load()
    pp = protect.load()
    alpha = keep.copy()
    ap = alpha.load()
    seen = bytearray(w * h)
    queue = deque()
    for y in range(h):
        for x in range(w):
            if kp[x, y] == 0:
                seen[y * w + x] = 1
                queue.append((x, y))
            elif pp[x, y]:
                seen[y * w + x] = 1
    while queue:
        x, y = queue.popleft()
        c = px[x, y]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                n = px[nx, ny]
                if sky_like(n, clouds) and max(abs(n[0] - c[0]), abs(n[1] - c[1]), abs(n[2] - c[2])) < 16:
                    seen[ny * w + nx] = 1
                    ap[nx, ny] = 0
                    queue.append((nx, ny))
    return alpha


def bleed(rgb: Image.Image, alpha: Image.Image) -> Image.Image:
    """Give transparent texels nearby opaque colours so filtering never shows sky fringes."""
    base = rgb.copy()
    known = alpha.point(lambda a: 255 if a > 8 else 0)
    for _ in range(6):
        grown = base.filter(ImageFilter.MaxFilter(3))
        grown_known = known.filter(ImageFilter.MaxFilter(3))
        base = Image.composite(base, grown, known)
        known = grown_known
    return base


def build(name: str, spec: dict, preview: list):
    src = load_source(spec['source'], spec.get('tiles', False))
    xs = [p[0] for p in spec['poly']]
    ys = [p[1] for p in spec['poly']]
    box = (max(0, min(xs)), max(0, min(ys)), min(src.width, max(xs) + 1), min(src.height, max(ys) + 1))
    crop = src.crop(box)
    scale = spec['height'] / crop.height
    size = (max(1, round(crop.width * scale)), spec['height'])
    small = crop.resize(size, Image.LANCZOS)
    def local(poly, dy=0):
        return [((x - box[0]) * scale, (y + dy - box[1]) * scale) for x, y in poly]
    keep = Image.new('L', size, 0)
    ImageDraw.Draw(keep).polygon(local(spec['poly']), fill=255)
    protect = Image.new('L', size, 0)
    for poly in spec.get('protect', []):
        ImageDraw.Draw(protect).polygon(local(poly), fill=255)
    if 'protect_shift' in spec:
        ImageDraw.Draw(protect).polygon(local(spec['poly'], spec['protect_shift']), fill=255)
    alpha = remove_sky(small, keep, protect, spec.get('clouds', True))
    # Soften the cut by one texel; keep fully opaque interiors untouched.
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    rgb = bleed(small, alpha)
    sprite = rgb.copy()
    sprite.putalpha(alpha)
    bbox = alpha.point(lambda a: 255 if a > 4 else 0).getbbox()
    sprite = sprite.crop(bbox)
    png = WORK / (name + '.png')
    sprite.save(png)
    layout = {'type': 2, 'canvas': {'width': sprite.width, 'height': sprite.height},
              'cuts': [{'index': 0, 'source': png.name,
                        'source_rect': {'x': 0, 'y': 0, 'w': sprite.width, 'h': sprite.height},
                        'canvas_rect': {'x0': 0, 'y0': 0, 'x1': sprite.width - 1, 'y1': sprite.height - 1}}],
              'default_center': {'x': 0, 'y': 0}}
    layout_path = WORK / (name + '.type2.json')
    layout_path.write_text(json.dumps(layout, indent=2), encoding='utf8')
    g00 = WORK / (name + '.g00')
    run('-g', '--c', '--type', '2', layout_path, g00)
    preview.append((name, sprite))
    return {'name': name, 'source': spec['source'] + '.g00', 'width': sprite.width, 'height': sprite.height,
            'source_sha256': hashlib.sha256((GAME_G00 / (spec['source'] + '.g00')).read_bytes()).hexdigest(),
            'sha256': hashlib.sha256(g00.read_bytes()).hexdigest()}


def contact_sheet(preview):
    w = sum(s.width for _, s in preview) + 20 * (len(preview) + 1)
    h = max(s.height for _, s in preview) + 40
    sheet = Image.new('RGBA', (w, h), (255, 0, 255, 255))
    draw = ImageDraw.Draw(sheet)
    x = 20
    for name, sprite in preview:
        sheet.alpha_composite(sprite, (x, 30))
        draw.text((x, 6), name, fill=(0, 0, 0, 255))
        x += sprite.width + 20
    sheet.convert('RGB').save(ROOT / 'build/landmarks-preview.png')


def main():
    parser = argparse.ArgumentParser()
    global GAME_G00
    parser.add_argument('--game', type=Path, default=ROOT.parent / 'game',
                        help='game folder holding the original g00/ (default: ../game)')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/g00')
    parser.add_argument('--only', nargs='*')
    args = parser.parse_args()
    GAME_G00 = args.game / 'g00'
    WORK.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    preview, report = [], []
    for name, spec in LANDMARKS.items():
        if args.only and name not in args.only:
            continue
        info = build(name, spec, preview)
        shutil.copyfile(WORK / (name + '.g00'), args.output / (name + '.g00'))
        report.append(info)
    contact_sheet(preview)
    (ROOT / 'build/landmark-assets.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps([(r['name'], r['width'], r['height']) for r in report]))


if __name__ == '__main__':
    main()
