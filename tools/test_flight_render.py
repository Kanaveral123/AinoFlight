"""Frame-by-frame check of the shipped renderer's projection math (flicker guard).

The pure SS commands that place ground strips and 3D lines (camera, clip, projection
and strip width) are taken from zzz_flight_draw.ss and executed natively, with 32-bit
overflow checks, along the reference circuit flown by the test pilot. It fails if a
strip's width oscillates between frames or a line's endpoints would need clamping
(which bends the line), the two causes of flicker found in v5.
"""
from __future__ import annotations

import json
import math
import re

import test_flight_sim as T

ROOT = T.ROOT
PURE = ('fl_d_clamp', 'fl_d_camera', 'fl_d_screen', 'fl_d_plane', 'fl_d_part', 'fl_d_cross', 'fl_d_clip3',
        'fl_d_proj16', 'fl_d_strip_width', 'fl_d_round16', 'fl_d_coast_edge', 'fl_d_coast_calc',
        'fl_d_rect_calc', 'fl_d_region_calc')
# Runway markings drawn by $$fl_d_rect: (slot, x1, z1, x2, z2, world width cm).
RUNWAY_MARKS = ([(70 + i, 0, i * 7500 + 1600, 0, i * 7500 + 4200, 60) for i in range(12)]
                + [(82 + i, (i - 4) * 650 + 300, 1000, (i - 4) * 650 + 300, 4800, 250) for i in range(8)]
                + [(98, -1900, 20500, -1900, 23500, 400), (99, 1900, 20500, 1900, 23500, 400),
                   (169, -1200, 22000, 1200, 22000, 250), (170, 0, 20800, 0, 23200, 250)]
                + [(26 + i, -3000, i * 2250 + 1100, 3000, i * 2250 + 1100, 2250) for i in range(40)])


def bar_shape(sim):
    """Corners of the drawn bar relative to its centre, in pixels (rolled screen)."""
    dx, dy, t = sim.fl_d_rc_dx / 16, sim.fl_d_rc_dy / 16, max(sim.fl_d_rc_t, 16) / 16
    length = max(math.hypot(dx, dy), 0.5)
    nx, ny = -dy / length * t / 2, dx / length * t / 2
    return [(sx * dx + tx * nx, sx * dy + tx * ny) for sx in (-1, 1) for tx in (-1, 1)], max(2 * length, t)


def shape_change(a, b):
    return max(min(math.hypot(p[0] - q[0], p[1] - q[1]) for q in b) for p in a)


def MathShim_tan(sim):
    # Same integer horizon offset the horizon group gets from math.tan(pitch, 850).
    return T.MathShim.tan(sim.fl_pitch, 850)


def runway_layers(sim):
    """The four runway-surface regions exactly as $$fl_d_world lays them out."""
    out = []
    for args in ((-3000, sim.fl_z - 800000, -3000, sim.fl_z + 800000, 1, 0),
                 (3000, sim.fl_z - 800000, 3000, sim.fl_z + 800000, 1, 0),
                 (sim.fl_x - 800000, 0, sim.fl_x + 800000, 0, 0, -1),
                 (sim.fl_x - 800000, 90000, sim.fl_x + 800000, 90000, 0, 1)):
        mode = sim.fl_d_region_calc(*args)
        out.append((mode, sim.fl_d_rg_x, sim.fl_d_rg_y, math.atan2(sim.fl_d_rg_dy, sim.fl_d_rg_dx)))
    return out


def covers(layer, hx, hy):
    mode, px, py, theta = layer
    if mode != 2:
        return mode == 1
    c, s = math.cos(theta), math.sin(theta)
    lx = (hx - px) * c + (hy - py) * s
    ly = -(hx - px) * s + (hy - py) * c
    return 0 <= lx <= 12000 and 0 <= ly <= 6000


def on_runway(sim, sx, sy):
    """Ground point seen at unrolled screen offset (sx, sy): None for sky, else whether
    it lies on the runway. Inverse of $$fl_d_camera / $$fl_d_screen in floating point."""
    p = math.radians(sim.fl_pitch / 10)
    h = math.radians(sim.fl_heading / 10)
    eye = sim.fl_alt + 150
    denom = -sy / 850 * math.cos(p) + math.sin(p)
    if denom >= -1e-6:
        return None
    t = -eye / denom
    forward = t * (sy / 850 * math.sin(p) + math.cos(p))
    lateral = t * sx / 850
    x = sim.fl_x + lateral * math.cos(h) + forward * math.sin(h)
    z = sim.fl_z - lateral * math.sin(h) + forward * math.cos(h)
    return -3000 < x < 3000 and 0 < z < 90000


def command(source, name):
    match = re.search(r'command\s+\$\$' + re.escape(name) + r'\b[^\n]*\n\{', source)
    assert match, f'Missing real SS command {name}'
    end = source.index('{', match.start()) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


def load_render():
    draw = (ROOT / 'scene/zzz_flight_draw.ss').read_text(encoding='utf8')
    inc = draw[draw.index('#inc_start'):draw.index('#inc_end')]
    inc = '\n'.join(l for l in inc.splitlines() if '#property' in l)
    sim = T.load_ss('\n'.join(command(draw, n) for n in PURE), inc)
    return sim, draw


def ground_strips(draw):
    """Every road, crop-row segment and aim mark exactly as $$fl_d_world lays them out."""
    world = command(draw, 'fl_d_world')
    strips = []
    for args in re.findall(r'\$\$fl_d_strip\(\$fl_d_root\.child\[1\]\.child\[\d+\],\s*([^)]*)\)', world):
        x1, z1, x2, z2, w = (int(v) for v in args.split(',')[:5])
        strips.append((x1, z1, x2, z2, w))
    for args in re.findall(r'\$\$fl_d_field\(([^)]*)\)', world):
        _, x, z, sx, sz, lx, lz, w = (int(v) for v in args.split(',')[:8])
        for i in range(5):
            for j in range(3):
                x0 = x + i * sx + int(lx * j / 3)
                z0 = z + i * sz + int(lz * j / 3)
                strips.append((x0, z0, x0 + int(lx / 3), z0 + int(lz / 3), w))
    return strips


def frame(sim):
    m = T.MathShim
    sim.fl_d_cos_h, sim.fl_d_sin_h = m.cos(sim.fl_heading, 1000), m.sin(sim.fl_heading, 1000)
    sim.fl_d_cos_p, sim.fl_d_sin_p = m.cos(sim.fl_pitch, 1000), m.sin(sim.fl_pitch, 1000)
    sim.fl_d_cos_r, sim.fl_d_sin_r = m.cos(sim.fl_roll, 1000), m.sin(sim.fl_roll, 1000)


def endpoints(sim, x1, y1, z1, x2, y2, z2):
    if not sim.fl_d_clip3(x1, y1, z1, x2, y2, z2):
        return None
    sim.fl_d_screen(sim.fl_d_ax, sim.fl_d_ay, sim.fl_d_az)
    a = (sim.fl_d_screen_x, sim.fl_d_screen_y)
    sim.fl_d_screen(sim.fl_d_bx, sim.fl_d_by, sim.fl_d_bz)
    return a, (sim.fl_d_screen_x, sim.fl_d_screen_y)


def inside_clamp_box(p):
    # $$fl_d_line2 clamps x to [-2048, 3968] and y to [-1500, 2580].
    return -2048 <= p[0] <= 3968 and -1500 <= p[1] <= 2580


def drawn(a, b):
    # $$fl_d_line2 skips a line whose ends both lie past the same screen edge.
    return not ((a[0] < -20 and b[0] < -20) or (a[0] > 1940 and b[0] > 1940)
                or (a[1] < -20 and b[1] < -20) or (a[1] > 1100 and b[1] > 1100))


def tests():
    pilot = T.load_ss()
    T.fly_fixture(pilot)
    inputs = pilot.test_inputs
    sim, draw = load_render()
    sim.fl_d_rc_axis.resize(171)
    strips = ground_strips(draw)
    assert len(strips) >= 60, len(strips)
    history = {}
    oscillations = []
    clamped = 0
    frames = 0
    largest = 0
    coast_frames = beach_missing = coast_jitter = 0
    coast_seq = []
    mark_frames = mark_twitches = 0
    mark_prev = {}
    surface_frames = surface_points = surface_wrong = 0
    surface_modes = {0: 0, 1: 0, 2: 0}
    surface_examples = []
    for tick, keys in enumerate(inputs):
        sim.fl_in_pitch, sim.fl_in_roll, sim.fl_in_throttle, sim.fl_in_brake = keys
        sim.fl_sim_step()
        if tick % 2:
            continue                      # 25 Hz samples of the 50 Hz flight
        frames += 1
        frame(sim)
        # Runway surface: the painted layers show runway exactly where the ground is
        # runway (points within 3 px of an edge are skipped), on the roll and in the air.
        if tick % 24 == 0 or (not sim.fl_airborne and tick % 4 == 0):
            surface_frames += 1
            layers = runway_layers(sim)
            for layer in layers:
                surface_modes[layer[0]] += 1
            lift = MathShim_tan(sim)
            for sx in range(-900, 901, 75):
                for sy in range(-150, 601, 25):
                    truth = on_runway(sim, sx, sy)
                    near = [on_runway(sim, sx + ox, sy + oy) for ox, oy in ((3, 0), (-3, 0), (0, 3), (0, -3))]
                    if truth is None or any(v is None or v != truth for v in near):
                        continue
                    hx, hy = sx, sy - lift
                    painted = covers(layers[0], hx, hy) and not any(covers(l, hx, hy) for l in layers[1:])
                    surface_points += 1
                    if painted != truth:
                        surface_wrong += 1
                        if len(surface_examples) < 5:
                            surface_examples.append((tick, sx, sy, truth, painted, sim.fl_z, sim.fl_alt, sim.fl_heading))
        # Coast: with the sea ahead, the beach band never vanishes and the edge never
        # jumps away and back between frames.
        heading = (sim.fl_heading + 1800) % 3600 - 1800
        if sim.fl_z < 230000 and abs(heading) < 600:
            sim.fl_d_coast_calc()
            coast_frames += 1
            if math.hypot(sim.fl_d_cl_px - sim.fl_d_cb_px, sim.fl_d_cl_py - sim.fl_d_cb_py) < 1:
                beach_missing += 1
            coast_seq.append(math.hypot(sim.fl_d_cl_px, sim.fl_d_cl_py))
            del coast_seq[:-3]
            if len(coast_seq) == 3:
                a, b, c = coast_seq
                if (b - a) * (b - c) > 0 and min(abs(b - a), abs(b - c)) >= 2:
                    coast_jitter += 1
        else:
            coast_seq.clear()
        # Runway markings on final: a visible bar never changes shape and changes back
        # (a twitch); a single change as the view opens up is allowed.
        if sim.fl_airborne and not sim.fl_touched and sim.fl_gate_index >= 15:
            mark_frames += 1
            for mark in RUNWAY_MARKS:
                slot = mark[0]
                visible = sim.fl_d_rect_calc(*mark) and 0 <= sim.fl_d_rc_x / 16 <= 1920 \
                    and 0 <= sim.fl_d_rc_y / 16 <= 1080
                if not visible:
                    mark_prev.pop(slot, None)
                    continue
                shape, size = bar_shape(sim)
                seq = mark_prev.setdefault(slot, [])
                seq.append(shape)
                del seq[:-3]
                if len(seq) == 3:
                    jump = shape_change(seq[2], seq[1])
                    back = shape_change(seq[2], seq[0])
                    if jump > 2 and jump > 0.25 * size and back < jump / 2:
                        mark_twitches += 1
        else:
            mark_prev.clear()
        # Long lines that previously bent when both ends were far off-screen.
        base_x, base_z = int(sim.fl_x / 30000) * 30000, int(sim.fl_z / 30000) * 30000
        for line in ((base_x - 180000, 0, base_z, base_x + 180000, 0, base_z),
                     (base_x, 0, base_z - 180000, base_x, 0, base_z + 180000),
                     (-3000, 8, 0, -3000, 8, 90000), (3000, 8, 0, 3000, 8, 90000),
                     (-300000, 5, 231000, -150000, 5, 231000)):
            ends = endpoints(sim, *line)
            if ends and not (inside_clamp_box(ends[0]) and inside_clamp_box(ends[1])):
                clamped += 1
        for n, (x1, z1, x2, z2, w) in enumerate(strips):
            # Strips beyond 4 km are a pixel or two; the game still draws them up to 7 km.
            if abs((x1 + x2) // 2 - sim.fl_x) > 400000 or abs((z1 + z2) // 2 - sim.fl_z) > 400000:
                history.pop(n, None)
                continue
            ends = endpoints(sim, x1, 5, z1, x2, 5, z2)
            if not ends:
                history.pop(n, None)
                continue
            if not (inside_clamp_box(ends[0]) and inside_clamp_box(ends[1])):
                clamped += 1
            if not drawn(*ends):
                history.pop(n, None)
                continue
            width = sim.fl_d_strip_width(x1, z1, x2, z2, w)
            largest = max(largest, width)
            seq = history.setdefault(n, [])
            seq.append(width)
            del seq[:-3]
            # Flicker is a jump that immediately jumps back; perspective change is monotonic.
            if len(seq) == 3:
                a, b, c = seq
                up = b - max(a, c)
                down = min(a, c) - b
                swing = max(up, down)
                if swing >= 3 and swing * 3 >= max(a, b, c):
                    oscillations.append((tick, n, seq[:]))
    report = {'frames_at_25hz': frames, 'strips': len(strips), 'largest_width_px': largest,
              'width_oscillations': len(oscillations), 'clamped_line_endpoints': clamped,
              'coast_frames': coast_frames, 'beach_missing_frames': beach_missing,
              'coast_edge_jitter': coast_jitter, 'final_frames': mark_frames,
              'runway_mark_twitches': mark_twitches, 'surface_frames': surface_frames,
              'surface_points': surface_points, 'surface_wrong': surface_wrong,
              'surface_modes': surface_modes, 'surface_examples': surface_examples,
              'examples': oscillations[:5]}
    (ROOT / 'build/render-report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, indent=2))
    assert not oscillations, 'strip widths flicker'
    assert clamped == 0, 'line endpoints still need clamping'
    assert coast_frames > 500 and beach_missing == 0 and coast_jitter == 0, 'coastline flickers'
    assert mark_frames > 500 and mark_twitches == 0, 'runway markings twitch'
    assert surface_points > 100000 and surface_modes[2] > 1000 and surface_wrong == 0, 'runway surface misdrawn'
    print('PASS: strips, coastline and runway markings stay steady frame to frame; the runway '
          'surface matches the ground exactly; clipped lines keep their direction')


if __name__ == '__main__':
    tests()
