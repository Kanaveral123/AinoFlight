"""Static text-fit audit of the flight HUD and panels (no engine needed).

Every literal string that ends up in a fixed slot is measured like the game measures
text (half-width units x font size / 2; CJK and full-width symbols count two) and
compared with the room that slot has before it would run into its neighbour.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scene/zzz_flight_draw.ss').read_text(encoding='utf8')


def half_width(text: str) -> int:
    return sum(1 if ord(c) < 128 or unicodedata.east_asian_width(c) in 'HNa' else 2 for c in text)


def literals(pattern: str):
    return [m for m in re.findall(pattern, SOURCE)]


KEYS = re.search(r'\$s = "(↑↓[^"]*)"', SOURCE)[1]
PAD_KEYS = re.search(r'\$s = "(左摇杆[^"]*)"', SOURCE)[1]
# The key summary shows keyboard or gamepad labels; tips must clear the wider one.
KEY_LEFT = 1888 - max(half_width(KEYS), half_width(PAD_KEYS)) * 18 // 2
checks = []
# Panel rows: body at x 474, 27 px, must end before Aino's portrait (~x 1235).
for label, body in literals(r'\$\$fl_d_row\(\d, "([^"]*)", "([^"]+)"\)'):
    checks.append(('panel row ' + label, body, 474 + half_width(body) * 27 // 2, 1235))
# Panel subtitles (x 360, 28 px) and footers (x 360, 22 px), same limit.
for text in literals(r'child\[4\]\.set_string\("([^"]+)"\)'):
    checks.append(('panel subtitle', text, 360 + half_width(text) * 28 // 2, 1235))
for text in literals(r'child\[12\]\.set_string\("([^"]+)"\)'):
    checks.append(('panel footer', text, 360 + half_width(text) * 22 // 2, 1235))
# Bottom-bar leg tips (x 32, 22 px) must end before the key summary.
for text in literals(r'\$tip = "([^"]+)"'):
    checks.append(('tip', text, 32 + half_width(text) * 22 // 2, KEY_LEFT - 24))
# Gate / touchdown toast (26 px) inside its 660 px box; widest touchdown text assumed.
widest_touch = '中线 偏左 29.9 m · 瞄准点 偏晚 680.0 m'
checks.append(('touch toast', widest_touch, 960 + half_width(widest_touch) * 26 // 4, 630 + 660 - 12))
checks.append(('gate toast', '第 19 框 · 漏框', 960 + half_width('第 19 框 · 漏框') * 26 // 4, 630 + 660 - 12))
# Top bar: the left sub line must stay clear of the centred counts.
counts = '通过 19 · 漏框 19'
left_sub = '引导框完成 · 对准橙色瞄准点'
checks.append(('top bar left', left_sub, 34 + half_width(left_sub) * 21 // 2, 960 - half_width(counts) * 32 // 4 - 24))

report = []
for name, text, right, limit in checks:
    report.append({'slot': name, 'text': text, 'right_px': right, 'limit_px': limit, 'margin_px': limit - right})
report.sort(key=lambda r: r['margin_px'])
(ROOT / 'build/text-layout-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
for r in report[:8]:
    print(f"{r['margin_px']:5d} px  {r['slot']:16s} {r['text']}")
over = [r for r in report if r['margin_px'] < 0]
assert not over, f'{len(over)} text slots overflow'
assert report[0]['margin_px'] >= 30, 'a text slot is closer than 30 px to its neighbour'
print(f'PASS: {len(report)} text slots fit, tightest margin {report[0]["margin_px"]} px')
