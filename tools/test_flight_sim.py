"""Execute the actual native SS simulation after a small syntax-only translation.

No parallel physics implementation is used: assertions exercise the shipped SS
commands, with Siglus integer division, trigonometry and intlist shims.
The closed-loop test pilot is a test fixture; it is absent from the game package.
"""
from __future__ import annotations
import ast
import csv
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def idiv(a, b):
    return int(a / b)


def imod(a, b):
    return a - idiv(a, b) * b


class MathShim:
    abs = staticmethod(abs)

    @staticmethod
    def sin(angle, radius):
        return int(math.sin(angle * math.pi / 1800) * radius)

    @staticmethod
    def cos(angle, radius):
        return int(math.cos(angle * math.pi / 1800) * radius)

    @staticmethod
    def distance(x1, y1, x2, y2):
        return int(math.hypot(x2 - x1, y2 - y1))

    @staticmethod
    def tan(angle, radius):
        return int(math.tan(angle * math.pi / 1800) * radius)


class IntList(list):
    def resize(self, size):
        self[:] = (self + [0] * size)[:size]


def i32(value):
    """Siglus integers are 32-bit; every intermediate result must fit."""
    if not -2**31 <= value < 2**31:
        raise OverflowError(value)
    return value


class IntArithmetic(ast.NodeTransformer):
    def visit_BinOp(self, node):
        self.generic_visit(node)
        if isinstance(node.op, (ast.Div, ast.Mod)):
            name = 'idiv' if isinstance(node.op, ast.Div) else 'imod'
            node = ast.copy_location(ast.Call(func=ast.Name(id=name, ctx=ast.Load()),
                                              args=[node.left, node.right], keywords=[]), node)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
            return node
        return ast.copy_location(ast.Call(func=ast.Name(id='i32', ctx=ast.Load()),
                                          args=[node], keywords=[]), node)


def load_ss(extra_source='', extra_inc=''):
    """Translate the shipped sim (plus any extra pure SS commands) and run it natively."""
    inc = (ROOT / 'scene/zzz_flight.inc').read_text(encoding='utf8') + '\n' + extra_inc
    global_names = set(re.findall(r'#property\s+\$(\w+)', inc))
    lists = set(re.findall(r'#property\s+\$(\w+)\s*:\s*intlist', inc))
    source = (ROOT / 'scene/zzz_flight_sim.ss').read_text(encoding='utf8') + '\n' + extra_source
    source = re.sub(r'//[^\n]*', '', source)
    source = re.sub(r'#z\d+\s*\nreturn', '', source)
    # Put braces/statements on separate lines; no string literals exist in sim.
    source = source.replace('{', '\n{\n').replace('}', '\n}\n')
    source = re.sub(r'\belse\b', '\nelse', source)
    out = []
    indent = 0

    def expr(s):
        s = s.strip().replace('&&', ' and ').replace('||', ' or ')
        s = re.sub(r'\$\$(\w+)', r'self.\1', s)
        s = re.sub(r'\$(\w+)', lambda m: ('self.' if m[1] in global_names else '') + m[1], s)
        s = s.replace('math.', 'm.')
        return s

    for raw in source.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == '{':
            indent += 1
            continue
        if line == '}':
            indent -= 1
            continue
        if line.startswith('command '):
            match = re.match(r'command\s+\$\$(\w+)(?:\((.*?)\))?(?:\s*:\s*int)?$', line)
            assert match, line
            name, args = match.groups()
            arg_names = re.findall(r'\$(\w+)', args or '')
            line = f'def {name}(self' + ''.join(', ' + a for a in arg_names) + '):'
        elif line.startswith('property '):
            continue
        elif line.startswith('if('):
            assert line.endswith(')'), line
            line = 'if ' + expr(line[3:-1]) + ':'
        elif line == 'else':
            line = 'else:'
        elif line.startswith('for('):
            match = re.match(r'for\(\s*\$(\w+)\s*=\s*(.*?),\s*\$\1\s*<\s*(.*?),\s*\$\1\s*\+=\s*1\s*\)', line)
            assert match, line
            name, start, end = match.groups()
            line = f'for {name} in range({expr(start)}, {expr(end)}):'
        elif line.startswith('return'):
            line = 'return' + (' ' + expr(line[6:]) if len(line) > 6 else '')
        else:
            line = expr(line)
            if re.fullmatch(r'self\.\w+', line):
                line += '()'
        out.append('    ' * indent + line)
    py_source = '\n'.join(out)
    tree = ast.parse(py_source)
    tree = IntArithmetic().visit(tree)
    ast.fix_missing_locations(tree)
    ns = {'idiv': idiv, 'imod': imod, 'i32': i32, 'm': MathShim}
    exec(compile(tree, str(ROOT / 'scene/zzz_flight_sim.ss'), 'exec'), ns)
    simtype = type('NativeSS', (), {k: v for k, v in ns.items() if k.startswith('fl_')})
    sim = simtype()
    for name in global_names:
        setattr(sim, name, IntList() if name in lists else 0)
    sim.fl_sim_init()
    return sim


def fly_fixture(sim, sink=110):
    """A pilot drives the real control inputs; never teleports the aircraft.

    It flies like a person on a keyboard: arrow keys chase a flight-path angle,
    Q/A chase an airspeed, and it never commands more climb than the aircraft has.
    """
    trace = []
    inputs = []
    previous_gamma = 0
    for tick in range(36000):
        if sim.fl_state != 1:
            break
        if sim.fl_airborne == 0:
            sim.fl_in_throttle = 1
            sim.fl_in_pitch = 1 if sim.fl_speed > 2400 and sim.fl_pitch < 85 else 0
            sim.fl_in_roll = 0
        elif sim.fl_touched:
            sim.fl_in_throttle = -1
            sim.fl_in_pitch = 0
            sim.fl_in_brake = 1
            h = (sim.fl_heading + 1800) % 3600 - 1800
            sim.fl_in_roll = -1 if h > 1 else (1 if h < -1 else 0)
        else:
            i = sim.fl_gate_index
            final = i >= sim.fl_gate_count
            if not final:
                gx, gz, gy = sim.fl_gate_x[i], sim.fl_gate_z[i], sim.fl_gate_y[i]
            else:
                gx, gz, gy = 0, sim.fl_z + 30000, 0
            dx, dz = gx - sim.fl_x, gz - sim.fl_z
            desired_hdg = math.atan2(dx, dz) * 1800 / math.pi
            err = (desired_hdg - sim.fl_heading + 1800) % 3600 - 1800
            roll_target = max(-300, min(300, err * 1.1))
            sim.fl_in_roll = 1 if sim.fl_roll < roll_target - 5 else (-1 if sim.fl_roll > roll_target + 5 else 0)
            if final:
                desired_vs = -sink if sim.fl_alt < 250 else -200
            else:
                desired_vs = max(-280, min(280, (gy - sim.fl_alt) * .35))
            if sim.fl_speed < 2750 and desired_vs > 0:
                desired_vs = 0
            gamma_target = math.asin(max(-.5, min(.5, desired_vs / max(1500, sim.fl_speed)))) * 1800 / math.pi
            gamma = sim.fl_gamma / 100
            error = gamma_target - gamma - (gamma - previous_gamma) * 12
            previous_gamma = gamma
            sim.fl_in_pitch = 1 if error > 2 else (-1 if error < -2 else 0)
            target_speed = 3000 if i < 14 else 2750
            if final:
                target_speed = 2600
            sim.fl_in_throttle = 1 if sim.fl_speed < target_speed - 15 else (-1 if sim.fl_speed > target_speed + 15 else 0)
            if final and sim.fl_alt < 250:
                sim.fl_in_throttle = -1
        old_gate = sim.fl_gate_index
        inputs.append((sim.fl_in_pitch, sim.fl_in_roll, sim.fl_in_throttle, sim.fl_in_brake))
        sim.fl_sim_step()
        if sim.fl_gate_index != old_gate or tick % 1000 == 0 or sim.fl_state != 1:
            trace.append(dict(tick=tick, x=sim.fl_x, z=sim.fl_z, alt=sim.fl_alt,
                              speed=sim.fl_speed, h=sim.fl_heading, pitch=sim.fl_pitch,
                              aoa=sim.fl_aoa, throttle=sim.fl_throttle,
                              gate=sim.fl_gate_index, state=sim.fl_state, reason=sim.fl_fail_reason))
    sim.test_inputs = inputs
    return trace


def write_native_replay(sim):
    """Generate an isolated validation scene, never placed in production src/."""
    inputs = sim.test_inputs
    with (ROOT / 'build/native-input-trace.csv').open('w', newline='', encoding='utf8') as f:
        writer = csv.writer(f)
        writer.writerow(('tick', 'pitch', 'roll', 'throttle', 'brake'))
        writer.writerows((i, *keys) for i, keys in enumerate(inputs))
    runs = []
    for keys in inputs:
        if runs and runs[-1][0] == keys:
            runs[-1][1] += 1
        else:
            runs.append([keys, 1])
    lines = ['// Isolated test-only input replay, generated from the actual SS test.',
             '// Do not include this scene in the deployed game package.',
             '#z00', 'close', '$$fl_sim_init', '$$fl_draw_init']
    for (pitch, roll, throttle, brake), count in runs:
        lines += [f'$fl_in_pitch = {pitch}', f'$fl_in_roll = {roll}', f'$fl_in_throttle = {throttle}',
                  f'$fl_in_brake = {brake}',
                  f'for( l[0] = 0, l[0] < {count}, l[0] += 1 ) {{',
                  '    $$fl_sim_step', '    if( $fl_step_ticks % 250 == 0 ) {',
                  '        $$fl_draw_frame', '        disp', '    }', '}']
    lines += ['$$fl_draw_frame', 'input.clear', 'R', '$$fl_draw_clear', 'return']
    (ROOT / 'build/zzz_flight_validation.ss').write_text('\n'.join(lines) + '\n', encoding='utf8')
    return len(runs)


KT = 0.0194384  # cm/s -> knots


def airborne(speed, pitch=33, roll=0, alt=15000, throttle=0, gamma=0):
    """Place the real SS aircraft in free air, away from gates and boundaries."""
    a = load_ss()
    a.fl_airborne, a.fl_phase = 1, 3
    a.fl_x, a.fl_z = 300000, 0
    a.fl_alt = a.fl_max_alt = alt
    a.fl_speed, a.fl_pitch, a.fl_roll = speed, pitch, roll
    a.fl_throttle, a.fl_gamma = throttle, gamma
    a.fl_aoa = pitch + 30 - gamma // 100
    return a


def run(sim, ticks, hold_roll=None):
    for _ in range(ticks):
        if hold_roll is not None:
            sim.fl_roll, sim.fl_roll_rem = hold_roll, 0
        sim.fl_sim_step()
        assert sim.fl_state == 1, (sim.fl_state, sim.fl_fail_reason)


def aerodynamics():
    """Calibration of the shipped SS aerodynamics against light-biplane figures."""
    out = {}

    def stall_kt(bank):
        lo, hi = 1500, 4000
        while hi - lo > 2:
            mid = (lo + hi) // 2
            a = airborne(mid, pitch=114, roll=bank)  # angle of attack at CLmax
            a.fl_sim_step()
            if a.fl_lift * math.cos(math.radians(bank / 10)) >= 981:
                hi = mid
            else:
                lo = mid
        return hi * KT
    out['stall_kt'] = {b // 10: round(stall_kt(b), 1) for b in (0, 300, 450)}
    assert 43 <= out['stall_kt'][0] <= 45
    assert 46 <= out['stall_kt'][30] <= 48.5
    assert 51 <= out['stall_kt'][45] <= 53.5
    # Past the critical angle lift breaks and the nose drops even with full back stick.
    deep = airborne(2300, pitch=180)
    deep.fl_in_pitch = 1
    run(deep, 100)
    assert deep.fl_stall == 2 or deep.fl_aoa < 160
    assert deep.fl_pitch < 180 and deep.fl_vspeed < 0

    def level_throttle(speed):
        cl = 981 * 7294 // (speed * speed // 1000)
        pitch = (cl - 250) // 8 - 30
        best = None
        for throttle in range(0, 1001, 5):
            a = airborne(speed, pitch=pitch, throttle=throttle)
            before = a.fl_speed * 50 + a.fl_speed_rem
            a.fl_sim_step()
            gain = a.fl_speed * 50 + a.fl_speed_rem - before
            if best is None or abs(gain) < best[0]:
                best = (abs(gain), throttle, pitch)
        return best[1], best[2]
    throttle60, pitch60 = level_throttle(3087)
    out['level_60kt'] = {'throttle_percent': throttle60 / 10, 'pitch_deg': pitch60 / 10}
    assert 500 <= throttle60 <= 650 and 0 <= pitch60 <= 60

    # Hands-off full-power climb settles near the 57 kt trim speed.
    climb = airborne(3000, throttle=1000)
    run(climb, 1000)
    alt0 = climb.fl_alt
    run(climb, 1000)
    out['full_power_climb_fpm'] = round((climb.fl_alt - alt0) / 20 * 1.9685)
    out['climb_speed_kt'] = round(climb.fl_speed * KT, 1)
    assert 450 <= out['full_power_climb_fpm'] <= 800

    # Power-off glide ratio over 30 s after the phugoid has settled.
    glide = airborne(2900, throttle=0, alt=45000)
    run(glide, 1000)
    x0, z0, alt0 = glide.fl_x, glide.fl_z, glide.fl_alt
    run(glide, 1500)
    out['glide_ratio'] = round(math.hypot(glide.fl_x - x0, glide.fl_z - z0) / (alt0 - glide.fl_alt), 1)
    out['glide_speed_kt'] = round(glide.fl_speed * KT, 1)
    assert 6.5 <= out['glide_ratio'] <= 9.5

    # Coordinated turn: rate = g tan(bank) / V when lift is raised by 1/cos(bank).
    turn = airborne(3087, pitch=47, roll=300, throttle=700)
    run(turn, 50, hold_roll=300)
    rate = turn.fl_turn_total / 10
    expected = math.degrees(9.81 * math.tan(math.radians(30)) / 30.87)
    out['turn_30deg_dps'] = {'sim': round(abs(rate), 2), 'theory': round(expected, 2)}
    assert rate > 0 and abs(rate - expected) / expected < 0.08
    # The same bank at level-flight pitch loses height: back pressure is required.
    sag = airborne(3087, pitch=33, roll=300, throttle=566)
    run(sag, 250, hold_roll=300)
    level = airborne(3087, pitch=33, roll=0, throttle=566)
    run(level, 250, hold_roll=0)
    out['bank_without_pull_fpm'] = {'level': round(level.fl_vspeed * 1.9685), 'bank30': round(sag.fl_vspeed * 1.9685)}
    assert sag.fl_vspeed < 0 and level.fl_vspeed - sag.fl_vspeed > 80

    # Ground effect: identical state, less drag at half a metre than at 30 m.
    def gain(alt):
        a = airborne(2700, pitch=60, alt=alt, throttle=200)
        before = a.fl_speed * 50 + a.fl_speed_rem
        a.fl_sim_step()
        return a.fl_speed * 50 + a.fl_speed_rem - before
    assert gain(50) > gain(3000)

    # Lift-off emerges from lift exceeding weight after rotation, not a fixed rule.
    roll = load_ss()
    liftoff = None
    for _ in range(3000):
        roll.fl_in_throttle = 1
        roll.fl_in_pitch = 1 if roll.fl_speed > 2400 and roll.fl_pitch < 85 else 0
        roll.fl_sim_step()
        if roll.fl_airborne and liftoff is None:
            liftoff = (roll.fl_speed * KT, (roll.fl_z - 10000) / 100)
            break
    out['liftoff'] = {'kt': round(liftoff[0], 1), 'ground_roll_m': round(liftoff[1])}
    assert 46 <= liftoff[0] <= 52 and 150 <= liftoff[1] <= 400
    # Without rotation the grass roll does not leave the ground below 60 kt.
    flat = load_ss()
    flat.fl_in_throttle = 1
    for _ in range(1200):
        flat.fl_sim_step()
        if flat.fl_state != 1 or flat.fl_airborne:
            break
    assert flat.fl_airborne == 0 or flat.fl_speed * KT > 60

    # Abuse: random keys and extreme manoeuvres keep every 32-bit intermediate valid.
    import random
    for seed in range(3):
        rng = random.Random(seed)
        a = airborne(3000, alt=30000, throttle=1000)
        for tick in range(9000):
            if tick % 25 == 0:
                a.fl_in_pitch, a.fl_in_roll, a.fl_in_throttle = (rng.choice((-1, 0, 1)) for _ in range(3))
            a.fl_sim_step()
            if a.fl_state != 1:
                break
        assert 0 <= a.fl_speed <= 7500
    dive = airborne(3000, pitch=-300, alt=50000, throttle=1000)
    dive.fl_in_pitch, dive.fl_in_throttle = -1, 1
    for _ in range(3000):
        dive.fl_sim_step()
        if dive.fl_state != 1:
            break
    assert dive.fl_speed <= 7500
    return out


def tests():
    aero = aerodynamics()
    print(json.dumps(aero, indent=2))
    s = load_ss()
    # Exactly one second at 50 Hz adds 25%; release holds; stops clamp.
    s.fl_in_throttle = 1
    for _ in range(50):
        s.fl_sim_step()
    assert s.fl_throttle == 250
    s.fl_in_throttle = 0
    for _ in range(100):
        s.fl_sim_step()
    assert s.fl_throttle == 250
    s.fl_throttle = 999
    s.fl_in_throttle = 1
    s.fl_sim_step()
    assert s.fl_throttle == 1000
    s.fl_throttle = 1
    s.fl_in_throttle = -1
    s.fl_sim_step()
    assert s.fl_throttle == 0
    # Pause does not advance physics or consume throttle.
    s.fl_state = 2
    before = (s.fl_elapsed_ms, s.fl_x, s.fl_z, s.fl_throttle)
    s.fl_sim_step()
    assert before == (s.fl_elapsed_ms, s.fl_x, s.fl_z, s.fl_throttle)

    def cross(offset=0, backwards=False):
        g = load_ss()
        g.fl_airborne = 1
        g.fl_x = offset
        g.fl_z = 75100 if not backwards else 74900
        g.fl_alt = g.fl_gate_y[0]
        g.fl_check_gates(offset, 74900 if not backwards else 75100, g.fl_gate_y[0])
        return g

    # 19 frames share 50 points; the circuit's last point is the touchdown aim point.
    per_gate = 5000 // 19
    c = cross()
    assert c.fl_gate_count == 19
    assert c.fl_gate_points == per_gate and c.fl_gate_hits == 1
    c.fl_check_gates(0, 74900, c.fl_gate_y[0])
    assert c.fl_gate_points == per_gate, 'same gate must not score twice'
    off = cross(9000)
    assert off.fl_gate_index == 1 and off.fl_gate_points == 0 and off.fl_gate_misses == 1
    assert cross(backwards=True).fl_gate_index == 0
    near = cross(3000)
    assert 0 < near.fl_gate_points < per_gate

    def land(vs=-100, x=0, z=22000, valid=True):
        a = load_ss()
        a.fl_airborne = 1
        a.fl_x, a.fl_z, a.fl_alt = x, z, -2
        a.fl_speed, a.fl_vspeed = 2600, vs
        a.fl_max_alt = 15000
        a.fl_gate_index = a.fl_gate_count if valid else 0
        a.fl_route_mask = 7
        a.fl_turn_total = -3600
        a.fl_touchdown()
        return a

    soft, hard = land(-40), land(-300)
    assert soft.fl_landing_points > hard.fl_landing_points
    assert soft.fl_landing_points == 3000 and soft.fl_center_points == 1000 and soft.fl_aim_points == 1000
    assert land(-600).fl_state == 4 and land(-600).fl_fail_reason == 2
    assert land(x=4000).fl_fail_reason == 1
    assert land(valid=False).fl_fail_reason == 3
    # Touching down short of the aim point, inside the runway, is a valid landing.
    short = land(z=15000)
    assert short.fl_state == 1 and short.fl_fail_reason == 0 and short.fl_phase == 6
    assert (short.fl_touch_x, short.fl_touch_z) == (0, 15000)
    # Accuracy scores fall steadily with the miss and reach zero at their limits:
    # centreline full within 0.5 m, zero from 8 m; aim point full within 5 m, zero from 75 m.
    offsets = (0, 50, 200, 400, 600, 800, 1500)
    distances = (22000, 21500, 19000, 26000, 16000, 14500, 40000)
    lateral = [land(x=x).fl_center_points for x in offsets]
    along = [land(z=z).fl_aim_points for z in distances]
    assert lateral[:2] == [1000, 1000] and lateral[-2:] == [0, 0]
    assert all(a > b for a, b in zip(lateral[1:5], lateral[2:6]))
    assert along[:2] == [1000, 1000] and along[-2:] == [0, 0]
    assert along[1] > along[2] > along[3] > along[4] > along[5]
    assert land(z=26000).fl_aim_points == land(z=18000).fl_aim_points
    assert land(x=-600).fl_center_points == land(x=600).fl_center_points
    total = land(vs=-60, x=300, z=24000)
    assert total.fl_total == (total.fl_gate_points + total.fl_landing_points
                              + total.fl_center_points + total.fl_aim_points) // 100

    # Wheel brakes on the landing roll: B shortens the stop; it does nothing before touchdown.
    def rollout(brake):
        a = land(z=20000)
        a.fl_speed = 2500
        a.fl_in_brake = brake
        for _ in range(3000):
            a.fl_sim_step()
            if a.fl_state != 1:
                break
        assert a.fl_state == 3
        return (a.fl_z - 20000) / 100
    free, braked = rollout(0), rollout(1)
    assert braked < free * 0.5 and 40 <= braked <= 110, (free, braked)
    roll_free, roll_brake = load_ss(), load_ss()
    roll_brake.fl_in_brake = 1
    for g in (roll_free, roll_brake):
        g.fl_in_throttle = 1
        for _ in range(400):
            g.fl_sim_step()
    assert (roll_free.fl_speed, roll_free.fl_z) == (roll_brake.fl_speed, roll_brake.fl_z)
    # Ground steering: weak standing still, full from about 20 kt, eased in, and only on
    # the ground. Measured over one second of holding right from a straight start.
    def steer(speed):
        g = load_ss()
        g.fl_speed = speed
        g.fl_in_roll = 1
        for _ in range(50):
            g.fl_speed = speed
            g.fl_sim_step()
        return g.fl_heading / 10, g
    steer_still, still = steer(0)
    steer_slow, _ = steer(400)
    steer_fast, _ = steer(1300)
    assert 0.5 <= steer_still <= 1.0 and steer_still < steer_slow < steer_fast and 6.5 <= steer_fast <= 8.0
    first = load_ss()
    first.fl_in_roll = 1
    first.fl_speed = 1300
    first.fl_sim_step()
    assert first.fl_heading <= 1, 'steering must ease in, not jump'
    assert still.fl_roll == 0
    landing_checks = {'stop_m_free': round(free), 'stop_m_braked': round(braked),
                      'center_points_by_offset_cm': dict(zip(offsets, lateral)),
                      'aim_points_by_z_cm': dict(zip(distances, along)),
                      'steer_deg_in_1s': {'0kt': steer_still, '8kt': steer_slow, '25kt': steer_fast}}
    print(json.dumps(landing_checks))
    locked = soft.fl_touch_fpm
    soft.fl_vspeed = -900
    soft.fl_touchdown()
    assert soft.fl_touch_fpm == locked, 'bounce must not replace first contact'
    # A completed right circuit does not satisfy a left circuit.
    right = land()
    right.fl_touched = 0
    right.fl_turn_total = 3600
    right.fl_touchdown()
    assert right.fl_fail_reason == 3

    flight = load_ss()
    trace = fly_fixture(flight)
    report = {'state': flight.fl_state, 'reason': flight.fl_fail_reason,
              'time_seconds': flight.fl_elapsed_ms / 1000,
              'gate_hits': flight.fl_gate_hits, 'misses': flight.fl_gate_misses,
              'gate_points': flight.fl_gate_points, 'landing_points': flight.fl_landing_points,
              'center_points': flight.fl_center_points, 'aim_points': flight.fl_aim_points,
              'touch_fpm': flight.fl_touch_fpm, 'touch_x_m': flight.fl_touch_x / 100,
              'touch_z_m': flight.fl_touch_z / 100, 'score': flight.fl_total,
              'stop_z_m': flight.fl_z / 100, 'landing_checks': landing_checks,
              'aerodynamics': aero, 'trace': trace}
    (ROOT / 'build/simulation-report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in report.items() if k != 'trace'}, indent=2))
    assert flight.fl_state == 3, 'a pilot using only the advertised controls must complete the circuit'
    assert flight.fl_gate_hits >= 16
    assert 170 <= flight.fl_elapsed_ms / 1000 <= 420
    assert flight.fl_touch_fpm < 0 and flight.fl_z < 90000
    print(f'Native replay: {write_native_replay(flight)} input runs')
    print('PASS: actual SS aerodynamics, controls, pause, gates, misses, first contact, '
          'touchdown accuracy, brakes and complete left circuit')


if __name__ == '__main__':
    tests()
