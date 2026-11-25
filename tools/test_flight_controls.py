"""Execute the shipped SS menu and input-isolation commands with native API stubs.

The menu state machine and exit-release loop are translated from zzz_flight.ss;
there is no second implementation of the intended menu behavior in this test.
"""
from __future__ import annotations

import ast
from collections import defaultdict
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / 'scene/zzz_flight.ss'


class IntList(list):
    def resize(self, count):
        self[:] = (self + [0] * count)[:count]


class Key:
    def __init__(self):
        self.on_down = False
        self.is_down = False


class Keys(defaultdict):
    def __init__(self):
        super().__init__(Key)

    def __getitem__(self, code):
        return super().__getitem__(ord(code) if isinstance(code, str) else code)


class Mouse:
    def __init__(self):
        self.left = Key()
        self.right = Key()


class NativeAPI:
    def __init__(self, owner, family, flags=None):
        self.owner = owner
        self.family = family
        self.flags = dict(flags or {})

    def __getattr__(self, name):
        if name.startswith('get_'):
            return self.flags.get(name[4:], 0)

        def call(*args):
            env = self.owner
            env.events.append((self.family + '.' + name, args, env.frame, env.held()))
            if name.startswith('set_'):
                field = name[4:]
                if args:
                    self.flags[field] = args[0]
                elif field.endswith('_disable'):
                    self.flags[field] = 1
                    self.flags[field + '_flag'] = 1
                elif field.endswith('_enable'):
                    self.flags[field[:-7] + '_disable'] = 0
                    self.flags[field[:-7] + '_disable_flag'] = 0
                else:
                    self.flags[field] = 1
            if self.family == 'input' and name == 'next':
                env.frame += 1
                if env.release_at is not None and env.frame >= env.release_at:
                    for key in env.key.values():
                        key.is_down = False
                    env.pad_held = False
                    env.mouse.left.is_down = False
                    env.mouse.right.is_down = False
        return call


class Environment:
    def __init__(self):
        self.key = Keys()
        self.mouse = Mouse()
        self.pad_held = False
        self.events = []
        self.frame = 0
        self.release_at = None
        self.script = NativeAPI(self, 'script', {
            'skip_disable_flag': 1, 'ctrl_skip_disable_flag': 0,
            'mwnd_disp_off_flag': 0, 'allow_joypad_mode_onoff': 1,
        })
        self.syscom = NativeAPI(self, 'syscom', {
            'read_skip_enable_flag': 1, 'auto_skip_enable_flag': 0,
            'auto_mode_enable_flag': 1, 'msg_back_enable_flag': 0,
            'save_enable_flag': 1, 'load_enable_flag': 0,
            'hide_mwnd_enable_flag': 1, 'auto_mode_onoff_flag': 1,
            'read_skip_onoff_flag': 1, 'auto_skip_onoff_flag': 1,
        })
        self.input = NativeAPI(self, 'input')
        self.keyboard = NativeAPI(self, 'keyboard')

    def held(self):
        return (any(k.is_down for k in self.key.values()) or self.mouse.left.is_down
                or self.mouse.right.is_down or self.pad_held)

    def disp(self):
        self.events.append(('disp', (), self.frame, self.held()))


def command(source, name):
    match = re.search(r'command\s+\$\$' + re.escape(name) + r'\s*\n\{', source)
    assert match, f'Missing real SS command {name}'
    begin = match.start()
    brace = source.index('{', match.start())
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


def translate(source):
    source = re.sub(r'//[^\n]*', '', source)
    source = source.replace('{', '\n{\n').replace('}', '\n}\n')
    records = []
    pending = ''
    for raw in source.splitlines():
        line = raw.strip()
        if not line:
            continue
        if pending:
            pending += ' ' + line
            if pending.count('(') == pending.count(')'):
                records.append(pending)
                pending = ''
        elif line.startswith(('if(', 'elseif(', 'while(')) and line.count('(') != line.count(')'):
            pending = line
        else:
            records.append(line)
    assert not pending, pending

    def expression(value):
        value = value.strip().replace('&&', ' and ').replace('||', ' or ')
        value = re.sub(r'\$\$(\w+)', r'self.\1', value)
        return re.sub(r'\$(\w+)', r'self.\1', value)

    lines = []
    indent = 0
    for line in records:
        if line == '{':
            indent += 1
            continue
        if line == '}':
            indent -= 1
            continue
        if line.startswith('command '):
            match = re.fullmatch(r'command\s+\$\$(\w+)', line)
            assert match, line
            line = f'def {match[1]}(self):'
        elif line.startswith(('if(', 'elseif(', 'while(')):
            kind = 'elif' if line.startswith('elseif') else line.split('(')[0]
            body = line[line.index('(') + 1:-1]
            assert line.endswith(')'), line
            line = kind + ' ' + expression(body) + ':'
        elif line == 'else':
            line = 'else:'
        elif line.startswith('return'):
            line = expression(line)
        elif line == 'disp':
            line = 'engine.disp()'
        else:
            line = expression(line)
            if re.fullmatch(r'(?:self\.fl_\w+|script\.\w+|syscom\.\w+|input\.\w+|keyboard\.\w+)', line):
                line += '()'
        lines.append('    ' * indent + line)
    assert indent == 0, indent
    py_source = '\n'.join(lines)
    ast.parse(py_source)
    return py_source


def load_actual(env):
    source = SOURCE_PATH.read_text(encoding='utf8')
    fragments = [command(source, n) for n in ('fl_menu_step', 'fl_controls_enter', 'fl_controls_leave')]
    release_start = source.index('while( key[13].is_down')
    release_end = release_start + re.search(r'\ncommand\s+\$\$', source[release_start:]).start()
    # Include the actual key-release gate, clear calls, restore call and active reset.
    fragments.append('command $$fl_test_release\n{\n' + source[release_start:release_end] + '\n}')
    ns = {n: getattr(env, n) for n in ('key', 'mouse', 'script', 'syscom', 'input', 'keyboard')}
    ns['engine'] = env
    exec(compile(translate('\n'.join(fragments)), str(SOURCE_PATH), 'exec'), ns)
    methods = {n: v for n, v in ns.items() if n.startswith('fl_')}

    def sim_init(self):
        self.calls.append('sim_init')
        self.fl_state = 1
        self.fl_completed = 0
    methods['fl_sim_init'] = sim_init
    for name in ('fl_sound_reset', 'fl_sound_pause', 'fl_sound_resume', 'fl_draw_clear'):
        methods[name] = lambda self, name=name: self.calls.append(name)
    # The pad poll reads the engine's joypad; here it reports the environment's held pad buttons.
    methods['fl_pad_poll'] = lambda self: setattr(self, 'fl_pad_held', int(env.pad_held))
    native = type('ActualFlightControls', (), methods)()
    names = set(re.findall(r'(?<!\$)\$(fl_\w+)', source))
    for name in names:
        setattr(native, name, 0)
    native.fl_old_flags = IntList()
    native.calls = []
    return native, source


def menu(state, key=None, action=0, exit_from=2, pad=0):
    env = Environment()
    actual, _ = load_actual(env)
    actual.fl_state = state
    actual.fl_menu_action = action
    actual.fl_exit_from = exit_from
    # A gamepad press arrives as both $fl_pad_press and the panel action, as in the main loop.
    actual.fl_pad_press = pad
    if pad:
        actual.fl_menu_action = pad
    if key is not None:
        env.key[key].on_down = True
    actual.fl_menu_step()
    return actual


def tests():
    assertions = 0
    # During actual flight none of the story confirmation/fast-forward inputs exits.
    for key in (13, 32, 17, 9, 'Q', 'A', 'B', 37, 38, 39, 40):
        result = menu(1, key=key)
        assert (result.fl_state, result.fl_completed, result.calls) == (1, 0, [])
        assertions += 1
    for action in range(1, 6):
        assert menu(1, action=action).fl_state == 1
        assertions += 1
    for key in ('P', 27):
        result = menu(1, key=key)
        assert result.fl_state == 2 and result.calls == ['fl_sound_pause']
        assertions += 1

    # A pause cancellation opens a separate confirmation; it never returns to ADV.
    for key, action in ((27, 0), (None, 3)):
        result = menu(2, key=key, action=action)
        assert (result.fl_state, result.fl_exit_from, result.fl_completed) == (6, 2, 0)
        assertions += 1
    for origin in (0, 2, 4):
        for key, action in ((13, 0), (27, 0), (None, 5)):
            result = menu(6, key=key, action=action, exit_from=origin)
            assert result.fl_state == origin and result.fl_completed == 0
            assertions += 1
        result = menu(6, action=4, exit_from=origin)
        assert result.fl_state == 5 and result.fl_completed == 0
        assertions += 1
    for action in (0, 1, 2, 3):
        assert menu(6, action=action).fl_state == 6
        assertions += 1

    failed = menu(4, key=13)
    assert failed.fl_state == 1 and failed.fl_completed == 0
    assert failed.calls == ['sim_init', 'fl_sound_reset']
    assertions += 2
    success = menu(3, key=13)
    assert (success.fl_state, success.fl_completed) == (5, 1)
    assert menu(3, key=27).fl_state == 3
    assertions += 2
    assert menu(0, key=13).calls == ['fl_sound_reset']
    assert menu(2, key=13).calls == ['fl_sound_resume']
    assert menu(2, key='R').calls == ['sim_init', 'fl_sound_reset']
    assertions += 3

    # Gamepad: START / BACK pause the flight (action 6); a pad press in the same frame as a
    # key decides alone, so a key the engine might also report cannot add another action.
    paused = menu(1, pad=6)
    assert paused.fl_state == 2 and paused.calls == ['fl_sound_pause']
    assert menu(1, key=13, pad=0).fl_state == 1
    for state, key, pad, expect in ((0, 27, 1, 1), (2, 13, 3, 6), (2, 'P', 2, 1), (3, 'R', 1, 5),
                                    (4, 13, 3, 6), (6, 13, 4, 5), (6, None, 5, 2)):
        result = menu(state, key=key, pad=pad)
        assert result.fl_state == expect, (state, key, pad, result.fl_state)
        assertions += 1
    assert menu(2, key='P', pad=2).calls == ['sim_init', 'fl_sound_reset']
    assert menu(3, key='R', pad=1).fl_completed == 1
    assert menu(6, key=27, pad=4).fl_completed == 0
    assertions += 4

    # Execute the actual engine controls against mixed preexisting flags, then test
    # every flight key/button remaining held until three explicit input frames.
    held_inputs = [13, 32, 27, 17, 37, 38, 39, 40, 'Q', 'A', 'B', 'P', 'R', 'mouse_left', 'mouse_right', 'pad']
    for index, held in enumerate(held_inputs):
        env = Environment()
        # Each persisted flag sees both possible old values across these runs.
        if index % 2:
            for flags in (env.script.flags, env.syscom.flags):
                for field in tuple(flags):
                    flags[field] = 1 - flags[field]
        native, source = load_actual(env)
        script_before = dict(env.script.flags)
        syscom_before = dict(env.syscom.flags)
        native.fl_active = 1
        native.fl_controls_enter()
        assert env.script.flags['mouse_move_by_key_disable'] == 1
        assert env.script.flags['end_msg_by_key_disable'] == 1
        assert env.script.flags['allow_joypad_mode_onoff'] == 1
        assert env.syscom.flags['mwnd_btn_disable'] == 1
        assert env.syscom.flags['mwnd_btn_touch_disable'] == 1
        for field in ('auto_mode', 'auto_skip', 'read_skip', 'save', 'load', 'msg_back', 'hide_mwnd'):
            assert env.syscom.flags[field + '_enable_flag'] == 0
        if held == 'mouse_left':
            env.mouse.left.is_down = True
        elif held == 'mouse_right':
            env.mouse.right.is_down = True
        elif held == 'pad':
            env.pad_held = True
            native.fl_pad_held = 1
        else:
            env.key[held].is_down = True
        env.events.clear()
        env.release_at = 3
        native.fl_test_release()
        assert env.frame == 3 and native.fl_active == 0
        restore = [event for event in env.events if event[0] in (
            'script.set_end_msg_by_key_enable', 'script.set_mouse_move_by_key_enable',
            'syscom.set_mwnd_btn_enable', 'syscom.set_syscom_menu_enable',
        )]
        assert len(restore) == 4 and all(event[2] >= 3 and not event[3] for event in restore)
        for field, before in script_before.items():
            assert env.script.flags[field] == before, (field, before, env.script.flags[field])
        for field, before in syscom_before.items():
            if field.endswith('_enable_flag'):
                assert env.syscom.flags[field] == before, (field, before, env.syscom.flags[field])
            elif field.endswith('_onoff_flag'):
                assert env.syscom.flags[field] == 0
        assertions += 1

    # The 250ms transition latch is intentionally outside the isolated menu command.
    # Check its location/order against the actual main loop, rather than model it.
    assert 'input.decide' not in source and 'input.cancel' not in source
    assert '$fl_clock_now - $fl_menu_stamp >= 250' in source
    main_loop = source[:source.index('\ncommand $$fl_menu_step')]
    assert main_loop.index('while( key[13].is_down') < main_loop.rindex('$$fl_controls_leave')
    assert main_loop.rindex('$$fl_controls_leave') < main_loop.rindex('$fl_active = 0')
    assertions += 4
    print(json.dumps({'result': 'PASS', 'menu_cases_and_release_scenarios': assertions,
                      'source': str(SOURCE_PATH), 'held_key_release_cases': len(held_inputs),
                      'checks': ['actual SS menu execution', 'story-key isolation', 'explicit exit confirmation',
                                 'failure retry and success return', 'held-key drain before ADV restore',
                                 'mixed old flag round-trip', 'cursor and message-advance disable/enable',
                                 'gamepad pause and panel actions', 'pad press precedence over keys',
                                 'held pad buttons drained before ADV restore']},
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    tests()
