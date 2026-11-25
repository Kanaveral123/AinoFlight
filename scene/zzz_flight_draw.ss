// Native Siglus first-person renderer. Existing sky and cockpit art; no external window.
// World lengths are centimetres. Angles use the engine's 3600-units-per-turn convention.
// Landmarks are cut from the game's own background paintings (FL_lm_*, built by
// tools/prepare_flight_landmarks.py). North (+Z) of the field lies the coast and sea.
#inc_start
	#define $fl_d_root front.object[<OBJ_APP_EFFECT01>]
	#property $fl_d_cam_x
	#property $fl_d_cam_y
	#property $fl_d_cam_z
	#property $fl_d_screen_x
	#property $fl_d_screen_y
	#property $fl_d_cos_h
	#property $fl_d_sin_h
	#property $fl_d_cos_p
	#property $fl_d_sin_p
	#property $fl_d_cos_r
	#property $fl_d_sin_r
	#property $fl_d_hud_time
	#property $fl_d_state
	#property $fl_d_speech_serial
	#property $fl_d_button_action : intlist
	#property $fl_d_button_x : intlist
	#property $fl_d_gyro_pitch
	#property $fl_d_gyro_roll
	#property $fl_d_lm_count
	#property $fl_d_lm_x : intlist
	#property $fl_d_lm_z : intlist
	#property $fl_d_lm_h : intlist
	#property $fl_d_lm_ph : intlist
	#property $fl_d_map_x
	#property $fl_d_map_y
	#property $fl_d_gate_seen
	#property $fl_d_toast_until
	#property $fl_d_centered
	#property $fl_d_ax
	#property $fl_d_ay
	#property $fl_d_az
	#property $fl_d_bx
	#property $fl_d_by
	#property $fl_d_bz
	#property $fl_d_px16
	#property $fl_d_py16
	#property $fl_d_touch_seen
	#property $fl_d_ce_a
	#property $fl_d_ce_n
	#property $fl_d_ce_l
	#property $fl_d_ce_d
	#property $fl_d_cl_a
	#property $fl_d_cl_n
	#property $fl_d_cl_px
	#property $fl_d_cl_py
	#property $fl_d_cb_a
	#property $fl_d_cb_n
	#property $fl_d_cb_px
	#property $fl_d_cb_py
	#property $fl_d_rc_x
	#property $fl_d_rc_y
	#property $fl_d_rc_dx
	#property $fl_d_rc_dy
	#property $fl_d_rc_t
	#property $fl_d_last_ms
	#property $fl_d_rc_axis : intlist
	#property $fl_d_kx
	#property $fl_d_ky
	#property $fl_d_kz
	#property $fl_d_rg_mode
	#property $fl_d_rg_x
	#property $fl_d_rg_y
	#property $fl_d_rg_dx
	#property $fl_d_rg_dy
	#command $$fl_d_gyro_init
	#command $$fl_d_gyro_frame
#inc_end

#z00
return

command $$fl_d_clamp(property $value, property $low, property $high) : int
{
	if( $value < $low ) { return ($low) }
	if( $value > $high ) { return ($high) }
	return ($value)
}

command $$fl_d_text(property $obj : object, property $text : str, property $x, property $y, property $size, property $color)
{
	$obj.create_string($text, 1, $x, $y)
	$obj.set_string_param($size, 0, 0, 100, $color, 1, 1)
}

// Latin text placed letter by letter. The engine gives every half-width letter the same
// cell, which leaves gaps after narrow letters ("Ai no's"); here each letter advances by
// its own approximate width (hundredths of the font size).
command $$fl_d_kern_text(property $obj : object, property $text : str, property $x, property $y, property $size, property $color)
{
	property $i
	property $c
	property $w
	$obj.disp = 1
	$obj.child.resize($text.len)
	for( $i = 0, $i < $text.len, $i += 1 ) {
		$obj.child[$i].create_string($text.mid($i, 1), 1, $x, $y)
		$obj.child[$i].set_string_param($size, 0, 0, 100, $color, 0, 0)
		$c = $text.get_code($i)
		$w = 54
		if( $c >= 65 && $c <= 90 ) { $w = 62 }
		if( $c == 115 || $c == 99 ) { $w = 48 }
		if( $c == 102 || $c == 116 || $c == 114 || $c == 106 ) { $w = 36 }
		if( $c == 105 || $c == 108 || $c == 39 || $c == 46 || $c == 32 || $c == 73 ) { $w = 27 }
		if( $c == 109 || $c == 119 ) { $w = 82 }
		$x += $size * $w / 100
	}
}

// Panel text on the light dialog art: no shadow or outline.
command $$fl_d_panel_text(property $obj : object, property $x, property $y, property $size, property $color)
{
	$obj.create_string("", 1, $x, $y)
	$obj.set_string_param($size, 0, 0, 100, $color, 0, 0)
}

// String objects report no pixel size; like the game's own macros, width is the
// half-width length times half the font size.
command $$fl_d_center_text(property $obj : object, property $text : str, property $cx, property $y, property $size)
{
	$obj.set_string($text)
	$obj.set_pos($cx - $text.len * $size / 4, $y)
}

// Base line has a 100 x 2 pixel texture and its origin at its first endpoint.
command $$fl_d_line_init(property $obj : object)
{
	$obj.create_rect(0, 0, 100, 2, 255, 255, 255, 255, 1)
	$obj.disp = 0
}

command $$fl_d_line2(property $obj : object, property $x1, property $y1, property $x2, property $y2, property $width, property $r, property $g, property $b)
{
	property $length
	$obj.disp = 0
	if( ($x1 < -20 && $x2 < -20) || ($x1 > 1940 && $x2 > 1940) || ($y1 < -20 && $y2 < -20) || ($y1 > 1100 && $y2 > 1100) ) { return }
	// Bound invisible endpoints before distance/angle to keep integer arithmetic safe.
	$x1 = $$fl_d_clamp($x1, -2048, 3968)
	$x2 = $$fl_d_clamp($x2, -2048, 3968)
	$y1 = $$fl_d_clamp($y1, -1500, 2580)
	$y2 = $$fl_d_clamp($y2, -1500, 2580)
	$length = math.distance($x1, $y1, $x2, $y2)
	if( $length < 1 ) { return }
	if( $fl_d_centered ) {
		// Wide ground strips straddle their centre line instead of growing to one side.
		$obj.set_pos($x1 + ($y2 - $y1) * $width / 2 / $length, $y1 - ($x2 - $x1) * $width / 2 / $length)
	} else {
		$obj.set_pos($x1, $y1)
	}
	$obj.set_scale($length * 10, $width * 500)
	$obj.rotate_z = math.angle($x1, $y1, $x2, $y2)
	$obj.color_r = $r
	$obj.color_g = $g
	$obj.color_b = $b
	$obj.color_rate = 255
	$obj.disp = 1
}

// World -> camera; camera height is 1.5m above the landing-gear ground plane.
command $$fl_d_camera(property $wx, property $wy, property $wz)
{
	property $dx
	property $dy
	property $dz
	property $forward
	$dx = $wx - $fl_x
	$dy = $wy - $fl_alt - 150
	$dz = $wz - $fl_z
	$fl_d_cam_x = ($dx * $fl_d_cos_h - $dz * $fl_d_sin_h) / 1000
	$forward = ($dx * $fl_d_sin_h + $dz * $fl_d_cos_h) / 1000
	$fl_d_cam_y = ($dy * $fl_d_cos_p - $forward * $fl_d_sin_p) / 1000
	$fl_d_cam_z = ($dy * $fl_d_sin_p + $forward * $fl_d_cos_p) / 1000
}

command $$fl_d_screen(property $cx, property $cy, property $cz)
{
	property $x
	property $y
	$x = $cx * 850 / $cz
	$y = 0 - $cy * 850 / $cz
	$fl_d_screen_x = 960 + ($x * $fl_d_cos_r + $y * $fl_d_sin_r) / 1000
	$fl_d_screen_y = 395 + ($y * $fl_d_cos_r - $x * $fl_d_sin_r) / 1000
}

// Signed distance-like value of a camera-space point to one clip plane; >= 0 inside.
// 0: 5 m near plane. 1-4: a view cone 1300 px around the screen centre (26/17 of the
// focal 850), wider than any rolled screen corner.
command $$fl_d_plane(property $i, property $x, property $y, property $z) : int
{
	if( $i == 0 ) { return ($z - 500) }
	if( $i == 1 ) { return ($z * 26 + $x * 17) }
	if( $i == 2 ) { return ($z * 26 - $x * 17) }
	if( $i == 3 ) { return ($z * 26 + $y * 17) }
	return ($z * 26 - $y * 17)
}

// Clips a world segment in camera space to the near plane and view cone, leaving it in
// $fl_d_ax..$fl_d_bz. Clipping before projection keeps both endpoints near the screen,
// so a line never needs its endpoints clamped and keeps its true direction.
command $$fl_d_clip3(property $x1, property $y1, property $z1, property $x2, property $y2, property $z2) : int
{
	property $i
	property $fa
	property $fb
	property $r
	$$fl_d_camera($x1, $y1, $z1)
	$fl_d_ax = $fl_d_cam_x
	$fl_d_ay = $fl_d_cam_y
	$fl_d_az = $fl_d_cam_z
	$$fl_d_camera($x2, $y2, $z2)
	$fl_d_bx = $fl_d_cam_x
	$fl_d_by = $fl_d_cam_y
	$fl_d_bz = $fl_d_cam_z
	for( $i = 0, $i < 5, $i += 1 ) {
		$fa = $$fl_d_plane($i, $fl_d_ax, $fl_d_ay, $fl_d_az)
		$fb = $$fl_d_plane($i, $fl_d_bx, $fl_d_by, $fl_d_bz)
		if( $fa < 0 && $fb < 0 ) { return (0) }
		if( $fa < 0 ) {
			$$fl_d_cross($i, $fl_d_ax, $fl_d_ay, $fl_d_az, $fl_d_bx, $fl_d_by, $fl_d_bz, $fa, $fb)
			$fl_d_ax = $fl_d_kx
			$fl_d_ay = $fl_d_ky
			$fl_d_az = $fl_d_kz
		}
		if( $fb < 0 ) {
			$$fl_d_cross($i, $fl_d_bx, $fl_d_by, $fl_d_bz, $fl_d_ax, $fl_d_ay, $fl_d_az, $fb, $fa)
			$fl_d_bx = $fl_d_kx
			$fl_d_by = $fl_d_ky
			$fl_d_bz = $fl_d_kz
		}
	}
	return (1)
}

// Where the segment from outside point O (plane value $fo < 0) to inside point I meets
// clip plane $i, into $fl_d_kx..kz, staying on the segment to about a centimetre. A
// first step finds the thousandth of the segment that holds the crossing; a second step
// splits that thousandth again, so long lines are cut precisely too.
command $$fl_d_cross(property $i, property $ox, property $oy, property $oz, property $ix, property $iy, property $iz, property $fo, property $fi)
{
	property $r
	property $f1
	property $f2
	property $px
	property $py
	property $pz
	property $qx
	property $qy
	property $qz
	if( math.abs($fo) > 2000000 || math.abs($fi) > 2000000 ) {
		$fo = $fo / 32
		$fi = $fi / 32
	}
	$r = $fo * 1000 / ($fo - $fi)
	$px = $ox + $$fl_d_part($ix - $ox, $r)
	$py = $oy + $$fl_d_part($iy - $oy, $r)
	$pz = $oz + $$fl_d_part($iz - $oz, $r)
	$qx = $ox + $$fl_d_part($ix - $ox, $r + 1)
	$qy = $oy + $$fl_d_part($iy - $oy, $r + 1)
	$qz = $oz + $$fl_d_part($iz - $oz, $r + 1)
	$f1 = $$fl_d_plane($i, $px, $py, $pz)
	$f2 = $$fl_d_plane($i, $qx, $qy, $qz)
	$fl_d_kx = $qx
	$fl_d_ky = $qy
	$fl_d_kz = $qz
	if( $f1 >= 0 ) {
		$fl_d_kx = $px
		$fl_d_ky = $py
		$fl_d_kz = $pz
	}
	if( $f1 < 0 && $f2 > $f1 ) {
		// Round towards the inside end so the point is never left outside the plane.
		$r = ((0 - $f1) * 1000 + ($f2 - $f1) - 1) / ($f2 - $f1)
		$fl_d_kx = $px + ($qx - $px) * $r / 1000
		$fl_d_ky = $py + ($qy - $py) * $r / 1000
		$fl_d_kz = $pz + ($qz - $pz) * $r / 1000
	}
	if( $i == 0 && $fl_d_kz < 500 ) { $fl_d_kz = 500 }
}

// $d * $r / 1000 without overflowing for |$d| up to about two million.
command $$fl_d_part(property $d, property $r) : int
{
	if( math.abs($d) < 2000000 ) { return ($d * $r / 1000) }
	return ($d / 10 * $r / 100)
}

command $$fl_d_line3(property $obj : object, property $x1, property $y1, property $z1, property $x2, property $y2, property $z2, property $width, property $r, property $g, property $b)
{
	property $sx
	property $sy
	$obj.disp = 0
	if( $$fl_d_clip3($x1, $y1, $z1, $x2, $y2, $z2) == 0 ) { return }
	$$fl_d_screen($fl_d_ax, $fl_d_ay, $fl_d_az)
	$sx = $fl_d_screen_x
	$sy = $fl_d_screen_y
	$$fl_d_screen($fl_d_bx, $fl_d_by, $fl_d_bz)
	$$fl_d_line2($obj, $sx, $sy, $fl_d_screen_x, $fl_d_screen_y, $width, $r, $g, $b)
}

// Unrolled screen position in 1/16 px (roll does not change a thickness).
command $$fl_d_proj16(property $cx, property $cy, property $cz)
{
	$fl_d_px16 = $$fl_d_clamp($cx * 1360 / ($cz / 10), -64000, 64000)
	$fl_d_py16 = $$fl_d_clamp(0 - $cy * 1360 / ($cz / 10), -64000, 64000)
}

// Screen thickness of a ground strip of world width $w, measured where it is actually
// seen: at the middle of the clipped, visible part of its centre line. The edges there
// are projected in 1/16 px and only their spread across the strip's own screen
// direction counts, so a 2-3 px strip seen edge-on cannot jump with pixel rounding.
command $$fl_d_strip_width(property $x1, property $z1, property $x2, property $z2, property $w) : int
{
	property $len
	property $ox
	property $oy
	property $oz
	property $px
	property $py
	property $pz
	property $ax
	property $ay
	property $bx
	property $by
	property $dx
	property $dy
	property $dl
	property $n
	$len = math.distance($x1 / 100, $z1 / 100, $x2 / 100, $z2 / 100)
	if( $len < 1 ) { return (0) }
	if( $$fl_d_clip3($x1, 5, $z1, $x2, 5, $z2) == 0 ) { return (0) }
	// Screen direction of the visible part, from its two clipped ends.
	$$fl_d_proj16($fl_d_ax, $fl_d_ay, $fl_d_az)
	$dx = $fl_d_px16
	$dy = $fl_d_py16
	$$fl_d_proj16($fl_d_bx, $fl_d_by, $fl_d_bz)
	$dx = $fl_d_px16 - $dx
	$dy = $fl_d_py16 - $dy
	$px = ($fl_d_ax + $fl_d_bx) / 2
	$py = ($fl_d_ay + $fl_d_by) / 2
	$pz = ($fl_d_az + $fl_d_bz) / 2
	// Half the strip width across it, turned into camera space (rotation only).
	$$fl_d_camera($fl_x + ($z1 - $z2) / 100 * $w / 2 / $len, $fl_alt + 150, $fl_z + ($x2 - $x1) / 100 * $w / 2 / $len)
	$ox = $fl_d_cam_x
	$oy = $fl_d_cam_y
	$oz = $fl_d_cam_z
	if( $pz - math.abs($oz) < 300 ) { return (2) }
	$$fl_d_proj16($px + $ox, $py + $oy, $pz + $oz)
	$ax = $fl_d_px16
	$ay = $fl_d_py16
	$$fl_d_proj16($px - $ox, $py - $oy, $pz - $oz)
	$bx = $fl_d_px16
	$by = $fl_d_py16
	for( $n = 0, $n < 8, $n += 1 ) {
		if( math.abs($dx) > 4000 || math.abs($dy) > 4000 ) {
			$dx = $dx / 2
			$dy = $dy / 2
		}
	}
	$dl = math.distance(0, 0, $dx, $dy)
	// A strip seen end-on as a dot has no direction: its full edge spread is the width.
	if( $dl < 32 ) { return ($$fl_d_clamp((math.distance($ax, $ay, $bx, $by) + 8) / 16, 1, 300)) }
	return ($$fl_d_clamp((math.abs(($bx - $ax) * $dy - ($by - $ay) * $dx) / $dl + 8) / 16, 1, 300))
}

// A ground strip (road, crop row) of world width $w, drawn centred on its line.
command $$fl_d_strip(property $obj : object, property $x1, property $z1, property $x2, property $z2, property $w, property $r, property $g, property $b)
{
	$obj.disp = 0
	if( math.abs(($x1 + $x2) / 2 - $fl_x) > 700000 || math.abs(($z1 + $z2) / 2 - $fl_z) > 700000 ) { return }
	$fl_d_centered = 1
	$$fl_d_line3($obj, $x1, 5, $z1, $x2, 5, $z2, $$fl_d_strip_width($x1, $z1, $x2, $z2, $w), $r, $g, $b)
	$fl_d_centered = 0
}

command $$fl_d_round16(property $v) : int
{
	if( $v >= 0 ) { return (($v + 8) / 16) }
	return (($v - 8) / 16)
}

// Edge of the ground beyond the east-west line Z = $line, in horizon space. The edge
// is the projected line's closest point to the horizon centre: 850 b / L along the
// unit normal (a, n) / L, where a = h sin(heading), b = h cos(heading) and n is the
// distance to the line. The result is scale-free in (h, n), so both are kept in
// centimetres and only halved together when they outgrow 32-bit arithmetic.
command $$fl_d_coast_edge(property $line)
{
	property $h
	property $n
	property $i
	$h = $$fl_d_clamp($fl_alt + 150, 150, 60000)
	$n = $$fl_d_clamp($line - $fl_z, -400000, 400000)
	for( $i = 0, $i < 5, $i += 1 ) {
		if( math.abs($n) > 30000 || $h > 30000 ) {
			$h = $h / 2
			$n = $n / 2
		}
	}
	if( $n == 0 ) { $n = 1 }
	$fl_d_ce_a = $h * $fl_d_sin_h / 1000
	$fl_d_ce_n = $n
	$fl_d_ce_l = math.distance(0, 0, $fl_d_ce_a, $n)
	if( $fl_d_ce_l < 1 ) { $fl_d_ce_l = 1 }
	// Beyond 3000 px the line leaves the screen on one side; the 6000 px fill still covers.
	$fl_d_ce_d = $$fl_d_round16($$fl_d_clamp(13600 * ($h * $fl_d_cos_h / 1000) / $fl_d_ce_l, -48000, 48000))
}

// Land (Z < 236000) and the 40 m beach beyond it. Seen from the circuit the beach is
// often under a pixel, so it is placed from the land edge along the same normal and
// kept at least one pixel wide instead of being rounded away and back each frame.
command $$fl_d_coast_calc
{
	property $t
	$$fl_d_coast_edge(236000)
	$fl_d_cl_a = $fl_d_ce_a
	$fl_d_cl_n = $fl_d_ce_n
	$fl_d_cl_px = $fl_d_ce_d * $fl_d_ce_a / $fl_d_ce_l
	$fl_d_cl_py = $fl_d_ce_d * $fl_d_ce_n / $fl_d_ce_l
	$t = $fl_d_ce_d
	$$fl_d_coast_edge(240000)
	$fl_d_cb_a = $fl_d_ce_a
	$fl_d_cb_n = $fl_d_ce_n
	$fl_d_cb_px = $fl_d_ce_d * $fl_d_ce_a / $fl_d_ce_l
	$fl_d_cb_py = $fl_d_ce_d * $fl_d_ce_n / $fl_d_ce_l
	if( $fl_d_cl_n > 0 && $fl_d_cb_n > 0 ) {
		$t = $t - $fl_d_ce_d
		if( $t < 1 && $t > -1 ) {
			$t = 1
			if( $fl_d_ce_d < 0 ) { $t = -1 }
		}
		$fl_d_cb_a = $fl_d_cl_a
		$fl_d_cb_n = $fl_d_cl_n
		$$fl_d_coast_edge(236000)
		// Unit normal in 1/256; the offset is then t px along it, rounded once.
		$fl_d_cb_px = $fl_d_cl_px - $$fl_d_round16($t * ($fl_d_ce_a * 256 / $fl_d_ce_l) / 16)
		$fl_d_cb_py = $fl_d_cl_py - $$fl_d_round16($t * ($fl_d_ce_n * 256 / $fl_d_ce_l) / 16)
	}
}

// Ground region on the $ix/$iz side of the world line ($x1,$z1)-($x2,$z2) (a long
// segment; only its visible part is used). The edge is the exact projection of the line,
// so regions meet the 3D-drawn edge lines at any distance and attitude. Mode 2 leaves the
// top-left corner of a 12000 x 6000 px rect lying along the edge (horizon space) and its
// direction; mode 1 means the visible ground is all inside, mode 0 all outside.
command $$fl_d_region_calc(property $x1, property $z1, property $x2, property $z2, property $ix, property $iz) : int
{
	property $ax
	property $ay
	property $bx
	property $by
	property $dx
	property $dy
	property $mx
	property $my
	property $mz
	property $tx
	property $ty
	property $tz
	property $cx
	property $cy
	property $sign
	property $len
	property $n
	$fl_d_rg_mode = 0
	if( $$fl_d_clip3($x1, 0, $z1, $x2, 0, $z2) ) {
		$mx = ($fl_d_ax + $fl_d_bx) / 2
		$my = ($fl_d_ay + $fl_d_by) / 2
		$mz = ($fl_d_az + $fl_d_bz) / 2
		$$fl_d_proj16($fl_d_ax, $fl_d_ay, $fl_d_az)
		$ax = $fl_d_px16
		$ay = $fl_d_py16
		$$fl_d_proj16($fl_d_bx, $fl_d_by, $fl_d_bz)
		$bx = $fl_d_px16
		$by = $fl_d_py16
		$dx = $bx - $ax
		$dy = $by - $ay
		if( math.abs($dx) + math.abs($dy) >= 32 ) {
			// Which side is inside: from the nearest visible point of the edge, step into
			// the region by a quarter of its distance (large enough to show on screen even
			// when foreshortened, small enough to stay in front) and see where it lands.
			$mx = $fl_d_ax
			$my = $fl_d_ay
			$mz = $fl_d_az
			$tx = $ax
			$ty = $ay
			if( $fl_d_bz < $fl_d_az ) {
				$mx = $fl_d_bx
				$my = $fl_d_by
				$mz = $fl_d_bz
				$tx = $bx
				$ty = $by
			}
			$$fl_d_camera($fl_x + $ix * ($mz / 4), $fl_alt + 150, $fl_z + $iz * ($mz / 4))
			$sign = 1
			$tz = $mz + $fl_d_cam_z
			if( $tz >= 300 ) {
				$$fl_d_proj16($mx + $fl_d_cam_x, $my + $fl_d_cam_y, $tz)
				$cx = $$fl_d_clamp($fl_d_px16 - $tx, -40000, 40000)
				$cy = $$fl_d_clamp($fl_d_py16 - $ty, -40000, 40000)
				for( $n = 0, $n < 8, $n += 1 ) {
					if( math.abs($dx) > 4000 || math.abs($dy) > 4000 ) {
						$dx = $dx / 2
						$dy = $dy / 2
					}
				}
				// The rect extends to the right of its direction; point that side inward.
				if( ($dx * $cy - $dy * $cx) * $sign < 0 ) {
					$dx = 0 - $dx
					$dy = 0 - $dy
				}
				$len = math.distance(0, 0, $dx, $dy)
				if( $len < 1 ) { $len = 1 }
				$fl_d_rg_x = ($ax + $bx) / 32 - $dx * 6000 / $len
				$fl_d_rg_y = ($ay + $by) / 32 - math.tan($fl_pitch, 850) - $dy * 6000 / $len
				$fl_d_rg_dx = $dx
				$fl_d_rg_dy = $dy
				$fl_d_rg_mode = 2
				return (2)
			}
		}
	}
	// Edge out of view: the ground 200 m ahead tells whether all of it is inside.
	$tx = $fl_x + math.sin($fl_heading, 20000)
	$tz = $fl_z + math.cos($fl_heading, 20000)
	if( ($tx - $x1) * $ix + ($tz - $z1) * $iz > 0 ) { $fl_d_rg_mode = 1 }
	return ($fl_d_rg_mode)
}

command $$fl_d_region(property $obj : object, property $x1, property $z1, property $x2, property $z2, property $ix, property $iz)
{
	$obj.disp = 0
	$$fl_d_region_calc($x1, $z1, $x2, $z2, $ix, $iz)
	if( $fl_d_rg_mode == 2 ) {
		$obj.set_pos($fl_d_rg_x, $fl_d_rg_y)
		$obj.rotate_z = math.angle(0, 0, $fl_d_rg_dx, $fl_d_rg_dy)
		$obj.disp = 1
	}
	if( $fl_d_rg_mode == 1 ) {
		$obj.set_pos(-6000, -3000)
		$obj.rotate_z = 0
		$obj.disp = 1
	}
}

// Ground half-plane through edge point ($px, $py) with normal ($a, $n), laid in horizon
// space; the sky drawn afterwards hides any overhang. It paints the camera side of
// Z = line (n > 0); negating a and n paints the far side instead.
command $$fl_d_halfplane(property $obj : object, property $px, property $py, property $a, property $n)
{
	property $dx
	property $dy
	property $len
	property $ux
	property $uy
	// Direction along the edge, pointing to screen right.
	$dx = $n
	$dy = 0 - $a
	if( $n < 0 ) {
		$dx = 0 - $n
		$dy = $a
	}
	$len = math.distance(0, 0, $dx, $dy)
	if( $len < 1 ) { $len = 1 }
	$ux = $dx * 6000 / $len
	$uy = $dy * 6000 / $len
	$px -= $ux
	$py -= $uy
	// Beyond the camera's side of the line the land is painted on the far side.
	if( $n < 0 ) {
		$px += $uy
		$py -= $ux
	}
	$obj.set_pos($px, $py)
	$obj.rotate_z = math.angle(0, 0, $dx, $dy)
	$obj.disp = 1
}

// A flat ground rectangle (runway marking) of length ($x1,$z1)-($x2,$z2) and world width
// $w, projected at 1/16 px. It is drawn along whichever of its two sides is longer on
// screen, with the other side's extent across it as thickness, so a short marking far
// away becomes a flat bar instead of a thick stub whose angle swings with pixel rounding.
// Leaves the centre, half main axis (both rolled screen 1/16 px) and thickness. A nearly
// square marking keeps the axis it had ($slot remembers it) until the other side is a
// quarter longer, so it cannot flip back and forth between frames.
command $$fl_d_rect_calc(property $slot, property $x1, property $z1, property $x2, property $z2, property $w) : int
{
	property $len
	property $ax
	property $ay
	property $bx
	property $by
	property $mx
	property $my
	property $mz
	property $ox
	property $oy
	property $oz
	property $px
	property $py
	property $qx
	property $qy
	property $lx
	property $ly
	property $wx
	property $wy
	property $cx
	property $cy
	property $ux
	property $uy
	property $vx
	property $vy
	property $ul
	property $vl
	$len = math.distance($x1 / 100, $z1 / 100, $x2 / 100, $z2 / 100)
	if( $len < 1 ) { return (0) }
	if( $$fl_d_clip3($x1, 10, $z1, $x2, 10, $z2) == 0 ) { return (0) }
	$mx = ($fl_d_ax + $fl_d_bx) / 2
	$my = ($fl_d_ay + $fl_d_by) / 2
	$mz = ($fl_d_az + $fl_d_bz) / 2
	$$fl_d_proj16($fl_d_ax, $fl_d_ay, $fl_d_az)
	$ax = $fl_d_px16
	$ay = $fl_d_py16
	$$fl_d_proj16($fl_d_bx, $fl_d_by, $fl_d_bz)
	$bx = $fl_d_px16
	$by = $fl_d_py16
	// Half the width across the rectangle, turned into camera space (rotation only).
	$$fl_d_camera($fl_x + ($z1 - $z2) / 100 * $w / 2 / $len, $fl_alt + 150, $fl_z + ($x2 - $x1) / 100 * $w / 2 / $len)
	$ox = $fl_d_cam_x
	$oy = $fl_d_cam_y
	$oz = $fl_d_cam_z
	if( $mz - math.abs($oz) < 300 ) { return (0) }
	$$fl_d_proj16($mx + $ox, $my + $oy, $mz + $oz)
	$px = $fl_d_px16
	$py = $fl_d_py16
	$$fl_d_proj16($mx - $ox, $my - $oy, $mz - $oz)
	$qx = $fl_d_px16
	$qy = $fl_d_py16
	$lx = $bx - $ax
	$ly = $by - $ay
	$wx = $px - $qx
	$wy = $py - $qy
	// Main axis u (drawn), other axis v (thickness).
	$ux = $lx
	$uy = $ly
	$vx = $wx
	$vy = $wy
	$cx = ($ax + $bx) / 2
	$cy = ($ay + $by) / 2
	$ul = math.distance(0, 0, $lx / 8, $ly / 8)
	$vl = math.distance(0, 0, $wx / 8, $wy / 8)
	if( $fl_d_rc_axis[$slot] == 0 && $vl * 4 > $ul * 5 ) { $fl_d_rc_axis[$slot] = 1 }
	if( $fl_d_rc_axis[$slot] == 1 && $ul * 4 > $vl * 5 ) { $fl_d_rc_axis[$slot] = 0 }
	if( $fl_d_rc_axis[$slot] == 1 ) {
		$ux = $wx
		$uy = $wy
		$vx = $lx
		$vy = $ly
		$cx = ($px + $qx) / 2
		$cy = ($py + $qy) / 2
		$ul = $vl
	}
	// Up close perspective puts the far half of a marking in far fewer pixels than the
	// near half, so the bar is centred between the other axis' projected ends, not on
	// the main axis line.
	if( $fl_d_rc_axis[$slot] == 1 ) {
		$mx = ($ax + $bx) / 2 - $cx
		$my = ($ay + $by) / 2 - $cy
	} else {
		$mx = ($px + $qx) / 2 - $cx
		$my = ($py + $qy) / 2 - $cy
	}
	if( $ul >= 2 ) {
		// Offset of that midpoint across the main axis (1/16 px), then move there.
		$mx = $$fl_d_clamp($mx, -40000, 40000)
		$my = $$fl_d_clamp($my, -40000, 40000)
		$mz = (($ux / 8) * ($my / 8) - ($uy / 8) * ($mx / 8)) * 8 / $ul
		$cx = $cx - ($uy / 8) * $mz / $ul
		$cy = $cy + ($ux / 8) * $mz / $ul
	}
	$vx = $$fl_d_clamp($vx, -40000, 40000)
	$vy = $$fl_d_clamp($vy, -40000, 40000)
	if( $ul < 2 ) {
		// Under a pixel each way: a one-pixel dot.
		$ux = 16
		$uy = 0
		$fl_d_rc_t = 16
	} else {
		$fl_d_rc_t = math.abs($ux / 8 * $vy - $uy / 8 * $vx) / $ul
	}
	$fl_d_rc_x = 15360 + ($cx * $fl_d_cos_r + $cy * $fl_d_sin_r) / 1000
	$fl_d_rc_y = 6320 + ($cy * $fl_d_cos_r - $cx * $fl_d_sin_r) / 1000
	$fl_d_rc_dx = ($ux * $fl_d_cos_r + $uy * $fl_d_sin_r) / 2000
	$fl_d_rc_dy = ($uy * $fl_d_cos_r - $ux * $fl_d_sin_r) / 2000
	return (1)
}

// Draws the bar left by $$fl_d_rect_calc, centred on its axis, $pad16 thicker.
command $$fl_d_bar(property $obj : object, property $pad16, property $r, property $g, property $b)
{
	property $len16
	property $t16
	property $sx
	property $sy
	$len16 = math.distance(0, 0, $fl_d_rc_dx / 4, $fl_d_rc_dy / 4) * 8
	if( $len16 < 16 ) { $len16 = 16 }
	$t16 = $$fl_d_clamp($fl_d_rc_t + $pad16, 16, 4800)
	$sx = $fl_d_rc_x - $fl_d_rc_dx + $fl_d_rc_dy * $t16 / $len16
	$sy = $fl_d_rc_y - $fl_d_rc_dy - $fl_d_rc_dx * $t16 / $len16
	$obj.set_pos($$fl_d_round16($sx), $$fl_d_round16($sy))
	$obj.set_scale($len16 * 5 / 8, $t16 * 125 / 4)
	$obj.rotate_z = math.angle(0, 0, $fl_d_rc_dx, $fl_d_rc_dy)
	$obj.color_r = $r
	$obj.color_g = $g
	$obj.color_b = $b
	$obj.color_rate = 255
	$obj.disp = 1
}

// $slot is the marking's child index under the ground group.
command $$fl_d_rect(property $slot, property $x1, property $z1, property $x2, property $z2, property $w, property $pad16, property $r, property $g, property $b)
{
	$fl_d_root.child[1].child[$slot].disp = 0
	if( $$fl_d_rect_calc($slot, $x1, $z1, $x2, $z2, $w) ) { $$fl_d_bar($fl_d_root.child[1].child[$slot], $pad16, $r, $g, $b) }
}

command $$fl_draw_clear
{
	$fl_d_root.init
	$fl_d_state = -1
	$fl_d_hud_time = -1
	$fl_d_speech_serial = -1
}

command $$fl_draw_init
{
	property $i
	$$fl_draw_clear
	$fl_d_root.disp = 1
	$fl_d_root.layer = <LAYER_UI>
	$fl_d_root.wipe_copy = 0
	$fl_d_root.child.resize(9)

	// Horizon parent rotates only the distant sky/ground. Cockpit remains fixed.
	// Grass fills the ground plane; each frame the runway surface (light ground on
	// x > -30 m, then grass on x > 30 m, z < 0 and z > 900 m), the beach beyond the
	// land edge and the sea beyond the beach are laid over it as half-planes, then
	// three soft haze bands and finally the sky down to the horizon.
	$fl_d_root.child[0].disp = 1
	$fl_d_root.child[0].child.resize(11)
	$fl_d_root.child[0].child[0].create_rect(0, 0, 100, 100, 112, 137, 68, 255, 1)
	$fl_d_root.child[0].child[0].set_scale(80000, 50000)
	$fl_d_root.child[0].child[0].set_pos(-4000, 0)
	$fl_d_root.child[0].child[1].create_rect(0, 0, 100, 100, 155, 163, 89, 255, 1)
	for( $i = 2, $i < 5, $i += 1 ) { $fl_d_root.child[0].child[$i].create_rect(0, 0, 100, 100, 112, 137, 68, 255, 1) }
	$fl_d_root.child[0].child[5].create_rect(0, 0, 100, 100, 218, 204, 158, 255, 1)
	$fl_d_root.child[0].child[6].create_rect(0, 0, 100, 100, 54, 112, 156, 255, 1)
	for( $i = 1, $i < 7, $i += 1 ) { $fl_d_root.child[0].child[$i].set_scale(120000, 60000) }
	for( $i = 0, $i < 3, $i += 1 ) {
		$fl_d_root.child[0].child[7 + $i].create_rect(0, 0, 100, 1, 200, 214, 216, 255, 1)
		$fl_d_root.child[0].child[7 + $i].set_scale(80000, 2400 + $i * $i * 5000)
		$fl_d_root.child[0].child[7 + $i].set_pos(-4000, 0)
		$fl_d_root.child[0].child[7 + $i].tr = 64
	}
	// The sky art is drawn about its own (64, 36) centre; this puts its bottom edge
	// exactly on the horizon.
	$fl_d_root.child[0].child[10].create("b_bg999_01", 1, -2880, -3348)
	$fl_d_root.child[0].child[10].set_scale(3000, 3000)

	// Ground lines: 0-25 grid, 26-65 mown runway strips, 66-99 runway marks,
	// 100-108 roads, 109-168 field strips, 169-170 aim-point mark. 171 landmark sprites,
	// 172 turbines and sails.
	$fl_d_root.child[1].disp = 1
	$fl_d_root.child[1].child.resize(173)
	for( $i = 0, $i < 171, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[1].child[$i]) }
	$fl_d_rc_axis.resize(171)
	for( $i = 0, $i < 171, $i += 1 ) { $fl_d_rc_axis[$i] = 0 }
	$fl_d_root.child[1].child[171].disp = 1
	$fl_d_root.child[1].child[172].disp = 1
	$$fl_d_marks_init
	$fl_d_root.child[1].child[172].child.resize(33)
	for( $i = 0, $i < 33, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[1].child[172].child[$i]) }

	// Three inscribed octagonal guide frames match the circular precision boundary.
	$fl_d_root.child[2].disp = 1
	$fl_d_root.child[2].child.resize(30)
	for( $i = 0, $i < 30, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[2].child[$i]) }

	// Original artwork, fitted to the 1920 x 1080 native screen without stretching.
	$fl_d_root.child[3].create("ef_cutin_cockpit", 1, 0, 40)
	$fl_d_root.child[3].set_scale(938, 938)

	$$fl_d_hud_init

	// A center reference remains fixed in the windshield; it is not an autopilot.
	$fl_d_root.child[5].disp = 1
	$fl_d_root.child[5].child.resize(3)
	$$fl_d_line_init($fl_d_root.child[5].child[0])
	$$fl_d_line_init($fl_d_root.child[5].child[1])
	$$fl_d_line_init($fl_d_root.child[5].child[2])
	$$fl_d_line2($fl_d_root.child[5].child[0], 930, 395, 950, 395, 2, 255, 235, 170)
	$$fl_d_line2($fl_d_root.child[5].child[1], 970, 395, 990, 395, 2, 255, 235, 170)
	$$fl_d_line2($fl_d_root.child[5].child[2], 960, 405, 960, 413, 2, 255, 235, 170)

	$$fl_d_panel_init
	$$fl_d_speech_init
	$$fl_d_gyro_init
	$fl_d_gate_seen = 0
	$fl_d_toast_until = 0
	$fl_d_last_ms = 0
	$fl_d_centered = 0
	$$fl_draw_frame
}

// ---------------------------------------------------------------- landmarks

command $$fl_d_mark(property $i, property $file : str, property $x, property $z, property $height)
{
	$fl_d_root.child[1].child[171].child[$i].create($file, 0, 0, 0)
	$fl_d_lm_ph[$i] = $$fl_d_clamp($fl_d_root.child[1].child[171].child[$i].get_size_y, 1, 4096)
	// Anchor at the bottom centre: the sprite stands on its ground position.
	$fl_d_root.child[1].child[171].child[$i].set_center($fl_d_root.child[1].child[171].child[$i].get_size_x / 2, $fl_d_lm_ph[$i])
	// Distance haze blends towards the pale horizon colour.
	$fl_d_root.child[1].child[171].child[$i].color_r = 200
	$fl_d_root.child[1].child[171].child[$i].color_g = 214
	$fl_d_root.child[1].child[171].child[$i].color_b = 222
	$fl_d_lm_x[$i] = $x
	$fl_d_lm_z[$i] = $z
	$fl_d_lm_h[$i] = $height
}

command $$fl_d_marks_init
{
	property $i
	$fl_d_lm_count = 27
	$fl_d_lm_x.resize($fl_d_lm_count)
	$fl_d_lm_z.resize($fl_d_lm_count)
	$fl_d_lm_h.resize($fl_d_lm_count)
	$fl_d_lm_ph.resize($fl_d_lm_count)
	$fl_d_root.child[1].child[171].child.resize($fl_d_lm_count)
	// The canopy struts leave about 20 degrees either side of the nose clear, so each
	// landmark stands nearly ahead on the leg it marks, at a storybook scale.
	// Index 0 is the windmill; its sails are drawn separately.
	$$fl_d_mark(0, "FL_lm_windmill", -35000, 195000, 3200)
	$$fl_d_mark(1, "FL_lm_farm", -130000, 0, 2400)
	$$fl_d_mark(2, "FL_lm_observatory", -125000, -160000, 2800)
	$$fl_d_mark(3, "FL_lm_school", 20000, -145000, 2200)
	$$fl_d_mark(4, "FL_lm_shops", 50000, -152000, 2200)
	$$fl_d_mark(5, "FL_lm_sign", 14000, -126000, 1200)
	$$fl_d_mark(6, "FL_lm_hangar", 9000, 40000, 1400)
	$$fl_d_mark(7, "FL_lm_trailer", 8000, 50000, 450)
	// Windbreaks: north of the east wheat field, along the farm road, by the windmill,
	// the observatory and the town.
	for( $i = 0, $i < 7, $i += 1 ) { $$fl_d_mark(8 + $i, "FL_lm_trees", 18000 + $i * 9000, 64500, 1500) }
	for( $i = 0, $i < 6, $i += 1 ) { $$fl_d_mark(15 + $i, "FL_lm_trees", -30000 - $i * 15000, 1000, 1500) }
	$$fl_d_mark(21, "FL_lm_trees", -45000, 188000, 1500)
	$$fl_d_mark(22, "FL_lm_trees", -25000, 200000, 1400)
	$$fl_d_mark(23, "FL_lm_trees", -40000, 205000, 1500)
	$$fl_d_mark(24, "FL_lm_trees", -115000, -152000, 1500)
	$$fl_d_mark(25, "FL_lm_trees", -138000, -168000, 1600)
	$$fl_d_mark(26, "FL_lm_trees", 36000, -158000, 1500)
}

command $$fl_d_marks
{
	property $i
	property $scale
	property $haze
	for( $i = 0, $i < $fl_d_lm_count, $i += 1 ) {
		$fl_d_root.child[1].child[171].child[$i].disp = 0
		if( math.abs($fl_d_lm_x[$i] - $fl_x) < 800000 && math.abs($fl_d_lm_z[$i] - $fl_z) < 800000 ) {
			$$fl_d_camera($fl_d_lm_x[$i], 0, $fl_d_lm_z[$i])
			if( $fl_d_cam_z > 1500 ) {
				$$fl_d_screen($fl_d_cam_x, $fl_d_cam_y, $fl_d_cam_z)
				if( $fl_d_screen_x > -1200 && $fl_d_screen_x < 3120 && $fl_d_screen_y > -400 && $fl_d_screen_y < 2400 ) {
					$scale = 850 * $fl_d_lm_h[$i] / $fl_d_lm_ph[$i] * 1000 / $fl_d_cam_z
					$haze = $$fl_d_clamp(($fl_d_cam_z - 120000) * 255 / 600000, 0, 255)
					$fl_d_root.child[1].child[171].child[$i].set_pos($fl_d_screen_x, $fl_d_screen_y)
					$fl_d_root.child[1].child[171].child[$i].set_scale($scale, $scale)
					$fl_d_root.child[1].child[171].child[$i].rotate_z = 0 - $fl_roll
					$fl_d_root.child[1].child[171].child[$i].color_rate = $haze * 130 / 255
					$fl_d_root.child[1].child[171].child[$i].tr = 255 - $haze * 120 / 255
					// Nearer landmarks are drawn over farther ones; the index breaks ties so
					// the engine never has two equal keys to order arbitrarily.
					$fl_d_root.child[1].child[171].child[$i].layer = (100000 - $fl_d_cam_z / 100) * 32 + $i
					$fl_d_root.child[1].child[171].child[$i].disp = 1
				}
			}
		}
	}
	$$fl_d_sails
}

// Four lattice sails on the windmill, turning at about 10 rpm in the sprite's plane.
command $$fl_d_sails
{
	property $i
	property $cz
	property $hx
	property $hy
	property $ox
	property $oy
	property $angle
	property $c
	property $s
	property $l0
	property $l1
	property $off
	property $x1
	property $y1
	property $x2
	property $y2
	for( $i = 25, $i < 33, $i += 1 ) { $fl_d_root.child[1].child[172].child[$i].disp = 0 }
	if( $fl_d_root.child[1].child[171].child[0].disp == 0 ) { return }
	$$fl_d_camera($fl_d_lm_x[0], 0, $fl_d_lm_z[0])
	$$fl_d_screen($fl_d_cam_x, $fl_d_cam_y, $fl_d_cam_z)
	// Pixels per 1800ths of the windmill's height, as measured on the painting.
	$cz = $fl_d_cam_z * 1800 / $fl_d_lm_h[0]
	// Hub: 105/1800 of the height right of the sprite centre, 1695/1800 up.
	$ox = 105 * 850 / $cz
	$oy = 0 - 1695 * 850 / $cz
	$hx = $fl_d_screen_x + ($ox * $fl_d_cos_r + $oy * $fl_d_sin_r) / 1000
	$hy = $fl_d_screen_y + ($oy * $fl_d_cos_r - $ox * $fl_d_sin_r) / 1000
	$l0 = 120 * 850 / $cz
	$l1 = 1150 * 850 / $cz
	$off = 85 * 850 / $cz
	for( $i = 0, $i < 4, $i += 1 ) {
		$angle = (3600 - $fl_elapsed_ms * 6 / 10 % 3600 + $i * 900) % 3600 - $fl_roll
		$c = math.cos($angle, 1000)
		$s = math.sin($angle, 1000)
		// Lattice frame beside the stock, then the dark stock on top.
		$x1 = $hx + ($c * $l0 - $s * $off) / 1000
		$y1 = $hy + ($s * $l0 + $c * $off) / 1000
		$x2 = $hx + ($c * $l1 - $s * $off) / 1000
		$y2 = $hy + ($s * $l1 + $c * $off) / 1000
		$$fl_d_line2($fl_d_root.child[1].child[172].child[25 + $i * 2], $x1, $y1, $x2, $y2, $$fl_d_clamp(160 * 850 / $cz, 1, 160), 226, 220, 202)
		$fl_d_root.child[1].child[172].child[25 + $i * 2].tr = 210
		$$fl_d_line2($fl_d_root.child[1].child[172].child[26 + $i * 2], $hx, $hy, $hx + $c * $l1 / 1000, $hy + $s * $l1 / 1000, $$fl_d_clamp(32 * 850 / $cz, 1, 40), 96, 66, 48)
	}
}

// Five coastal wind turbines, 60 m hubs and 32 m blades turning at 15 rpm.
command $$fl_d_turbines
{
	property $i
	property $j
	property $x
	property $w
	property $angle
	for( $i = 0, $i < 25, $i += 1 ) { $fl_d_root.child[1].child[172].child[$i].disp = 0 }
	for( $i = 0, $i < 5, $i += 1 ) {
		$x = -170000 + $i * 60000
		if( math.abs($x - $fl_x) < 800000 && math.abs(226000 - $fl_z) < 800000 ) {
			$$fl_d_camera($x, 3000, 226000)
			if( $fl_d_cam_z > 2000 ) {
				$w = $$fl_d_clamp(300 * 850 / $fl_d_cam_z, 1, 40)
				$$fl_d_line3($fl_d_root.child[1].child[172].child[$i * 5], $x, 0, 226000, $x, 6000, 226000, $w, 236, 238, 240)
				$$fl_d_line3($fl_d_root.child[1].child[172].child[$i * 5 + 1], $x, 6000, 225700, $x, 6000, 226500, $w + 1, 222, 226, 230)
				for( $j = 0, $j < 3, $j += 1 ) {
					$angle = ($fl_elapsed_ms * 9 / 10 + $i * 470 + $j * 1200) % 3600
					$$fl_d_line3($fl_d_root.child[1].child[172].child[$i * 5 + 2 + $j], $x, 6000, 225650,
						$x + math.cos($angle, 3200), 6000 + math.sin($angle, 3200), 225650,
						$$fl_d_clamp($w * 2 / 3, 1, 30), 242, 244, 246)
				}
			}
		}
	}
}

// ---------------------------------------------------------------- ground

// Five rows of three segments each, so every piece takes its own perspective width.
command $$fl_d_field(property $first, property $x, property $z, property $sx, property $sz, property $lx, property $lz, property $w, property $r, property $g, property $b)
{
	property $i
	property $j
	property $shade
	property $x0
	property $z0
	for( $i = 0, $i < 5, $i += 1 ) {
		$shade = 1000 - $i % 2 * 90
		for( $j = 0, $j < 3, $j += 1 ) {
			$x0 = $x + $i * $sx + $lx * $j / 3
			$z0 = $z + $i * $sz + $lz * $j / 3
			$$fl_d_strip($fl_d_root.child[1].child[$first + $i * 3 + $j], $x0, $z0, $x0 + $lx / 3, $z0 + $lz / 3, $w, $r * $shade / 1000, $g * $shade / 1000, $b * $shade / 1000)
		}
	}
}

command $$fl_d_world
{
	property $i
	property $z
	property $x
	property $base_x
	property $base_z
	property $zmax
	// Sea, beach (40 m) and land, seen from the current height.
	$$fl_d_coast_calc
	// Runway surface first, so the coast below paints over any grass it laid on the sea.
	$$fl_d_region($fl_d_root.child[0].child[1], -3000, $fl_z - 800000, -3000, $fl_z + 800000, 1, 0)
	$$fl_d_region($fl_d_root.child[0].child[2], 3000, $fl_z - 800000, 3000, $fl_z + 800000, 1, 0)
	$$fl_d_region($fl_d_root.child[0].child[3], $fl_x - 800000, 0, $fl_x + 800000, 0, 0, -1)
	$$fl_d_region($fl_d_root.child[0].child[4], $fl_x - 800000, 90000, $fl_x + 800000, 90000, 0, 1)
	$$fl_d_halfplane($fl_d_root.child[0].child[5], $fl_d_cl_px, $fl_d_cl_py, 0 - $fl_d_cl_a, 0 - $fl_d_cl_n)
	$$fl_d_halfplane($fl_d_root.child[0].child[6], $fl_d_cb_px, $fl_d_cb_py, 0 - $fl_d_cb_a, 0 - $fl_d_cb_n)
	// Stable world grid, in 300m cells, gives texture flow over land only.
	$base_x = $fl_x / 30000 * 30000
	$base_z = $fl_z / 30000 * 30000
	$zmax = $$fl_d_clamp($base_z + 180000, -9000000, 236000)
	for( $i = 0, $i < 13, $i += 1 )
	{
		$x = $base_x + ($i - 6) * 30000
		$z = $base_z + ($i - 6) * 30000
		$fl_d_root.child[1].child[$i * 2].disp = 0
		$fl_d_root.child[1].child[$i * 2 + 1].disp = 0
		if( $base_z - 180000 < $zmax ) {
			$$fl_d_line3($fl_d_root.child[1].child[$i * 2], $x, 0, $base_z - 180000, $x, 0, $zmax, 1, 124, 146, 76)
		}
		if( $z < 236000 ) {
			$$fl_d_line3($fl_d_root.child[1].child[$i * 2 + 1], $base_x - 180000, 0, $z, $base_x + 180000, 0, $z, 1, 124, 146, 76)
		}
	}
	// The mown runway surface is a ground region in the horizon layers; here come its
	// cream edge lines and the markings, all at real size.
	$$fl_d_line3($fl_d_root.child[1].child[66], -3000, 8, 0, -3000, 8, 90000, 4, 242, 239, 205)
	$$fl_d_line3($fl_d_root.child[1].child[67], 3000, 8, 0, 3000, 8, 90000, 4, 242, 239, 205)
	$$fl_d_line3($fl_d_root.child[1].child[68], -3000, 8, 0, 3000, 8, 0, 7, 242, 239, 205)
	$$fl_d_line3($fl_d_root.child[1].child[69], -3000, 8, 90000, 3000, 8, 90000, 7, 242, 239, 205)
	// Centre-line dashes 26 m x 0.6 m; threshold bars 38 m x 2.5 m at both ends.
	for( $i = 0, $i < 12, $i += 1 ) {
		$z = $i * 7500 + 1600
		$$fl_d_rect(70 + $i, 0, $z, 0, $z + 2600, 60, 0, 230, 236, 191)
	}
	for( $i = 0, $i < 8, $i += 1 ) {
		$x = ($i - 4) * 650 + 300
		$$fl_d_rect(82 + $i, $x, 1000, $x, 4800, 250, 0, 242, 239, 205)
		$$fl_d_rect(90 + $i, $x, 85200, $x, 89000, 250, 0, 242, 239, 205)
	}
	// Aim-point blocks (30 m x 4 m) either side of the touchdown aim point, 220 m past
	// the threshold, and an orange cross on the aim point itself.
	$$fl_d_rect(98, -1900, 20500, -1900, 23500, 400, 0, 242, 239, 205)
	$$fl_d_rect(99, 1900, 20500, 1900, 23500, 400, 0, 242, 239, 205)
	$$fl_d_rect(169, -1200, 22000, 1200, 22000, 250, 0, 255, 150, 40)
	$$fl_d_rect(170, 0, 20800, 0, 23200, 250, 0, 255, 150, 40)
	// Roads: from the field into town, along the coast, and out to the farm.
	$$fl_d_strip($fl_d_root.child[1].child[100], 3500, -2000, 6000, -80000, 600, 158, 156, 146)
	$$fl_d_strip($fl_d_root.child[1].child[101], 6000, -80000, 10000, -128000, 600, 158, 156, 146)
	$$fl_d_strip($fl_d_root.child[1].child[102], 10000, -128000, 20000, -138000, 600, 158, 156, 146)
	$$fl_d_strip($fl_d_root.child[1].child[103], 20000, -138000, 70000, -160000, 600, 158, 156, 146)
	$$fl_d_strip($fl_d_root.child[1].child[104], -300000, 231000, -150000, 231000, 700, 150, 150, 142)
	$$fl_d_strip($fl_d_root.child[1].child[105], -150000, 231000, 0, 231000, 700, 150, 150, 142)
	$$fl_d_strip($fl_d_root.child[1].child[106], 0, 231000, 150000, 231000, 700, 150, 150, 142)
	$$fl_d_strip($fl_d_root.child[1].child[107], -3500, 5000, -65000, 5000, 500, 164, 150, 112)
	$$fl_d_strip($fl_d_root.child[1].child[108], -65000, 5000, -125000, 5000, 500, 164, 150, 112)
	// Fields as broad crop rows of alternating shade: wheat west of the farm, east of the
	// airfield and inside the circuit, and the town's watermelon patch.
	$$fl_d_field(109, -186000, -40000, 9000, 0, 0, 80000, 5000, 206, 174, 86)
	$$fl_d_field(124, 15000, 26000, 0, 7000, 60000, 0, 4000, 212, 182, 92)
	$$fl_d_field(139, -80000, -90000, 6000, 0, 0, 45000, 3300, 200, 170, 82)
	$$fl_d_field(154, -40000, -175000, 0, 5500, 40000, 0, 3000, 72, 116, 54)
}

command $$fl_d_gates
{
	property $i
	property $j
	property $k
	property $slot
	property $gx
	property $gy
	property $gz
	property $sx
	property $sy
	property $sz
	property $ex
	property $ey
	property $ez
	property $across
	property $radius
	property $r
	property $g
	property $b
	property $width
	for( $i = 0, $i < 30, $i += 1 ) { $fl_d_root.child[2].child[$i].disp = 0 }
	for( $i = 2, $i >= 0, $i -= 1 )
	{
		$j = $fl_gate_index + $i
		if( $j < $fl_gate_count )
		{
			$slot = (2 - $i) * 10
			$gx = $fl_gate_x[$j]
			$gy = $fl_gate_y[$j]
			$gz = $fl_gate_z[$j]
			$radius = $fl_gate_radius[$j]
			$r = 97
			$g = 222
			$b = 206
			$width = 3
			if( $i == 0 ) {
				$r = 255
				$g = 190
				$b = 79
				$width = 5
			}
			// Eight straight segments lie entirely inside the scoring circle.
			// Consequently crossing anywhere inside the visible frame is valid.
			for( $k = 0, $k < 8, $k += 1 )
			{
				$across = math.cos(225 + $k * 450, $radius)
				$sx = $gx + math.cos($fl_gate_heading[$j], $across)
				$sz = $gz - math.sin($fl_gate_heading[$j], $across)
				$sy = $gy + math.sin(225 + $k * 450, $radius)
				$across = math.cos(675 + $k * 450, $radius)
				$ex = $gx + math.cos($fl_gate_heading[$j], $across)
				$ez = $gz - math.sin($fl_gate_heading[$j], $across)
				$ey = $gy + math.sin(675 + $k * 450, $radius)
				$$fl_d_line3($fl_d_root.child[2].child[$slot + $k], $sx, $sy, $sz, $ex, $ey, $ez, $width, $r, $g, $b)
				$fl_d_root.child[2].child[$slot + $k].tr = 255 - $i * 55
			}
			$sx = math.cos($fl_gate_heading[$j], $radius / 10)
			$sz = 0 - math.sin($fl_gate_heading[$j], $radius / 10)
			$$fl_d_line3($fl_d_root.child[2].child[$slot + 8], $gx - $sx, $gy, $gz - $sz, $gx + $sx, $gy, $gz + $sz, 2, $r, $g, $b)
			$$fl_d_line3($fl_d_root.child[2].child[$slot + 9], $gx, $gy - $radius / 10, $gz, $gx, $gy + $radius / 10, $gz, 2, $r, $g, $b)
		}
	}
}

// ---------------------------------------------------------------- HUD

// Map: 1 px = 17 m, centred on (-800 m, +100 m); north is up.
command $$fl_d_map_xy(property $x, property $z)
{
	$fl_d_map_x = 1736 + ($x + 80000) / 1700
	$fl_d_map_y = 286 - ($z - 10000) / 1700
}

command $$fl_d_map_dot(property $i, property $x, property $z, property $size, property $r, property $g, property $b)
{
	$$fl_d_map_xy($x, $z)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[$i], $fl_d_map_x - $size / 2, $fl_d_map_y - $size / 2, $fl_d_map_x + $size / 2, $fl_d_map_y - $size / 2, $size, $r, $g, $b)
}

// Information panels. Numbers are updated at 10Hz, not rebuilt every frame.
command $$fl_d_hud_init
{
	property $i
	property $s : str
	$fl_d_root.child[4].disp = 1
	$fl_d_root.child[4].child.resize(43)
	// Backgrounds: top bar, instrument strip, bottom tip bar, map panel.
	$fl_d_root.child[4].child[0].create_rect(0, 0, 1920, 86, 11, 26, 33, 200, 1)
	$fl_d_root.child[4].child[1].create_rect(0, 0, 1422, 100, 7, 17, 25, 222, 1)
	$fl_d_root.child[4].child[1].set_pos(249, 922)
	$fl_d_root.child[4].child[2].create_rect(0, 0, 1920, 50, 6, 18, 25, 222, 1)
	$fl_d_root.child[4].child[2].set_pos(0, 1030)
	$fl_d_root.child[4].child[3].create_rect(0, 0, 304, 352, 8, 28, 36, 215, 1)
	$fl_d_root.child[4].child[3].set_pos(1584, 98)
	// Top bar: flight leg on the left, score in the centre, title at the right.
	$$fl_d_text($fl_d_root.child[4].child[4], "", 32, 8, 32, 0)
	$$fl_d_text($fl_d_root.child[4].child[5], "", 34, 50, 21, 22)
	$$fl_d_text($fl_d_root.child[4].child[6], "", 800, 8, 32, 0)
	$$fl_d_text($fl_d_root.child[4].child[7], "", 800, 50, 21, 22)
	$s = "爱乃 · 初次飞行"
	$$fl_d_text($fl_d_root.child[4].child[8], $s, 1872 - $s.len * 26 / 2, 26, 26, 0)
	// Stall banner and gate toast, centred above the windshield reference.
	$fl_d_root.child[4].child[9].create_rect(0, 0, 640, 54, 120, 24, 18, 210, 1)
	$fl_d_root.child[4].child[9].set_pos(640, 132)
	$fl_d_root.child[4].child[9].disp = 0
	$$fl_d_text($fl_d_root.child[4].child[10], "", 660, 140, 30, 0)
	$fl_d_root.child[4].child[11].create_rect(0, 0, 660, 46, 11, 26, 33, 190, 1)
	$fl_d_root.child[4].child[11].set_pos(630, 200)
	$fl_d_root.child[4].child[11].disp = 0
	$$fl_d_text($fl_d_root.child[4].child[12], "", 760, 207, 26, 0)
	$$fl_d_text($fl_d_root.child[4].child[13], "本场航图 · 北 ↑", 1600, 106, 18, 22)
	$fl_d_root.child[4].child[14].disp = 1
	$fl_d_root.child[4].child[14].child.resize(56)
	for( $i = 0, $i < 56, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[4].child[14].child[$i]) }
	// Bottom bar: the current leg's advice and the key summary.
	$$fl_d_text($fl_d_root.child[4].child[15], "", 32, 1040, 22, 0)
	$s = "↑↓ 俯仰 · ←→ 坡度 · Q / A 油门 · B 刹车 · P 暂停"
	$$fl_d_text($fl_d_root.child[4].child[16], $s, 1888 - $s.len * 18 / 2, 1043, 18, 22)
	// Instrument strip: six fixed cells, small label above a large value.
	for( $i = 0, $i < 6, $i += 1 ) {
		$$fl_d_text($fl_d_root.child[4].child[17 + $i], "", 270 + $i * 237, 930, 18, 22)
		$$fl_d_text($fl_d_root.child[4].child[23 + $i], "", 270 + $i * 237, 956, 34, 0)
	}
	$fl_d_root.child[4].child[17].set_string("空速")
	$fl_d_root.child[4].child[18].set_string("高度")
	$fl_d_root.child[4].child[19].set_string("离地")
	$fl_d_root.child[4].child[20].set_string("航向")
	$fl_d_root.child[4].child[21].set_string("油门")
	$fl_d_root.child[4].child[22].set_string("垂直速率")
	for( $i = 0, $i < 5, $i += 1 ) {
		$fl_d_root.child[4].child[29 + $i].create_rect(0, 0, 1, 72, 70, 92, 102, 255, 1)
		$fl_d_root.child[4].child[29 + $i].set_pos(486 + $i * 237, 936)
	}
	// Map labels and legend.
	$$fl_d_text($fl_d_root.child[4].child[34], "风车", 1770, 166, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[35], "牧场", 1660, 282, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[36], "天文台", 1650, 376, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[37], "小镇", 1812, 370, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[38], "下一框", 1614, 424, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[39], "已通过", 1712, 424, 16, 0)
	$$fl_d_text($fl_d_root.child[4].child[40], "漏框", 1810, 424, 16, 0)
	// Brake badge above the instrument strip while B is held on the landing roll.
	$fl_d_root.child[4].child[41].create_rect(0, 0, 220, 40, 150, 40, 30, 220, 1)
	$fl_d_root.child[4].child[41].set_pos(850, 872)
	$fl_d_root.child[4].child[41].disp = 0
	$s = "B 刹车中"
	$$fl_d_text($fl_d_root.child[4].child[42], $s, 960 - $s.len * 24 / 4, 876, 24, 0)
	$fl_d_root.child[4].child[42].disp = 0
}

// Centimetres as metres with one decimal, sign dropped.
command $$fl_d_metres(property $cm) : str
{
	$cm = math.abs($cm)
	return (math.tostr($cm / 100) + "." + math.tostr($cm % 100 / 10))
}

// Lateral and along-runway miss of the first touchdown, as words and metres.
command $$fl_d_touch_text : str
{
	property $side : str
	property $aim : str
	$side = "偏右 "
	if( $fl_touch_x < 0 ) { $side = "偏左 " }
	$aim = "偏晚 "
	if( $fl_touch_z < 22000 ) { $aim = "偏早 " }
	return ("中线 " + $side + $$fl_d_metres($fl_touch_x) + " m · 瞄准点 " + $aim + $$fl_d_metres($fl_touch_z - 22000) + " m")
}

command $$fl_d_map
{
	property $i
	property $x1
	property $y1
	property $r
	property $g
	property $b
	// Sea above the coast line, the beach, and the coastal turbines.
	$$fl_d_map_xy(0, 240000)
	// A line's width grows downwards from its start point.
	$$fl_d_line2($fl_d_root.child[4].child[14].child[0], 1588, 128, 1884, 128, $fl_d_map_y - 128, 54, 112, 156)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[1], 1588, $fl_d_map_y, 1884, $fl_d_map_y, 3, 218, 204, 158)
	$$fl_d_map_xy(-170000, 226000)
	$x1 = $fl_d_map_x
	$$fl_d_map_xy(70000, 226000)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[2], $x1, $fl_d_map_y, $fl_d_map_x, $fl_d_map_y, 2, 236, 238, 240)
	// Runway.
	$$fl_d_map_xy(0, 0)
	$x1 = $fl_d_map_x
	$y1 = $fl_d_map_y
	$$fl_d_map_xy(0, 90000)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[3], $x1, $y1, $fl_d_map_x, $fl_d_map_y, 4, 235, 237, 209)
	// Touchdown aim point, then landmarks: windmill, farm, observatory, town.
	$$fl_d_map_dot(53, 0, 22000, 5, 255, 150, 40)
	$$fl_d_map_dot(4, -35000, 195000, 7, 176, 96, 70)
	$$fl_d_map_dot(5, -130000, 0, 7, 214, 174, 86)
	$$fl_d_map_dot(6, -125000, -160000, 7, 230, 232, 236)
	$$fl_d_map_dot(7, 35000, -150000, 7, 236, 150, 92)
	// Route and gates.
	$$fl_d_map_xy(0, 10000)
	$x1 = $fl_d_map_x
	$y1 = $fl_d_map_y
	for( $i = 0, $i < $fl_gate_count, $i += 1 )
	{
		$$fl_d_map_xy($fl_gate_x[$i], $fl_gate_z[$i])
		$$fl_d_line2($fl_d_root.child[4].child[14].child[8 + $i], $x1, $y1, $fl_d_map_x, $fl_d_map_y, 1, 75, 124, 130)
		$r = 92
		$g = 187
		$b = 180
		if( $fl_gate_result[$i] == 1 || $fl_gate_result[$i] == 2 ) { $r = 162
			$g = 234
			$b = 158 }
		if( $fl_gate_result[$i] == 3 ) { $r = 234
			$g = 106
			$b = 94 }
		if( $i == $fl_gate_index ) { $r = 255
			$g = 190
			$b = 79 }
		$$fl_d_line2($fl_d_root.child[4].child[14].child[28 + $i], $fl_d_map_x - 2, $fl_d_map_y, $fl_d_map_x + 2, $fl_d_map_y, 4, $r, $g, $b)
		$x1 = $fl_d_map_x
		$y1 = $fl_d_map_y
	}
	// Legend swatches.
	$$fl_d_line2($fl_d_root.child[4].child[14].child[48], 1600, 434, 1608, 434, 8, 255, 190, 79)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[49], 1698, 434, 1706, 434, 8, 162, 234, 158)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[50], 1796, 434, 1804, 434, 8, 234, 106, 94)
	// Own aircraft.
	$$fl_d_map_xy($fl_x, $fl_z)
	$x1 = $$fl_d_clamp($fl_d_map_x, 1592, 1880)
	$y1 = $$fl_d_clamp($fl_d_map_y, 128, 416)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[51], $x1, $y1, $x1 + math.sin($fl_heading, 11), $y1 - math.cos($fl_heading, 11), 3, 255, 255, 255)
	$$fl_d_line2($fl_d_root.child[4].child[14].child[52], $x1 - math.cos($fl_heading, 6), $y1 - math.sin($fl_heading, 6), $x1 + math.cos($fl_heading, 6), $y1 + math.sin($fl_heading, 6), 2, 255, 255, 255)
}

command $$fl_d_value(property $i, property $text : str)
{
	$$fl_d_center_text($fl_d_root.child[4].child[23 + $i], $text, 368 + $i * 237, 956, 34)
}

command $$fl_d_hud
{
	property $s : str
	property $phase : str
	property $tip : str
	property $heading
	$heading = ($fl_heading + 3600) % 3600 / 10
	if( $heading == 0 ) { $heading = 360 }
	$$fl_d_value(0, math.tostr($fl_speed * 1944 / 100000) + " kt")
	$$fl_d_value(1, math.tostr($fl_alt * 328 / 10000) + " ft")
	$$fl_d_value(2, math.tostr($fl_alt / 100) + " m")
	$$fl_d_value(3, math.tostr($heading) + "°")
	$$fl_d_value(4, math.tostr($fl_throttle / 10) + "%")
	if( $fl_touched ) {
		$fl_d_root.child[4].child[22].set_string("接地下降率")
		$$fl_d_value(5, math.tostr($fl_touch_fpm) + " fpm")
	} else {
		$fl_d_root.child[4].child[22].set_string("垂直速率")
		$s = math.tostr($fl_vspeed * 197 / 100)
		if( $fl_vspeed > 0 ) { $s = "+" + $s }
		$$fl_d_value(5, $s + " fpm")
	}
	$phase = "草地滑跑"
	$tip = "Q 推满油门，保持中线；约 47 kt 起按住 ↓ 抬头 8–10°，保持到离地"
	switch( $fl_phase ) {
	case(1) $phase = "一边 · 起飞爬升"
		$tip = "满油门爬升，空速保持 55–60 kt；穿过橙框后接近 130 m（约 430 ft）"
	case(2) $phase = "二边 · 侧风边"
		$tip = "朝海岸飞，在风车附近左转；转弯时轻拉 ↓ 保持高度"
	case(3) $phase = "三边 · 下风边"
		$tip = "跑道在左，牧场在右前方；保持 150 m（约 490 ft）、约 58 kt、油门约 55%"
	case(4) $phase = "四边 · 基线边"
		$tip = "在天文台前左转，朝小镇方向；油门 30–40%，52–56 kt 平缓下降"
	case(5) $phase = "五边 · 最后进近"
		$tip = "对正跑道中线，瞄准橙色十字；油门 20–30%，近地轻拉 ↓ 拉平"
	case(6) $phase = "着陆滑跑"
		$tip = "保持方向，A 收油门，按住 B 刹车"
	}
	// Gamepad labels while the pad is the device in use.
	$s = "↑↓ 俯仰 · ←→ 坡度 · Q / A 油门 · B 刹车 · P 暂停"
	if( $fl_pad_mode ) {
		$s = "左摇杆 俯仰 / 坡度 · RT / LT 油门 · B 刹车 · START 暂停"
		if( $fl_phase == 0 ) { $tip = "RT 推满油门，保持中线；约 47 kt 起按住 ↓ 抬头 8–10°，保持到离地" }
		if( $fl_phase == 6 ) { $tip = "保持方向，LT 收油门，按住 B 刹车" }
	}
	$fl_d_root.child[4].child[16].set_string($s)
	$fl_d_root.child[4].child[16].set_pos(1888 - $s.len * 18 / 2, 1043)
	$fl_d_root.child[4].child[4].set_string($phase)
	$s = "引导框 " + math.tostr($$fl_d_clamp($fl_gate_index + 1, 1, $fl_gate_count)) + " / " + math.tostr($fl_gate_count)
	if( $fl_gate_index >= $fl_gate_count ) { $s = "引导框完成 · 对准橙色瞄准点" }
	$fl_d_root.child[4].child[5].set_string($s)
	// Only the counts during flight; the frame score appears on the result panel.
	$$fl_d_center_text($fl_d_root.child[4].child[6], "通过 " + math.tostr($fl_gate_hits) + " · 漏框 " + math.tostr($fl_gate_misses), 960, 22, 32)
	$fl_d_root.child[4].child[15].set_string($tip)
	// Stall warning: amber when the angle of attack nears critical, red once stalled.
	$fl_d_root.child[4].child[9].disp = 0
	$s = ""
	if( $fl_state == 1 && $fl_stall == 1 ) {
		$s = "迎角过大 · 接近失速"
		$fl_d_root.child[4].child[9].color_r = 150
		$fl_d_root.child[4].child[9].color_g = 98
		$fl_d_root.child[4].child[9].color_b = 18
		$fl_d_root.child[4].child[9].color_rate = 255
		$fl_d_root.child[4].child[9].disp = 1
	}
	if( $fl_state == 1 && $fl_stall == 2 ) {
		$s = "失速！松开 ↓ 压低机头 · 加油门"
		$fl_d_root.child[4].child[9].color_rate = 0
		$fl_d_root.child[4].child[9].disp = 1
	}
	$$fl_d_center_text($fl_d_root.child[4].child[10], $s, 960, 141, 30)
	// A short toast for each gate: passed or missed, without its score.
	if( $fl_gate_event < $fl_d_gate_seen ) { $fl_d_gate_seen = $fl_gate_event }
	if( $fl_gate_event > $fl_d_gate_seen ) {
		$fl_d_gate_seen = $fl_gate_event
		$fl_d_toast_until = $fl_elapsed_ms + 2200
		$s = "第 " + math.tostr($fl_gate_index) + " 框 · 漏框"
		if( $fl_last_precision > 0 ) { $s = "第 " + math.tostr($fl_gate_index) + " 框 · 通过" }
		$$fl_d_center_text($fl_d_root.child[4].child[12], $s, 960, 207, 26)
	}
	// First touchdown: where the wheels met the runway, against centreline and aim point.
	if( $fl_touched == 0 ) { $fl_d_touch_seen = 0 }
	if( $fl_touched && $fl_d_touch_seen == 0 ) {
		$fl_d_touch_seen = 1
		$fl_d_toast_until = $fl_elapsed_ms + 3500
		$$fl_d_center_text($fl_d_root.child[4].child[12], $$fl_d_touch_text, 960, 207, 26)
	}
	$fl_d_root.child[4].child[11].disp = ($fl_state == 1 && $fl_elapsed_ms < $fl_d_toast_until)
	$fl_d_root.child[4].child[12].disp = $fl_d_root.child[4].child[11].disp
	$fl_d_root.child[4].child[41].disp = ($fl_state == 1 && $fl_touched && $fl_in_brake)
	$fl_d_root.child[4].child[42].disp = $fl_d_root.child[4].child[41].disp
	$$fl_d_map
}

// Original windmill confirmation panel, feather overlay and choice-button textures.
// Rows are a short coloured label column and a body column at fixed positions.
command $$fl_d_panel_init
{
    property $i
    $fl_d_root.child[6].disp = 0
    $fl_d_root.child[6].child.resize(22)
    $fl_d_root.child[6].child[0].create("_dialog_bg", 1, 0, 0)
    $fl_d_root.child[6].child[0].tr = 170
    $fl_d_root.child[6].child[1].create("_dialog_yesno_bg", 1, 250, 135)
    $fl_d_root.child[6].child[1].set_scale(2165, 4765)
    $fl_d_root.child[6].child[2].create($$get_bs_image_name("ai11_14"), 1, 1450, -100)
    $fl_d_root.child[6].child[2].set_scale(450, 450)
    $$fl_d_panel_text($fl_d_root.child[6].child[3], 355, 194, 48, 21)
    $$fl_d_panel_text($fl_d_root.child[6].child[4], 360, 266, 28, 21)
    for( $i = 0, $i < 7, $i += 1 ) {
        $$fl_d_panel_text($fl_d_root.child[6].child[5 + $i], 474, 326 + $i * 54, 27, 8)
        $$fl_d_panel_text($fl_d_root.child[6].child[15 + $i], 360, 326 + $i * 54, 27, 5)
    }
    $$fl_d_panel_text($fl_d_root.child[6].child[12], 360, 764, 22, 21)
    $fl_d_root.child[6].child[13].disp = 1
    $fl_d_root.child[6].child[13].child.resize(3)
    $fl_d_button_action.resize(3)
    $fl_d_button_x.resize(3)
    for( $i = 0, $i < 3, $i += 1 ) {
        $fl_d_button_x[$i] = 365 + $i * 415
        $fl_d_root.child[6].child[13].child[$i].disp = 1
        $fl_d_root.child[6].child[13].child[$i].set_pos($fl_d_button_x[$i], 845)
        $fl_d_root.child[6].child[13].child[$i].child.resize(2)
        $fl_d_root.child[6].child[13].child[$i].child[0].create("_sel_btn_n", 1, 0, 0)
        $fl_d_root.child[6].child[13].child[$i].child[0].set_scale(398, 914)
        $$fl_d_text($fl_d_root.child[6].child[13].child[$i].child[1], "", 30, 16, 27, 8)
        $fl_d_root.child[6].child[13].child[$i].child[1].set_string_param(27, 0, 0, 100, 8, 0, 0)
        $fl_d_button_action[$i] = 0
    }
    $$fl_d_kern_text($fl_d_root.child[6].child[14], "Aino's First Flight", 360, 164, 19, 21)
}

command $$fl_d_row(property $i, property $label : str, property $body : str)
{
    $fl_d_root.child[6].child[15 + $i].set_string($label)
    $fl_d_root.child[6].child[5 + $i].set_string($body)
}

command $$fl_d_button(property $i, property $action, property $label : str)
{
    $fl_d_button_action[$i] = $action
    $fl_d_root.child[6].child[13].child[$i].disp = ($action != 0)
    $fl_d_root.child[6].child[13].child[$i].child[1].set_string($label)
    $fl_d_root.child[6].child[13].child[$i].child[1].set_pos(180 - $label.len * 27 / 4, 17)
}

command $$fl_d_button_hover
{
    property $i
    property $hit
    property $mx
    property $my
    $mx = mouse.get_pos_x
    $my = mouse.get_pos_y
    for( $i = 0, $i < 3, $i += 1 ) {
        $hit = ($fl_d_button_action[$i] != 0 && $mx >= $fl_d_button_x[$i] && $mx < $fl_d_button_x[$i] + 360 && $my >= 845 && $my < 909)
        // With the gamepad, the focused button shows the hover look instead.
        if( $fl_pad_mode ) { $hit = ($fl_d_button_action[$i] != 0 && $i == $fl_pad_focus) }
        $fl_d_root.child[6].child[13].child[$i].child[0].patno = $hit
        if( $hit ) {
            $fl_d_root.child[6].child[13].child[$i].child[1].set_string_param(27, 0, 0, 100, 21, 0, 0)
        } else {
            $fl_d_root.child[6].child[13].child[$i].child[1].set_string_param(27, 0, 0, 100, 8, 0, 0)
        }
    }
}

// Explicit menu hit testing: neither arbitrary clicks nor narrative decide can leave flight.
command $$fl_ui_action : int
{
    property $i
    property $mx
    property $my
    if( $fl_state == 1 || $fl_state == 5 ) { return (0) }
    if( mouse.left.on_down == 0 ) { return (0) }
    $mx = mouse.get_pos_x
    $my = mouse.get_pos_y
    for( $i = 0, $i < 3, $i += 1 ) {
        if( $fl_d_button_action[$i] != 0 && $mx >= $fl_d_button_x[$i] && $mx < $fl_d_button_x[$i] + 360 && $my >= 845 && $my < 909 ) {
            return ($fl_d_button_action[$i])
        }
    }
    return (0)
}

// Gamepad menu input. ←→ (D-pad or left stick, with the game's key repeat) moves the
// focus over the visible panel buttons and A presses the focused one; START, B, Y and
// BACK are shortcuts like P / Enter, Esc and R. While flying, START or BACK pauses (6).
command $$fl_pad_action : int
{
    property $i
    property $step
    if( $fl_state == 5 ) { return (0) }
    if( $fl_state == 1 ) {
        if( joypad.key[<JOYPAD_EX1>].on_down || joypad.key[<JOYPAD_EX2>].on_down ) { return (6) }
        return (0)
    }
    if( $fl_pad_focus < 0 || $fl_pad_focus > 2 ) { $fl_pad_focus = 0 }
    if( $fl_d_button_action[$fl_pad_focus] == 0 ) { $fl_pad_focus = 0 }
    $step = 0
    if( $$joypad_left_on_down ) { $step = -1 }
    elseif( $$joypad_right_on_down ) { $step = 1 }
    if( $step != 0 ) {
        $i = $fl_pad_focus + $step
        while( $i >= 0 && $i <= 2 && $fl_d_button_action[$i] == 0 ) { $i += $step }
        if( $i >= 0 && $i <= 2 ) { $fl_pad_focus = $i }
    }
    if( joypad.key[<JOYPAD_BUTTON1>].on_down ) { return ($fl_d_button_action[$fl_pad_focus]) }
    if( $fl_state == 0 ) {
        if( joypad.key[<JOYPAD_EX1>].on_down ) { return (1) }
        if( joypad.key[<JOYPAD_BUTTON2>].on_down || joypad.key[<JOYPAD_EX2>].on_down ) { return (3) }
    }
    elseif( $fl_state == 2 ) {
        if( joypad.key[<JOYPAD_EX1>].on_down || joypad.key[<JOYPAD_BUTTON2>].on_down ) { return (1) }
        if( joypad.key[<JOYPAD_BUTTON4>].on_down ) { return (2) }
        if( joypad.key[<JOYPAD_EX2>].on_down ) { return (3) }
    }
    elseif( $fl_state == 3 ) {
        if( joypad.key[<JOYPAD_BUTTON4>].on_down ) { return (2) }
    }
    elseif( $fl_state == 4 ) {
        if( joypad.key[<JOYPAD_BUTTON4>].on_down ) { return (2) }
        if( joypad.key[<JOYPAD_BUTTON2>].on_down || joypad.key[<JOYPAD_EX2>].on_down ) { return (3) }
    }
    elseif( $fl_state == 6 ) {
        // Cancelling is a shortcut; confirming needs the focused right-hand button.
        if( joypad.key[<JOYPAD_BUTTON2>].on_down || joypad.key[<JOYPAD_EX1>].on_down || joypad.key[<JOYPAD_EX2>].on_down ) { return (5) }
    }
    return (0)
}

command $$fl_d_overlay
{
    property $i
    property $s : str
    $fl_d_root.child[6].disp = ($fl_state != 1)
    $fl_d_root.child[6].child[4].set_string("")
    $fl_d_root.child[6].child[12].set_string("")
    for( $i = 0, $i < 7, $i += 1 ) { $$fl_d_row($i, "", "") }
    for( $i = 0, $i < 3, $i += 1 ) { $$fl_d_button($i, 0, "") }
    switch( $fl_state ) {
    case(0)
        $fl_d_root.child[6].child[3].set_string("爱乃的初次飞行")
        $fl_d_root.child[6].child[4].set_string("草地起飞 → 左五边本场飞行 → 同一跑道着陆")
        $$fl_d_row(0, "起飞", "满油门滑跑，47 kt 起按住 ↓ 抬头 8–10° 直到离地")
        $$fl_d_row(1, "巡航", "高度 150 m（约 490 ft）· 空速约 58 kt · 油门约 55%")
        $$fl_d_row(2, "转弯", "坡度 20–30°，同时轻拉 ↓ 补足升力、保持高度")
        $$fl_d_row(3, "着陆", "油门 20–30%，瞄准跑道上的橙色十字；接地后按住 B 刹车")
        $$fl_d_row(4, "地标", "风车附近左转；下风边前方是牧场；天文台前转四边")
        $$fl_d_row(5, "操作", "↑↓ 俯仰　←→ 坡度　Q / A 油门　B 刹车　P 暂停")
        $$fl_d_row(6, "评分", "穿框 50 ＋ 接地轻柔 30 ＋ 中线 10 ＋ 瞄准点 10")
        $fl_d_root.child[6].child[12].set_string("Enter 开始飞行　·　Esc 打开退出确认")
        $$fl_d_button(0, 1, "开始飞行")
        $$fl_d_button(2, 3, "返回原剧情")
        if( $fl_pad_mode ) {
            $$fl_d_row(5, "操作", "左摇杆 俯仰 / 坡度　RT / LT 油门　B 刹车　START 暂停")
            $fl_d_root.child[6].child[12].set_string("←→ 选择　·　A 确定　·　START 开始飞行　·　B 退出确认")
        }
    case(2)
        $fl_d_root.child[6].child[3].set_string("暂停")
        $$fl_d_row(0, "操作", "↑↓ 俯仰　←→ 坡度　Q / A 油门　B 刹车")
        $$fl_d_row(1, "转弯", "带坡度时升力会不足，轻拉 ↓ 保持高度")
        $$fl_d_row(2, "失速", "迎角过大时先压低机头、加油门，再慢慢拉起")
        $$fl_d_row(3, "着陆", "瞄准橙色十字，近地轻拉 ↓ 拉平；接地后按住 B 刹车")
        $fl_d_root.child[6].child[12].set_string("P / Enter 继续　·　R 重新起飞　·　Esc 退出确认")
        $$fl_d_button(0, 1, "继续飞行")
        $$fl_d_button(1, 2, "重新起飞")
        $$fl_d_button(2, 3, "退出飞行")
        if( $fl_pad_mode ) {
            $$fl_d_row(0, "操作", "左摇杆 俯仰 / 坡度　RT / LT 油门　B 刹车")
            $fl_d_root.child[6].child[12].set_string("←→ 选择　·　A 确定　·　START / B 继续　·　Y 重新起飞")
        }
    case(3)
        $fl_d_root.child[6].child[3].set_string("平安归来")
        $fl_d_root.child[6].child[4].set_string("着陆完成　总分 " + math.tostr($fl_total) + " / 100")
        $$fl_d_row(0, "引导框", math.tostr($fl_gate_points / 100) + " / 50　（通过 " + math.tostr($fl_gate_hits) + " 框 · 漏框 " + math.tostr($fl_gate_misses) + "）")
        $$fl_d_row(1, "接地", math.tostr($fl_landing_points / 100) + " / 30　（首次接地 " + math.tostr($fl_touch_fpm) + " fpm）")
        $s = "偏右 "
        if( $fl_touch_x < 0 ) { $s = "偏左 " }
        $$fl_d_row(2, "中线", math.tostr($fl_center_points / 100) + " / 10　（" + $s + $$fl_d_metres($fl_touch_x) + " m）")
        $s = "偏晚 "
        if( $fl_touch_z < 22000 ) { $s = "偏早 " }
        $$fl_d_row(3, "瞄准点", math.tostr($fl_aim_points / 100) + " / 10　（" + $s + $$fl_d_metres($fl_touch_z - 22000) + " m）")
        $$fl_d_row(4, "用时", math.tostr($fl_elapsed_ms / 60000) + " 分 " + math.tostr($fl_elapsed_ms / 1000 % 60) + " 秒")
        $$fl_d_row(6, "", "爱乃与麦的第一次飞行，顺利结束。")
        $fl_d_root.child[6].child[12].set_string("Enter 继续原剧情　·　R 再飞一次")
        $$fl_d_button(0, 1, "继续原剧情")
        $$fl_d_button(1, 2, "再飞一次")
        if( $fl_pad_mode ) { $fl_d_root.child[6].child[12].set_string("←→ 选择　·　A 确定　·　Y 再飞一次") }
    case(4)
        $fl_d_root.child[6].child[3].set_string("再试一次吧")
        $s = "未能安全落地。"
        switch( $fl_fail_reason ) {
        case(1) $s = "未在跑道范围内完成着陆滑跑。"
        case(2) $s = "接地过重、速度过高或姿态不适合着陆。"
        case(3) $s = "尚未完成左五边航线。"
        case(4) $s = "飞出了本场范围，或高度超过任务上限。"
        case(5) $s = "飞行时间达到上限。"
        case(6) $s = "起飞滑跑偏出了草地跑道。"
        }
        $fl_d_root.child[6].child[4].set_string($s)
        $$fl_d_row(0, "提示", "放平机翼，稳定空速；近地时轻拉机头拉平。")
        if( $fl_touched ) {
            $$fl_d_row(1, "接地", "首次接地下降率 " + math.tostr($fl_touch_fpm) + " fpm")
            $$fl_d_row(2, "落点", $$fl_d_touch_text)
        }
        $fl_d_root.child[6].child[12].set_string("Enter / R 重新起飞　·　返回剧情需要再次确认")
        $$fl_d_button(0, 2, "重新起飞")
        $$fl_d_button(2, 3, "结束飞行")
        if( $fl_pad_mode ) { $fl_d_root.child[6].child[12].set_string("←→ 选择　·　A 确定　·　Y 重新起飞　·　B 退出确认") }
    case(6)
        $fl_d_root.child[6].child[3].set_string("要结束这次飞行吗？")
        $fl_d_root.child[6].child[4].set_string("退出小游戏后，将继续麦与爱乃的原剧情。")
        $$fl_d_row(0, "进度", "当前这次飞行的进度不会保存。")
        $$fl_d_row(1, "继续", "还想留在天空中，就选择“继续飞行”。")
        $fl_d_root.child[6].child[12].set_string("Enter / Esc 取消退出　·　只有右侧按钮可确认退出")
        $$fl_d_button(0, 5, "继续飞行")
        $$fl_d_button(2, 4, "确认退出")
        if( $fl_pad_mode ) { $fl_d_root.child[6].child[12].set_string("B 取消退出　·　选中右侧按钮后按 A 才会确认退出") }
    }
}

command $$fl_d_speech_init
{
    $fl_d_root.child[7].disp = 0
    $fl_d_root.child[7].child.resize(5)
    $fl_d_root.child[7].child[0].create("_dialog_yesno_bg", 1, 30, 655)
    $fl_d_root.child[7].child[0].set_scale(1200, 1400)
    $fl_d_root.child[7].child[1].create($$get_bs_image_name("ai11_14"), 1, 180, 389)
    $fl_d_root.child[7].child[1].set_scale(380, 380)
    // Clip coordinates are relative to the sprite's anchor (1023, 0) on its canvas.
    $fl_d_root.child[7].child[1].src_clip_use = 1
    $fl_d_root.child[7].child[1].src_clip_left = -323
    $fl_d_root.child[7].child[1].src_clip_top = 700
    $fl_d_root.child[7].child[1].src_clip_right = 337
    $fl_d_root.child[7].child[1].src_clip_bottom = 1240
    $$fl_d_text($fl_d_root.child[7].child[2], "愛乃", 320, 683, 31, 21)
    $fl_d_root.child[7].child[2].set_string_param(31, 0, 0, 100, 21, 0, 0)
    $$fl_d_text($fl_d_root.child[7].child[3], "", 320, 735, 28, 8)
    $fl_d_root.child[7].child[3].set_string_param(28, 0, 0, 100, 8, 0, 0)
    $$fl_d_text($fl_d_root.child[7].child[4], "", 320, 790, 25, 8)
    $fl_d_root.child[7].child[4].set_string_param(25, 0, 0, 100, 8, 0, 0)
}

command $$fl_d_speech
{
    property $quote : str
    property $translation : str
    property $face : str
    $fl_d_root.child[7].disp = 0
    if( $fl_state != 1 || $fl_speech_id <= 0 || $fl_elapsed_ms >= $fl_speech_until ) { return }
    $fl_d_root.child[7].disp = 1
    if( $fl_d_speech_serial != $fl_speech_serial ) {
        $quote = ""
        $translation = ""
        $face = "ai11_14"
        switch( $fl_speech_id ) {
        case(1) $quote = "「離陸しますよ」"
            $translation = "要起飞了哦。"
        case(2) $quote = "「順調ですよ！！」"
            $translation = "一切顺利！！"
            $face = "ai11_15"
        case(3) $quote = "「旋回して戻りますよって！！」"
            $translation = "我们要转弯返回啦！！"
        case(4) $quote = "「じゃあ、着陸しますよ！」"
            $translation = "那么，要着陆了哦！"
        case(5) $quote = "「揺れますよ！」"
            $translation = "要颠簸了哦！"
        }
        $fl_d_root.child[7].child[1].change_file($$get_bs_image_name($face))
        $fl_d_root.child[7].child[3].set_string($quote)
        $fl_d_root.child[7].child[4].set_string($translation)
        $fl_d_speech_serial = $fl_speech_serial
    }
    $fl_d_root.child[7].tr = $$fl_d_clamp(($fl_speech_until - $fl_elapsed_ms) * 255 / 350, 0, 255)
}


// Eight-sided attitude gyro. Its airplane symbol stays fixed to the cockpit.
// Screen-space blue/brown strips are clipped analytically to the octagon,
// so bank cannot rotate a rectangular texture out over the neighboring HUD.
command $$fl_d_gyro_init
{
    property $i
    property $j
    property $dy
    property $half
    property $a
    property $b
    property $x1
    property $y1
    property $x2
    property $y2
    $fl_d_root.child[8].disp = 0
    $fl_d_root.child[8].child.resize(9)
    $fl_d_root.child[8].child[0].disp = 1
    $fl_d_root.child[8].child[1].disp = 1
    $fl_d_root.child[8].child[0].child.resize(80)
    $fl_d_root.child[8].child[1].child.resize(80)
    for( $i = 0, $i < 80, $i += 1 ) {
        $dy = -119 + $i * 3
        $half = 120
        if( math.abs($dy) > 50 ) { $half = 170 - math.abs($dy) }
        $fl_d_root.child[8].child[0].child[$i].create_rect(0, 0, 100, 3, 62, 132, 177, 255, 1)
        $fl_d_root.child[8].child[0].child[$i].set_pos(1728 - $half, 580 + $i * 3)
        $fl_d_root.child[8].child[0].child[$i].set_scale($half * 20, 1000)
        $fl_d_root.child[8].child[1].child[$i].create_rect(0, 0, 100, 3, 133, 91, 55, 255, 1)
        $fl_d_root.child[8].child[1].child[$i].disp = 0
    }
    $fl_d_root.child[8].child[2].disp = 1
    $fl_d_root.child[8].child[2].child.resize(15)
    for( $i = 0, $i < 10, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[8].child[2].child[$i]) }
    for( $i = 0, $i < 5, $i += 1 ) {
        $$fl_d_text($fl_d_root.child[8].child[2].child[10 + $i], math.tostr(($i - 2) * 10), 0, 0, 17, 0)
    }
    // A dark bezel behind the pale octagonal rim.
    $fl_d_root.child[8].child[3].disp = 1
    $fl_d_root.child[8].child[3].child.resize(16)
    for( $i = 0, $i < 16, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[8].child[3].child[$i]) }
    for( $i = 0, $i < 8, $i += 1 ) {
        $a = 225 + $i * 450
        $b = $a + 450
        $x1 = 1728 + math.cos($a, 130)
        $y1 = 700 + math.sin($a, 130)
        $x2 = 1728 + math.cos($b, 130)
        $y2 = 700 + math.sin($b, 130)
        $$fl_d_line2($fl_d_root.child[8].child[3].child[$i], $x1, $y1, $x2, $y2, 17, 17, 28, 34)
        $$fl_d_line2($fl_d_root.child[8].child[3].child[8 + $i], $x1, $y1, $x2, $y2, 4, 191, 205, 200)
    }
    // Fixed yellow miniature aircraft: wings, short tips and center chevron.
    $fl_d_root.child[8].child[4].disp = 1
    $fl_d_root.child[8].child[4].child.resize(6)
    for( $i = 0, $i < 6, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[8].child[4].child[$i]) }
    $$fl_d_line2($fl_d_root.child[8].child[4].child[0], 1673, 700, 1712, 700, 5, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[4].child[1], 1744, 700, 1783, 700, 5, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[4].child[2], 1673, 700, 1673, 709, 5, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[4].child[3], 1783, 700, 1783, 709, 5, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[4].child[4], 1720, 706, 1728, 699, 4, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[4].child[5], 1728, 699, 1736, 706, 4, 255, 218, 78)
    // Fixed roll scale: 0, +/-10, +/-20, +/-30 and +/-45 degrees.
    $fl_d_root.child[8].child[5].disp = 1
    $fl_d_root.child[8].child[5].child.resize(13)
    for( $i = 0, $i < 9, $i += 1 ) {
        $a = ($i - 4) * 100
        if( $i == 0 ) { $a = -450 }
        if( $i == 8 ) { $a = 450 }
        $$fl_d_line_init($fl_d_root.child[8].child[5].child[$i])
        $j = 127
        if( $i == 0 || $i == 1 || $i == 4 || $i == 7 || $i == 8 ) { $j = 124 }
        $$fl_d_line2($fl_d_root.child[8].child[5].child[$i],
            1728 + math.sin($a, $j), 700 - math.cos($a, $j),
            1728 + math.sin($a, 139), 700 - math.cos($a, 139), 2, 238, 238, 220)
    }
    $$fl_d_text($fl_d_root.child[8].child[5].child[9], "45", 1608, 586, 17, 0)
    $$fl_d_text($fl_d_root.child[8].child[5].child[10], "30", 1638, 558, 17, 0)
    $$fl_d_text($fl_d_root.child[8].child[5].child[11], "30", 1798, 558, 17, 0)
    $$fl_d_text($fl_d_root.child[8].child[5].child[12], "45", 1828, 586, 17, 0)
    $fl_d_root.child[8].child[6].disp = 1
    $fl_d_root.child[8].child[6].child.resize(3)
    for( $i = 0, $i < 3, $i += 1 ) { $$fl_d_line_init($fl_d_root.child[8].child[6].child[$i]) }
    // Centred over the dial and clear of the bank-scale numbers.
    $$fl_d_text($fl_d_root.child[8].child[7], "姿态仪", 1728 - 3 * 25 / 2, 520, 25, 0)
    $$fl_d_text($fl_d_root.child[8].child[8], "", 1595, 845, 21, 0)
    $fl_d_gyro_pitch = -9999
    $fl_d_gyro_roll = -9999
}

command $$fl_d_gyro_frame
{
    property $i
    property $dy
    property $half
    property $left
    property $right
    property $cut
    property $width
    property $pitch_y
    property $angle
    property $length
    property $ly
    property $x1
    property $y1
    property $x2
    property $y2
    property $x3
    property $y3
    property $x4
    property $y4
    property $visible
    $fl_d_root.child[8].disp = ($fl_state == 1)
    if( $fl_state != 1 ) { return }
    $pitch_y = $fl_pitch * 4 / 10
    // Horizon normal is (sin(bank), cos(bank)). Positive pitch lowers it;
    // positive right bank lifts the right horizon edge. No auto-steering.
    for( $i = 0, $i < 80, $i += 1 ) {
        $dy = -119 + $i * 3
        $half = 120
        if( math.abs($dy) > 50 ) { $half = 170 - math.abs($dy) }
        $left = -$half
        $right = $half
        if( $fl_d_sin_r > 5 ) {
            $cut = ($pitch_y * 1000 - $dy * $fl_d_cos_r) / $fl_d_sin_r
            $left = $$fl_d_clamp($cut, -$half, $half)
        }
        elseif( $fl_d_sin_r < -5 ) {
            $cut = ($pitch_y * 1000 - $dy * $fl_d_cos_r) / $fl_d_sin_r
            $right = $$fl_d_clamp($cut, -$half, $half)
        }
        elseif( $dy < $pitch_y ) { $right = $left }
        $width = $right - $left
        $fl_d_root.child[8].child[1].child[$i].disp = ($width > 0)
        if( $width > 0 ) {
            $fl_d_root.child[8].child[1].child[$i].set_pos(1728 + $left, 580 + $i * 3)
            $fl_d_root.child[8].child[1].child[$i].set_scale($width * 10, 1000)
        }
    }
    // Five pitch-ladder levels. The centered aircraft symbol never rotates.
    for( $i = 0, $i < 5, $i += 1 ) {
        $angle = ($i - 2) * 100
        $ly = ($fl_pitch - $angle) * 4 / 10
        $length = 45
        if( $i == 0 || $i == 4 ) { $length = 63 }
        if( $i == 2 ) { $length = 98 }
        $x1 = 0 - $length
        $y1 = $ly
        $x2 = $length
        $y2 = $ly
        $x3 = ($x1 * $fl_d_cos_r + $y1 * $fl_d_sin_r) / 1000
        $y3 = ($y1 * $fl_d_cos_r - $x1 * $fl_d_sin_r) / 1000
        $x4 = ($x2 * $fl_d_cos_r + $y2 * $fl_d_sin_r) / 1000
        $y4 = ($y2 * $fl_d_cos_r - $x2 * $fl_d_sin_r) / 1000
        $visible = (math.abs($x3) < 115 && math.abs($y3) < 115 && math.abs($x3) + math.abs($y3) < 168 &&
                    math.abs($x4) < 115 && math.abs($y4) < 115 && math.abs($x4) + math.abs($y4) < 168)
        $fl_d_root.child[8].child[2].child[$i * 2].disp = 0
        $fl_d_root.child[8].child[2].child[$i * 2 + 1].disp = 0
        // The number sits left of the rung (26 x 17 px box); show it only when the whole
        // box is inside the dial, never half under the bezel.
        $x1 = math.max(math.abs($x3 - 18), math.abs($x3 + 8))
        $y1 = math.max(math.abs($y3 - 11), math.abs($y3 + 6))
        $fl_d_root.child[8].child[2].child[10 + $i].disp = ($visible && $x1 < 112 && $y1 < 112 && $x1 + $y1 < 158)
        if( $visible ) {
            $$fl_d_line2($fl_d_root.child[8].child[2].child[$i * 2],
                1728 + $x3, 700 + $y3, 1728 + ($ly * $fl_d_sin_r - 8 * $fl_d_cos_r) / 1000,
                700 + ($ly * $fl_d_cos_r + 8 * $fl_d_sin_r) / 1000, 2, 244, 245, 226)
            $$fl_d_line2($fl_d_root.child[8].child[2].child[$i * 2 + 1],
                1728 + ($ly * $fl_d_sin_r + 8 * $fl_d_cos_r) / 1000,
                700 + ($ly * $fl_d_cos_r - 8 * $fl_d_sin_r) / 1000, 1728 + $x4, 700 + $y4, 2, 244, 245, 226)
            $fl_d_root.child[8].child[2].child[10 + $i].set_pos(1710 + $x3, 689 + $y3)
        }
    }
    // Moving triangle reads right-bank positive against the fixed roll scale.
    $x1 = 1728 + math.sin($fl_roll, 121)
    $y1 = 700 - math.cos($fl_roll, 121)
    $x2 = 1728 + math.sin($fl_roll - 35, 109)
    $y2 = 700 - math.cos($fl_roll - 35, 109)
    $x3 = 1728 + math.sin($fl_roll + 35, 109)
    $y3 = 700 - math.cos($fl_roll + 35, 109)
    $$fl_d_line2($fl_d_root.child[8].child[6].child[0], $x1, $y1, $x2, $y2, 3, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[6].child[1], $x2, $y2, $x3, $y3, 3, 255, 218, 78)
    $$fl_d_line2($fl_d_root.child[8].child[6].child[2], $x3, $y3, $x1, $y1, 3, 255, 218, 78)
    if( $fl_d_gyro_pitch != $fl_pitch || $fl_d_gyro_roll != $fl_roll ) {
        $fl_d_root.child[8].child[8].set_string("俯仰 " + math.tostr($fl_pitch / 10) + "° / 坡度 " + math.tostr($fl_roll / 10) + "°")
        $fl_d_gyro_pitch = $fl_pitch
        $fl_d_gyro_roll = $fl_roll
    }
}

command $$fl_d_flight_reset
{
	$fl_d_toast_until = 0
	$fl_d_gate_seen = 0
	$fl_d_touch_seen = 0
	$fl_d_hud_time = -1
	$fl_d_root.child[4].child[9].disp = 0
	$fl_d_root.child[4].child[10].set_string("")
	$fl_d_root.child[4].child[11].disp = 0
	$fl_d_root.child[4].child[12].set_string("")
	$fl_d_root.child[4].child[12].disp = 0
	$fl_d_root.child[4].child[41].disp = 0
	$fl_d_root.child[4].child[42].disp = 0
	$fl_d_root.child[7].disp = 0
}

command $$fl_draw_frame
{
	$fl_d_cos_h = math.cos($fl_heading, 1000)
	$fl_d_sin_h = math.sin($fl_heading, 1000)
	$fl_d_cos_p = math.cos($fl_pitch, 1000)
	$fl_d_sin_p = math.sin($fl_pitch, 1000)
	$fl_d_cos_r = math.cos($fl_roll, 1000)
	$fl_d_sin_r = math.sin($fl_roll, 1000)
	$fl_d_root.child[0].set_pos(960, 395 + math.tan($fl_pitch, 850))
	$fl_d_root.child[0].rotate_z = 0 - $fl_roll
	// A restart rewinds the flight clock: drop every timed message of the last flight,
	// whose end times would otherwise lie in the new flight's future.
	if( $fl_elapsed_ms < $fl_d_last_ms ) { $$fl_d_flight_reset }
	$fl_d_last_ms = $fl_elapsed_ms
	$$fl_d_world
	$$fl_d_marks
	$$fl_d_turbines
	$$fl_d_gates
	if( $fl_d_hud_time != $fl_elapsed_ms / 100 || $fl_d_state != $fl_state || $fl_d_pad_seen != $fl_pad_mode ) {
		$$fl_d_hud
		$fl_d_hud_time = $fl_elapsed_ms / 100
	}
	if( $fl_d_state != $fl_state || $fl_d_pad_seen != $fl_pad_mode ) {
		$$fl_d_overlay
		$fl_d_state = $fl_state
		$fl_d_pad_seen = $fl_pad_mode
	}
	if( $fl_state != 1 ) { $$fl_d_button_hover }
	$$fl_d_speech
	$$fl_d_gyro_frame
}