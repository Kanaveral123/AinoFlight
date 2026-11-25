"""Temporarily arm a normal-engine save at the flight preface; restore with --off."""
from pathlib import Path
import argparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--off', action='store_true')
args = parser.parse_args()
# Untouched copy of the game's own _start.ss, kept beside the scene source.
original = (root / 'original/_start.ss').read_bytes()
target = root / 'scene/_start.ss'
if args.off:
    target.write_bytes(original)
    print('Restored original title/start flow.')
else:
    text = original.decode('cp932')
    assert text.count('#z00') == 1
    text = text.replace('#z00', '''#z00
// Test build only: create a real save through the original scenario flow.
$$init_scene
$$menu_control_disabled
<CHAPTER_PLAY> = 0
<EXTRA_MODE> = 0
$fl_test_entry = 1
jump("001_シナリオフロー", 157)
''', 1)
    target.write_text(text, encoding='utf8', newline='\r\n')
    print('Armed native save generation at ordinary slot 900.')
