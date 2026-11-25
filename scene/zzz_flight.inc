// Optional first-flight minigame. Units: cm, cm/s, tenths of degrees.
// 0 degrees is +Z; a positive heading/roll turns right. Fixed step: 20 ms.
#property $fl_x
#property $fl_active
#property $fl_completed
#property $fl_test_entry
#property $fl_test_save
#property $fl_z
#property $fl_alt
#property $fl_speed
#property $fl_vspeed
#property $fl_heading
#property $fl_pitch
#property $fl_roll
#property $fl_throttle
#property $fl_in_pitch
#property $fl_in_roll
#property $fl_in_throttle
#property $fl_state
#property $fl_phase
#property $fl_airborne
#property $fl_max_alt
#property $fl_step_ticks
#property $fl_elapsed_ms
#property $fl_turn_rem
#property $fl_turn_total
#property $fl_route_mask
#property $fl_gate_index
#property $fl_gate_count
#property $fl_gate_x : intlist
#property $fl_gate_z : intlist
#property $fl_gate_y : intlist
#property $fl_gate_heading : intlist
#property $fl_gate_radius : intlist
#property $fl_gate_phase : intlist
#property $fl_gate_result : intlist
#property $fl_gate_points
#property $fl_gate_hits
#property $fl_gate_misses
#property $fl_last_precision
#property $fl_gate_event
#property $fl_landing_points
#property $fl_total
#property $fl_touch_fpm
#property $fl_touch_speed
#property $fl_touch_roll
#property $fl_touched
#property $fl_landing_ticks
#property $fl_fail_reason
#property $fl_stall
#command $$fl_sim_init
#command $$fl_sim_step
#command $$fl_gate_set(int, int, int, int, int, int, int)
#command $$fl_check_gates(int, int, int)
#command $$fl_touchdown
#command $$fl_clamp(int, int, int) : int
#command $$fl_draw_init
#command $$fl_draw_frame
#command $$fl_draw_clear

// Append v2 data to preserve all v1 global-property indices.
#property $fl_speech_id
#property $fl_speech_until
#property $fl_speech_serial
#command $$fl_ui_action : int
#command $$fl_sound_reset
#command $$fl_sound_step
#command $$fl_sound_pause
#command $$fl_sound_resume
#command $$fl_sound_clear

// Append v5 aerodynamic state after all v1/v2 indices.
#property $fl_gamma
#property $fl_gamma_rem
#property $fl_speed_rem
#property $fl_x_rem
#property $fl_z_rem
#property $fl_alt_rem
#property $fl_pitch_rem
#property $fl_roll_rem
#property $fl_aoa
#property $fl_lift

// Append v6 brakes and touchdown accuracy after all earlier indices.
#property $fl_in_brake
#property $fl_touch_x
#property $fl_touch_z
#property $fl_center_points
#property $fl_aim_points

// Append v7 ground steering after all earlier indices.
#property $fl_steer
#property $fl_steer_rem

// Append v8 gamepad after all earlier indices: the device last used (1 = pad), the
// focused panel button, this frame's pad action, held pad buttons and the mouse position.
#property $fl_pad_mode
#property $fl_pad_focus
#property $fl_pad_press
#property $fl_pad_held
#property $fl_pad_mx
#property $fl_pad_my
#property $fl_d_pad_seen
#command $$fl_pad_poll
#command $$fl_pad_action : int
