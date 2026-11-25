// Native SS flight simulation; no external runtime, automatic steering or rails.
// All integration and scoring execute at a fixed 50 Hz. Positive pitch raises nose.
// Point-mass aerodynamics of a light biplane: lift and drag from angle of attack and
// dynamic pressure, propeller thrust, weight, ground friction and ground effect.
// Speeds cm/s, accelerations cm/s2, angles tenths of a degree; flight-path angle,
// pitch/roll rates and their remainders use millidegrees. Integer remainders keep
// small forces from being truncated away at 20 ms.
#z00
return

command $$fl_clamp(property $value, property $low, property $high) : int
{
    if( $value < $low ) { return ($low) }
    if( $value > $high ) { return ($high) }
    return ($value)
}

command $$fl_gate_set(property $i, property $x, property $z, property $y, property $h, property $r, property $p)
{
    $fl_gate_x[$i] = $x
    $fl_gate_z[$i] = $z
    $fl_gate_y[$i] = $y
    $fl_gate_heading[$i] = $h
    $fl_gate_radius[$i] = $r
    $fl_gate_phase[$i] = $p
}

command $$fl_sim_init
{
    property $i
    $fl_x = 0
    $fl_z = 10000
    $fl_alt = 0
    $fl_speed = 0
    $fl_vspeed = 0
    $fl_heading = 0
    $fl_pitch = 0
    $fl_roll = 0
    $fl_throttle = 0
    $fl_in_pitch = 0
    $fl_in_roll = 0
    $fl_in_throttle = 0
    $fl_state = 1
    $fl_phase = 0
    $fl_airborne = 0
    $fl_max_alt = 0
    $fl_step_ticks = 0
    $fl_elapsed_ms = 0
    $fl_turn_rem = 0
    $fl_turn_total = 0
    $fl_route_mask = 0
    $fl_gate_index = 0
    // 19 frames are flown through; the 20th point of the circuit is the touchdown aim
    // point on the runway (0, 220 m), scored by where the wheels first touch.
    $fl_gate_count = 19
    $fl_gate_points = 0
    $fl_gate_hits = 0
    $fl_gate_misses = 0
    $fl_last_precision = 0
    $fl_gate_event = 0
    $fl_landing_points = 0
    $fl_total = 0
    $fl_touch_fpm = 0
    $fl_touch_speed = 0
    $fl_touch_roll = 0
    $fl_touched = 0
    $fl_landing_ticks = 0
    $fl_fail_reason = 0
    $fl_stall = 0
    $fl_gamma = 0
    $fl_gamma_rem = 0
    $fl_speed_rem = 0
    $fl_x_rem = 0
    $fl_z_rem = 0
    $fl_alt_rem = 0
    $fl_pitch_rem = 0
    $fl_roll_rem = 0
    $fl_aoa = 30
    $fl_lift = 0
    $fl_in_brake = 0
    $fl_touch_x = 0
    $fl_touch_z = 0
    $fl_center_points = 0
    $fl_aim_points = 0
    $fl_steer = 0
    $fl_steer_rem = 0
    $fl_gate_x.resize($fl_gate_count)
    $fl_gate_z.resize($fl_gate_count)
    $fl_gate_y.resize($fl_gate_count)
    $fl_gate_heading.resize($fl_gate_count)
    $fl_gate_radius.resize($fl_gate_count)
    $fl_gate_phase.resize($fl_gate_count)
    $fl_gate_result.resize($fl_gate_count)
    for( $i = 0, $i < $fl_gate_count, $i += 1 ) {
        $fl_gate_result[$i] = 0
    }
    // A 7.4 km left circuit. Rounded corners can be flown at 25-35 degrees bank.
    // X negative is the left/west side of runway 00, Z 0..900m.
    // Upwind heights follow a full-power climb of about 600 fpm at 57 kt.
    $$fl_gate_set(0,       0,   75000,  4500,    0, 6000, 1)
    $$fl_gate_set(1,       0,  120000, 10000,    0, 9000, 1)
    $$fl_gate_set(2,  -15000,  145000, 13000, 3150, 9000, 2)
    $$fl_gate_set(3,  -45000,  150000, 15000, 2700, 9000, 2)
    $$fl_gate_set(4,  -75000,  150000, 15000, 2700, 9000, 2)
    $$fl_gate_set(5, -100000,  135000, 15000, 2250, 9000, 3)
    $$fl_gate_set(6, -110000,  105000, 15000, 1800, 9000, 3)
    $$fl_gate_set(7, -110000,   60000, 15000, 1800, 9000, 3)
    $$fl_gate_set(8, -110000,   10000, 15000, 1800, 9000, 3)
    $$fl_gate_set(9, -110000,  -40000, 15000, 1800, 9000, 3)
    $$fl_gate_set(10,-110000,  -90000, 14000, 1800, 9000, 3)
    $$fl_gate_set(11, -95000, -115000, 13000, 1350, 9000, 4)
    $$fl_gate_set(12, -65000, -125000, 12000,  900, 9000, 4)
    $$fl_gate_set(13, -35000, -125000, 11000,  900, 9000, 4)
    $$fl_gate_set(14, -10000, -110000,  9500,  450, 8000, 5)
    $$fl_gate_set(15,      0,  -85000,  8000,    0, 7000, 5)
    $$fl_gate_set(16,      0,  -55000,  5500,    0, 6000, 5)
    $$fl_gate_set(17,      0,  -25000,  3000,    0, 5000, 5)
    $$fl_gate_set(18,      0,       0,  1500,    0, 4000, 5)
}

// A forward segment-plane crossing is scored once at the actual intersection.
// Crossing outside the ring is a miss, but advances the target rather than trapping play.
command $$fl_check_gates(property $px, property $pz, property $py)
{
    property $i
    property $sn
    property $cs
    property $before
    property $after
    property $den
    property $ix
    property $iz
    property $iy
    property $side
    property $height
    property $r
    property $d2
    property $r2
    $i = $fl_gate_index
    if( $i >= $fl_gate_count || $fl_airborne == 0 || $fl_touched ) { return }
    $sn = math.sin($fl_gate_heading[$i], 1000)
    $cs = math.cos($fl_gate_heading[$i], 1000)
    $before = (($px - $fl_gate_x[$i]) * $sn + ($pz - $fl_gate_z[$i]) * $cs) / 1000
    $after = (($fl_x - $fl_gate_x[$i]) * $sn + ($fl_z - $fl_gate_z[$i]) * $cs) / 1000
    if( $before > 0 || $after <= 0 ) { return }
    $den = $after - $before
    if( $den <= 0 ) { return }
    $ix = $px + ($fl_x - $px) * (0 - $before) / $den
    $iz = $pz + ($fl_z - $pz) * (0 - $before) / $den
    $iy = $py + ($fl_alt - $py) * (0 - $before) / $den
    // Square metre precision avoids overflow at centimetre scale.
    $side = (($ix - $fl_gate_x[$i]) * $cs - ($iz - $fl_gate_z[$i]) * $sn) / 100000
    $height = ($iy - $fl_gate_y[$i]) / 100
    $r = $fl_gate_radius[$i] / 100
    $r2 = $r * $r
    if( math.abs($side) > $r || math.abs($height) > $r ) {
        $d2 = $r2 + 1
    } else {
        $d2 = $side * $side + $height * $height
    }
    if( $d2 <= $r2 && $iy > 0 ) {
        $fl_last_precision = ($r2 - $d2) * 100 / $r2
        // 19 frames share 50 points (5000 hundredths).
        $fl_gate_points += ($r2 - $d2) * 5000 / ($r2 * 19)
        $fl_gate_result[$i] = 2
        if( $fl_last_precision >= 75 ) { $fl_gate_result[$i] = 1 }
        $fl_gate_hits += 1
    } else {
        $fl_last_precision = 0
        $fl_gate_result[$i] = 3
        $fl_gate_misses += 1
    }
    $fl_gate_index += 1
    $fl_gate_event += 1
    if( $fl_gate_index < $fl_gate_count ) {
        $fl_phase = $fl_gate_phase[$fl_gate_index]
    } else {
        $fl_phase = 5
    }
    $fl_total = $fl_gate_points / 100
}

command $$fl_touchdown
{
    property $sink
    property $hdg
    if( $fl_touched ) { return }
    $fl_touched = 1
    $fl_touch_fpm = $fl_vspeed * 19685 / 10000
    $fl_touch_speed = $fl_speed
    $fl_touch_roll = $fl_roll
    $fl_touch_x = $fl_x
    $fl_touch_z = $fl_z
    $fl_alt = 0
    $fl_vspeed = 0
    $fl_gamma = 0
    $fl_gamma_rem = 0
    $fl_alt_rem = 0
    $fl_stall = 0
    $sink = math.abs($fl_touch_fpm)
    $hdg = $fl_heading
    if( $hdg > 1800 ) { $hdg -= 3600 }
    if( math.abs($fl_x) > 3000 || $fl_z < 0 || $fl_z > 90000 || math.abs($hdg) > 250 ) {
        $fl_fail_reason = 1
        $fl_state = 4
        return
    }
    if( $sink > 1000 || math.abs($fl_roll) > 180 || $fl_pitch < -60 || $fl_speed > 4800 ) {
        $fl_fail_reason = 2
        $fl_state = 4
        return
    }
    // Geography and net left heading prevent a takeoff/straight-in shortcut or right circuit.
    if( $fl_gate_index < $fl_gate_count || $fl_route_mask != 7 || $fl_turn_total > -2700 || $fl_max_alt < 8000 ) {
        $fl_fail_reason = 3
        $fl_state = 4
        return
    }
    // Softness 30: full at 90 fpm or less, none at 900 fpm.
    $fl_landing_points = $$fl_clamp((900 - $sink) * 3000 / 810, 0, 3000)
    // Centreline 10: full within 0.5 m, none from 8 m off.
    $fl_center_points = $$fl_clamp((800 - math.abs($fl_x)) * 1000 / 750, 0, 1000)
    // Aim point 10: along the runway, full within 5 m, none from 75 m early or late.
    $fl_aim_points = $$fl_clamp((7500 - math.abs($fl_z - 22000)) * 1000 / 7000, 0, 1000)
    $fl_total = ($fl_gate_points + $fl_landing_points + $fl_center_points + $fl_aim_points) / 100
    $fl_phase = 6
    $fl_landing_ticks = 0
}

command $$fl_sim_step
{
    property $px
    property $pz
    property $py
    property $grounded
    property $q
    property $eff
    property $rate
    property $gt
    property $aoa
    property $cl
    property $cd
    property $h
    property $t
    property $ge
    property $lift
    property $drag
    property $thrust
    property $sa
    property $ca
    property $sg
    property $cg
    property $sr
    property $cr
    property $acc
    property $net
    property $vc
    property $vh
    property $vs
    property $d
    if( $fl_state != 1 ) { return }
    $px = $fl_x
    $pz = $fl_z
    $py = $fl_alt
    $fl_step_ticks += 1
    $fl_elapsed_ms += 20
    // Exactly 25 percent/second, independent of display frame rate.
    $fl_throttle = $$fl_clamp($fl_throttle + $fl_in_throttle * 5, 0, 1000)
    $grounded = ($fl_airborne == 0 || $fl_touched)
    // Dynamic pressure, V*V/1000; 50 kt (2572 cm/s) gives 6615.
    $q = $fl_speed * $fl_speed / 1000

    // Keys command pitch/roll rate. Control authority follows the airflow.
    if( $grounded ) {
        // On the grass the elevator can lift the nose only from about 25 kt; when
        // released the nose settles, slowly once the tail is flying.
        $eff = $$fl_clamp(($fl_speed - 1300) * 1000 / 1300, 0, 1000)
        $rate = $fl_in_pitch * 240 * $eff / 1000
        if( $fl_in_pitch == 0 && $fl_pitch > 0 ) { $rate = 0 - 20 - 80 * (1000 - $eff) / 1000 }
        $fl_pitch_rem += $rate
        $d = $fl_pitch_rem / 100
        $fl_pitch = $$fl_clamp($fl_pitch + $d, 0, 110)
        $fl_pitch_rem -= $d * 100
        $fl_roll = 0
        $fl_roll_rem = 0
        // Tailwheel steering eases in over a quarter second, and its turn rate grows with
        // speed: about 1 deg/s standing still to 8 deg/s from 20 kt (1029 cm/s).
        $fl_steer += $$fl_clamp($fl_in_roll * 100 - $fl_steer, -8, 8)
        $fl_steer_rem += $fl_steer * (10 + 70 * $$fl_clamp($fl_speed, 0, 1029) / 1029) / 100
        $d = $fl_steer_rem / 50
        $fl_heading += $d
        $fl_steer_rem -= $d * 50
    } else {
        $eff = $$fl_clamp($q * 1000 / 6615, 350, 1000)
        // Static stability trims towards 7 degrees angle of attack (about 57 kt);
        // past the critical angle the nose drops however hard the pilot pulls.
        $rate = $fl_in_pitch * 240 * $eff / 1000 + $$fl_clamp((70 - $fl_aoa) * 3 / 10, -30, 30)
        if( $fl_aoa > 144 ) { $rate -= 60 + ($fl_aoa - 144) * 20 }
        $fl_pitch_rem += $rate
        $d = $fl_pitch_rem / 100
        $fl_pitch = $$fl_clamp($fl_pitch + $d, -300, 300)
        $fl_pitch_rem -= $d * 100
        // Ailerons roll at up to 30 deg/s; dihedral slowly levels released wings.
        $fl_steer = 0
        $fl_steer_rem = 0
        $rate = $fl_in_roll * 600 * $eff / 1000
        if( $fl_in_roll == 0 ) { $rate = $$fl_clamp(0 - $fl_roll * 2, -30, 30) }
        $fl_roll_rem += $rate
        $d = $fl_roll_rem / 100
        $fl_roll = $$fl_clamp($fl_roll + $d, -600, 600)
        $fl_roll_rem -= $d * 100
    }
    $fl_heading = ($fl_heading + 3600) % 3600

    // Angle of attack = pitch + 3 degree wing incidence - flight-path angle.
    $gt = $fl_gamma / 100
    $aoa = $fl_pitch + 30 - $gt
    $fl_aoa = $aoa
    // Lift curve: CL 0.25 at zero, 0.08 per degree, CLmax 1.40 at 14.4 degrees,
    // then a sharp stall break. Stall: 44 kt level, 47 kt at 30, 52 kt at 45 bank.
    if( $aoa <= 144 ) {
        $cl = 250 + $aoa * 8
        if( $cl < -700 ) { $cl = -700 }
    } else {
        $cl = 1402 - ($aoa - 144) * 30
        if( $cl < 800 ) { $cl = 800 }
    }
    // Ground effect within one span (9.8 m) of the grass cuts induced drag.
    $h = $$fl_clamp($fl_alt + 150, 0, 2000)
    $t = $h * 16000 / 980
    $t = $t * $t / 1000
    $ge = $t * 1000 / (1000 + $t)
    // Drag polar: CD = 0.050 + 0.066 CL^2; L/D about 8.7 at 57 kt.
    $cd = 50 + $cl * $cl / 1000 * 66 * $ge / 1000000
    if( $aoa > 144 ) { $cd += ($aoa - 144) * 4 }
    // 0.5 * rho * S / m gives 1/7294 in these units.
    $lift = $q * $cl / 7294
    $drag = $q * $cd / 7294
    // Fixed-pitch propeller: thrust falls with airspeed; a windmilling prop drags.
    $thrust = $fl_throttle * (320 - $fl_speed * 356 / 10000) / 1000 - (1000 - $fl_throttle) * $fl_speed / 300000
    $fl_lift = $lift
    $sa = math.sin($aoa, 1000)
    $ca = math.cos($aoa, 1000)

    if( $grounded ) {
        // Grass rolling friction (mu 0.10) on the weight the wings do not carry; after
        // touchdown B adds the wheel brakes (mu 0.35 more on grass).
        $acc = $thrust * $ca / 1000 - $drag - $$fl_clamp(981 - $lift, 0, 981) / 10
        if( $fl_touched && $fl_in_brake ) { $acc -= $$fl_clamp(981 - $lift, 0, 981) * 35 / 100 }
        $fl_gamma = 0
        $fl_gamma_rem = 0
        $fl_vspeed = 0
        $fl_alt = 0
        $fl_alt_rem = 0
        $fl_stall = 0
        if( $fl_touched == 0 && $lift >= 981 ) {
            $fl_airborne = 1
            if( $fl_phase == 0 ) { $fl_phase = 1 }
            $fl_alt = 1
        }
    } else {
        $sg = math.sin($gt, 1000)
        $cg = math.cos($gt, 1000)
        $sr = math.sin($fl_roll, 1000)
        $cr = math.cos($fl_roll, 1000)
        $acc = $thrust * $ca / 1000 - $drag - 981 * $sg / 1000
        // Flight path bends with the vertical lift component; banking costs lift.
        $vc = $fl_speed
        if( $vc < 1000 ) { $vc = 1000 }
        $net = $lift * $cr / 1000 + $thrust * $sa / 1000 - 981 * $cg / 1000
        $fl_gamma_rem += $net * 11459 / 10
        $d = $fl_gamma_rem / $vc
        $fl_gamma = $$fl_clamp($fl_gamma + $d, -85000, 85000)
        $fl_gamma_rem -= $d * $vc
        // Coordinated turn: horizontal lift component, rate = g tan(bank) / V level.
        $vh = $fl_speed * $cg / 1000
        if( $vh < 1000 ) { $vh = 1000 }
        $fl_turn_rem += $lift * $sr / 1000 * 11459 / 1000
        $d = $fl_turn_rem / $vh
        $fl_turn_rem -= $d * $vh
        $fl_heading = ($fl_heading + $d + 3600) % 3600
        $fl_turn_total += $d
        $fl_stall = 0
        if( $aoa >= 124 ) { $fl_stall = 1 }
        if( $aoa > 144 ) { $fl_stall = 2 }
    }
    $fl_speed_rem += $acc
    $d = $fl_speed_rem / 50
    $fl_speed_rem -= $d * 50
    $fl_speed += $d
    if( $fl_speed < 0 || $fl_speed > 7500 ) {
        $fl_speed = $$fl_clamp($fl_speed, 0, 7500)
        $fl_speed_rem = 0
    }

    $gt = $fl_gamma / 100
    $vh = $fl_speed * math.cos($gt, 1000) / 1000
    $fl_x_rem += math.sin($fl_heading, $vh)
    $d = $fl_x_rem / 50
    $fl_x += $d
    $fl_x_rem -= $d * 50
    $fl_z_rem += math.cos($fl_heading, $vh)
    $d = $fl_z_rem / 50
    $fl_z += $d
    $fl_z_rem -= $d * 50
    if( $fl_airborne && $fl_touched == 0 ) {
        $vs = $fl_speed * math.sin($gt, 1000) / 1000
        $fl_vspeed = $vs
        $fl_alt_rem += $vs
        $d = $fl_alt_rem / 50
        $fl_alt += $d
        $fl_alt_rem -= $d * 50
        if( $fl_alt > $fl_max_alt ) { $fl_max_alt = $fl_alt }
    }
    if( $fl_x < -60000 && $fl_z > 80000 ) { $fl_route_mask = $fl_route_mask | 1 }
    if( $fl_x < -60000 && $fl_z < -70000 ) { $fl_route_mask = $fl_route_mask | 2 }
    if( $fl_x > -30000 && $fl_z < -70000 ) { $fl_route_mask = $fl_route_mask | 4 }
    $$fl_check_gates($px, $pz, $py)
    if( $fl_airborne && $fl_touched == 0 && $fl_alt <= 0 ) {
        if( $fl_max_alt < 300 ) {
            // Settling back within 3 m of lift-off is still the takeoff roll.
            $fl_airborne = 0
            $fl_alt = 0
            $fl_alt_rem = 0
            $fl_vspeed = 0
            $fl_gamma = 0
            $fl_gamma_rem = 0
        } else {
            $$fl_touchdown
        }
    }
    if( $fl_state != 1 ) { return }
    if( $fl_touched ) {
        $fl_landing_ticks += 1
        if( math.abs($fl_x) > 3000 || $fl_z > 90000 || $fl_z < 0 ) {
            $fl_fail_reason = 1
            $fl_state = 4
            return
        }
        if( $fl_speed <= 100 ) {
            $fl_speed = 0
            $fl_state = 3
        }
    }
    if( $fl_airborne == 0 && (math.abs($fl_x) > 3000 || $fl_z > 90000 || $fl_z < 0) ) {
        $fl_fail_reason = 6
        $fl_state = 4
    }
    if( math.abs($fl_x) > 600000 || math.abs($fl_z) > 600000 || $fl_alt > 60000 ) {
        $fl_fail_reason = 4
        $fl_state = 4
    }
    if( $fl_elapsed_ms >= 720000 ) {
        $fl_fail_reason = 5
        $fl_state = 4
    }
}
