"""Run the shipped SS sound commands against a recording native-API shim.

The test translates SS syntax only; audio branching, first-contact priority,
throttle mixing and speech timing all execute from zzz_flight_audio.ss itself.
"""
from __future__ import annotations
import ast
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


class Channel:
    def __init__(self, name, events):
        self.name = name
        self.events = events
        self.volume = 255

    def play(self, *args, **kwargs):
        self.events.append((self.name, 'play', args, kwargs))

    def stop(self, *args): self.events.append((self.name, 'stop', args, {}))
    def pause(self, *args): self.events.append((self.name, 'pause', args, {}))
    def resume(self, *args): self.events.append((self.name, 'resume', args, {}))
    def set_volume(self, value, *args):
        self.volume = value
        self.events.append((self.name, 'volume', (value, *args), {}))


class IntegerDivision(ast.NodeTransformer):
    def visit_BinOp(self, node):
        self.generic_visit(node)
        if isinstance(node.op, ast.Div):
            return ast.copy_location(ast.Call(func=ast.Name(id='idiv', ctx=ast.Load()),
                                              args=[node.left, node.right], keywords=[]), node)
        return node


def load_audio():
    raw = (ROOT / 'scene/zzz_flight_audio.ss').read_text(encoding='utf8')
    private_names = set(re.findall(r'#property\s+\$(\w+)', raw))
    source = raw[raw.index('\ncommand $$fl_speech') + 1:]
    source = re.sub(r'//[^\n]*', '', source)
    source = re.sub(r'@bgm\(bgm27,\s*(\d+)\)', r'self.bgm.play("bgm27", fade=\1)', source)
    source = re.sub(r'@bgm_stop\((\d+)\)', r'self.bgm.stop(\1)', source)
    source = source.replace('{', '\n{\n').replace('}', '\n}\n')
    source = re.sub(r'\belse\b', '\nelse\n', source)
    source = re.sub(r'(case\(\d+\))', r'\1\n', source)
    out, stack = [], []
    indent = 0
    pending_switch = None
    first_case = True

    def expr(s):
        s = s.strip().replace('&&', ' and ').replace('||', ' or ')
        s = re.sub(r'\$\$(\w+)', r'self.\1', s)
        s = re.sub(r'\$(fl_\w+)', r'self.\1', s)
        s = re.sub(r'\$(\w+)', r'\1', s)
        s = s.replace('pcmch[', 'self.channels[').replace('bgm.', 'self.bgm.')
        s = s.replace('self.self.', 'self.').replace('math.abs(', 'abs(')
        return s

    for raw_line in source.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line == '{':
            if pending_switch is not None:
                stack.append(('switch', pending_switch, False))
                pending_switch = None
            else:
                stack.append(('block',))
                indent += 1
            continue
        if line == '}':
            kind = stack.pop()
            if kind[0] == 'block' or kind[2]: indent -= 1
            continue
        if line.startswith('command '):
            m = re.match(r'command\s+\$\$(\w+)(?:\((.*?)\))?$', line)
            assert m, line
            name, args = m.groups()
            names = re.findall(r'\$(\w+)', args or '')
            line = f'def {name}(self' + ''.join(', ' + x for x in names) + '):'
        elif line.startswith('property '):
            continue
        elif line.startswith('switch('):
            assert line.endswith(')'), line
            pending_switch = expr(line[7:-1])
            continue
        elif line.startswith('case('):
            m = re.match(r'case\((\d+)\)$', line)
            assert m and stack[-1][0] == 'switch', line
            _, key, active = stack[-1]
            if active: indent -= 1
            out.append('    ' * indent + ('elif' if active else 'if') + f' {key} == {m[1]}:')
            indent += 1
            stack[-1] = ('switch', key, True)
            continue
        elif line.startswith('elseif('):
            assert line.endswith(')'), line
            line = 'elif ' + expr(line[7:-1]) + ':'
        elif line.startswith('if('):
            assert line.endswith(')'), line
            line = 'if ' + expr(line[3:-1]) + ':'
        elif line == 'else':
            line = 'else:'
        elif line == 'return':
            line = 'return'
        else:
            line = expr(line)
            if re.fullmatch(r'self\.fl_\w+', line): line += '()'
        out.append('    ' * indent + line)
    translated = '\n'.join(out)
    tree = IntegerDivision().visit(ast.parse(translated))
    ast.fix_missing_locations(tree)
    ns = {'idiv': lambda a, b: int(a / b)}
    exec(compile(tree, 'zzz_flight_audio.ss', 'exec'), ns)
    cls = type('ActualSSAudio', (), {k: v for k, v in ns.items() if k.startswith('fl_')})
    audio = cls()
    audio.events = []
    audio.channels = {i: Channel(i, audio.events) for i in range(8)}
    audio.bgm = Channel('bgm', audio.events)
    for name in private_names | set(re.findall(r'(?<!\$)\$(fl_\w+)', raw)):
        setattr(audio, name, 0)
    audio.fl_clamp = lambda x, lo, hi: min(hi, max(lo, x))
    audio.fl_state = 1
    return audio


def events(audio, channel=None, action=None):
    return [e for e in audio.events if (channel is None or e[0] == channel)
            and (action is None or e[1] == action)]


def run_tests():
    a = load_audio()
    a.fl_sound_reset()
    assert events(a, 'bgm', 'play')[0][2] == ('bgm27',)
    assert a.fl_speech_id == 1 and a.fl_speech_until == 1678
    assert [a.channels[i].volume for i in (2, 3, 5)] == [72, 0, 0]
    mix = []
    for throttle in (0, 250, 500, 750, 1000):
        a.fl_throttle = throttle
        a.fl_engine_mix()
        levels = [a.channels[i].volume for i in (2, 3, 5)]
        mix.append({'throttle': throttle, 'low_mid_high_volume': levels})
        assert abs(sum(levels) - (72 + throttle * 178 // 1000)) <= 1
    assert mix[-1]['low_mid_high_volume'] == [0, 0, 250]
    a.fl_sound_reset()
    assert len(events(a, 'bgm', 'play')) == 1, 'Retry restarted the music'
    a.events.clear()
    a.fl_speed = 1800
    a.fl_elapsed_ms = 2300
    a.fl_sound_step()
    assert len(events(a, 4, 'play')) == 1
    assert events(a, 6, 'play')[-1][2] == ('SE_elec_plane_propeller_start',)
    for _ in range(5): a.fl_sound_step()
    assert len(events(a, 4, 'play')) == 1 and len(events(a, 6, 'play')) == 1
    a.fl_airborne, a.fl_phase, a.fl_alt = 1, 2, 5000
    a.fl_sound_step()
    assert events(a, 6, 'play')[-1][2] == ('SE_elec_plane_takeoff',)
    assert a.fl_speech_id == 2 and events(a, 4, 'stop')
    a.fl_sound_step()
    assert a.fl_speech_id == 3
    a.fl_phase = 5
    a.fl_sound_step()
    assert a.fl_speech_id == 4
    a.fl_alt, a.fl_vspeed = 500, -100
    a.fl_sound_step()
    assert a.fl_speech_id == 5
    serial = a.fl_speech_serial
    a.fl_sound_step()
    assert a.fl_speech_serial == serial
    a.fl_sound_pause()
    a.fl_sound_pause()
    assert len(events(a, 'bgm', 'pause')) == 1
    a.fl_sound_step()
    assert a.fl_speech_serial == serial
    a.fl_sound_resume()
    a.fl_sound_resume()
    assert len(events(a, 'bgm', 'resume')) == 1
    a.events.clear()
    a.fl_touched, a.fl_touch_fpm = 1, -188
    a.fl_state = 1
    a.fl_sound_step()
    assert events(a, 6, 'play') == [(6, 'play', ('SE_plane_land',), {})]
    assert events(a, 4, 'play'), 'Ground roll did not resume after contact'
    for _ in range(5): a.fl_sound_step()
    assert len(events(a, 6, 'play')) == 1, 'Contact sound repeated'
    # Wheel brakes squeal once while B is held on the roll and stop on release.
    a.fl_speed, a.fl_in_brake = 2000, 1
    for _ in range(5): a.fl_sound_step()
    assert events(a, 1, 'play') == [(1, 'play', ('SE_bike_brake',), {})]
    a.fl_in_brake = 0
    a.fl_sound_step()
    a.fl_sound_step()
    assert len(events(a, 1, 'stop')) == 1
    a.fl_state = 3
    a.fl_sound_step()
    counts = {ch: len(events(a, ch, 'stop')) for ch in (2, 3, 4, 5)}
    for _ in range(5): a.fl_sound_step()
    assert counts == {ch: len(events(a, ch, 'stop')) for ch in (2, 3, 4, 5)}
    a.fl_sound_clear()
    assert a.fl_speech_id == 0 and len(events(a, 'bgm', 'stop')) == 1

    # Crash contact and startup are deliberately eligible on the same frame.
    b = load_audio()
    b.fl_sound_reset()
    b.events.clear()
    b.fl_elapsed_ms, b.fl_touched, b.fl_touch_fpm, b.fl_state = 2301, 1, -1200, 4
    b.fl_sound_step()
    assert events(b, 6, 'play') == [(6, 'play', ('SE_plane_land_rattle',), {})]
    assert not events(b, 6, 'stop'), 'End-state fade cancelled the impact'
    b.fl_sound_step()
    assert len(events(b, 6, 'play')) == 1

    # A skipped exact sidewind phase still speaks the turn cue once.
    c = load_audio()
    c.fl_sound_reset()
    c.fl_airborne, c.fl_phase, c.fl_alt = 1, 3, 15000
    c.fl_sound_step()
    c.fl_sound_step()
    assert c.fl_speech_id == 3
    c.fl_sound_pause()
    c.fl_sound_reset()
    assert not c.fl_a_paused and len(events(c, 'bgm', 'play')) == 1
    assert events(c, 'bgm', 'resume'), 'Paused retry failed to resume music'

    report = {'status': 'PASS', 'source': 'src/zzz_flight_audio.ss',
              'bgm': 'bgm27', 'mix_samples': mix,
              'checks': ['original sightseeing BGM', 'continuous volume/pitch-layer mixing',
                         'ground roll follows speed/air-ground transition',
                         'one-shot first-contact priority including crash',
                         'finished fades are not restarted every frame',
                         'speech/subtitle event pairing and actual duration',
                         'pause/resume idempotence and paused retry',
                         'stage skipping does not lose turn cue']}
    (ROOT / 'build/audio-state-report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    run_tests()
