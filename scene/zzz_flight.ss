// Optional Aino first-flight activity. ADV input stays isolated until key release.
// Keyboard, mouse and gamepad all work; the gamepad uses the game's joypad library.
#inc_start
    #property $fl_clock_last
    #property $fl_clock_accum
    #property $fl_clock_now
    #property $fl_frame_state
    #property $fl_menu_action
    #property $fl_menu_stamp
    #property $fl_exit_from
    #property $fl_old_flags : intlist
    #command $$fl_controls_enter
    #command $$fl_controls_leave
    #command $$fl_menu_step
#inc_end

#z00
close
$fl_active = 1
$fl_completed = 0
koe_stop(100)
@揺れループ停止
@集中線終了
@all_sound_stop(200)
$$fl_sound_clear
$$fl_controls_enter
$$fl_sim_init
$fl_state = 0
$fl_speech_id = 0
$fl_speech_until = 0
$$fl_draw_init
counter[0].start_real
$fl_clock_last = counter[0].get
$fl_clock_accum = 0
$fl_menu_stamp = $fl_clock_last
$fl_pad_focus = 0
$fl_pad_mx = mouse.get_pos_x
$fl_pad_my = mouse.get_pos_y
if( syscom.check_joypad_mode ) { $fl_pad_mode = 1 }
keyboard.clear
input.clear

while( $fl_state != 5 )
{
    $fl_frame_state = $fl_state
    $fl_clock_now = counter[0].get
    $fl_menu_action = 0
    $fl_pad_press = 0
    $$fl_pad_poll
    // A new state never inherits the click/key which opened it.
    if( $fl_clock_now - $fl_menu_stamp >= 250 ) {
        $fl_menu_action = $$fl_ui_action
        // A gamepad press stands for a panel button (or 6: pause while flying).
        $fl_pad_press = $$fl_pad_action
        if( $fl_pad_press != 0 ) { $fl_menu_action = $fl_pad_press }
        $$fl_menu_step
    }
    if( $fl_state == 1 && $fl_frame_state == 1 )
    {
        $fl_clock_accum += math.min($fl_clock_now - $fl_clock_last, 200)
        $fl_in_pitch = 0
        $fl_in_roll = 0
        $fl_in_throttle = 0
        // Gamepad: D-pad or left stick like the arrow keys, RT / LT or the right stick
        // like Q / A, and B brakes like the B key.
        $fl_in_brake = key['B'].is_down || joypad.key[<JOYPAD_BUTTON2>].is_down
        if( key[38].is_down || joypad.key[<JOYPAD_UP>].is_down || joypad.key[<JOYPAD_LSTICK_UP>].is_down ) { $fl_in_pitch -= 1 }
        if( key[40].is_down || joypad.key[<JOYPAD_DOWN>].is_down || joypad.key[<JOYPAD_LSTICK_DOWN>].is_down ) { $fl_in_pitch += 1 }
        if( key[37].is_down || joypad.key[<JOYPAD_LEFT>].is_down || joypad.key[<JOYPAD_LSTICK_LEFT>].is_down ) { $fl_in_roll -= 1 }
        if( key[39].is_down || joypad.key[<JOYPAD_RIGHT>].is_down || joypad.key[<JOYPAD_LSTICK_RIGHT>].is_down ) { $fl_in_roll += 1 }
        if( key['Q'].is_down || joypad.key[<JOYPAD_R2>].is_down || joypad.key[<JOYPAD_RSTICK_UP>].is_down ) { $fl_in_throttle += 1 }
        if( key['A'].is_down || joypad.key[<JOYPAD_L2>].is_down || joypad.key[<JOYPAD_RSTICK_DOWN>].is_down ) { $fl_in_throttle -= 1 }
        while( $fl_clock_accum >= 20 && $fl_state == 1 ) {
            $$fl_sim_step
            $fl_clock_accum -= 20
        }
        $$fl_sound_step
    }
    else { $fl_clock_accum = 0 }
    if( $fl_state != $fl_frame_state ) {
        $fl_menu_stamp = $fl_clock_now
        $fl_pad_focus = 0
        input.clear
    }
    $fl_clock_last = $fl_clock_now
    if( $fl_state != 5 ) { $$fl_draw_frame }
    input.next
    disp
}

$$fl_sound_clear
// Consume flight and confirmation keys BEFORE restoring the story input; the same for
// gamepad buttons, so the A that left the panel cannot also advance the story text.
while( key[13].is_down || key[32].is_down || key[27].is_down || key[17].is_down ||
       key[37].is_down || key[38].is_down || key[39].is_down || key[40].is_down ||
       key['Q'].is_down || key['A'].is_down || key['P'].is_down || key['R'].is_down || key['B'].is_down ||
       mouse.left.is_down || mouse.right.is_down || $fl_pad_held )
{
    input.next
    disp
    $$fl_pad_poll
}
input.clear
keyboard.clear
$$fl_draw_clear
$$fl_controls_leave
$fl_active = 0
return

// Keys count only in frames without a gamepad press, so a pad button that the engine
// might also report as a key can never trigger a second, different action.
command $$fl_menu_step
{
    if( $fl_state == 0 ) {
        if( ($fl_pad_press == 0 && key[13].on_down) || $fl_menu_action == 1 ) {
            $fl_state = 1
            $$fl_sound_reset
        }
        elseif( ($fl_pad_press == 0 && key[27].on_down) || $fl_menu_action == 3 ) {
            $fl_exit_from = 0
            $fl_state = 6
        }
    }
    elseif( $fl_state == 1 ) {
        // ADV buttons, mouse clicks, Space and Ctrl do nothing while flying.
        if( ($fl_pad_press == 0 && (key['P'].on_down || key[27].on_down)) || $fl_menu_action == 6 ) {
            $fl_state = 2
            $$fl_sound_pause
        }
    }
    elseif( $fl_state == 2 ) {
        if( ($fl_pad_press == 0 && (key['P'].on_down || key[13].on_down)) || $fl_menu_action == 1 ) {
            $fl_state = 1
            $$fl_sound_resume
        }
        elseif( ($fl_pad_press == 0 && key['R'].on_down) || $fl_menu_action == 2 ) {
            $$fl_sim_init
            $$fl_sound_reset
        }
        elseif( ($fl_pad_press == 0 && key[27].on_down) || $fl_menu_action == 3 ) {
            $fl_exit_from = 2
            $fl_state = 6
        }
    }
    elseif( $fl_state == 3 ) {
        if( ($fl_pad_press == 0 && key['R'].on_down) || $fl_menu_action == 2 ) {
            $$fl_sim_init
            $$fl_sound_reset
        }
        elseif( ($fl_pad_press == 0 && key[13].on_down) || $fl_menu_action == 1 ) {
            $fl_completed = 1
            $fl_state = 5
        }
    }
    elseif( $fl_state == 4 ) {
        // On failure Enter retries; it cannot accidentally advance the story.
        if( ($fl_pad_press == 0 && (key['R'].on_down || key[13].on_down)) || $fl_menu_action == 2 ) {
            $$fl_sim_init
            $$fl_sound_reset
        }
        elseif( ($fl_pad_press == 0 && key[27].on_down) || $fl_menu_action == 1 || $fl_menu_action == 3 ) {
            $fl_exit_from = 4
            $fl_state = 6
            $$fl_sound_pause
        }
    }
    elseif( $fl_state == 6 ) {
        // Only the visible confirmation button authorizes leaving the activity
        // (clicked, or focused with the gamepad and pressed with A).
        if( $fl_menu_action == 4 ) { $fl_state = 5 }
        elseif( ($fl_pad_press == 0 && (key[27].on_down || key[13].on_down)) || $fl_menu_action == 5 ) {
            $fl_state = $fl_exit_from
        }
    }
}

// Gamepad state for this frame, read through the game's joypad library (its key-repeat
// table feeds $$joypad_left_on_down / $$joypad_right_on_down in the panels). Any pad
// press switches the on-screen hints to pad labels; keyboard keys or the mouse switch back.
command $$fl_pad_poll
{
    property $i
    $$update_joypad_key_repeat
    if( key[13].on_down || key[27].on_down || key[32].on_down || key['Q'].on_down || key['A'].on_down ||
        key['B'].on_down || key['P'].on_down || key['R'].on_down || mouse.left.on_down ||
        math.abs(mouse.get_pos_x - $fl_pad_mx) + math.abs(mouse.get_pos_y - $fl_pad_my) > 8 ) {
        $fl_pad_mode = 0
    }
    $fl_pad_mx = mouse.get_pos_x
    $fl_pad_my = mouse.get_pos_y
    $fl_pad_held = 0
    for( $i = 0, $i < <JOYPAD_MAX>, $i += 1 ) {
        if( joypad.key[$i].on_down ) { $fl_pad_mode = 1 }
        // Buttons only: a drifting stick must never hold the story back.
        if( $i >= <JOYPAD_BUTTON1> && $i <= <JOYPAD_EX2> && joypad.key[$i].is_down ) { $fl_pad_held = 1 }
    }
}

command $$fl_controls_enter
{
    $fl_old_flags.resize(11)
    $fl_old_flags[0] = script.get_skip_disable_flag
    $fl_old_flags[1] = script.get_ctrl_skip_disable_flag
    $fl_old_flags[2] = script.get_mwnd_disp_off_flag
    $fl_old_flags[3] = script.get_allow_joypad_mode_onoff
    $fl_old_flags[4] = syscom.get_read_skip_enable_flag
    $fl_old_flags[5] = syscom.get_auto_skip_enable_flag
    $fl_old_flags[6] = syscom.get_auto_mode_enable_flag
    $fl_old_flags[7] = syscom.get_msg_back_enable_flag
    $fl_old_flags[8] = syscom.get_save_enable_flag
    $fl_old_flags[9] = syscom.get_load_enable_flag
    $fl_old_flags[10] = syscom.get_hide_mwnd_enable_flag
    script.end_auto_mode
    syscom.set_auto_mode_onoff_flag(0)
    syscom.set_read_skip_onoff_flag(0)
    syscom.set_auto_skip_onoff_flag(0)
    syscom.set_read_skip_enable_flag(0)
    syscom.set_auto_skip_enable_flag(0)
    syscom.set_auto_mode_enable_flag(0)
    syscom.set_msg_back_enable_flag(0)
    syscom.set_save_enable_flag(0)
    syscom.set_load_enable_flag(0)
    syscom.set_hide_mwnd_enable_flag(0)
    syscom.set_syscom_menu_disable
    syscom.set_mwnd_btn_disable
    syscom.set_mwnd_btn_touch_disable
    script.set_mwnd_disp_off_flag(1)
    script.set_skip_disable
    script.set_end_msg_by_key_disable
    script.set_mouse_move_by_key_disable
    // Gamepad mode allowed, as the game's own minigames and menus do. The system-menu
    // and shortcut locks stay on, so pad buttons are meant for the flight alone.
    script.set_allow_joypad_mode_onoff(1)
    script.set_msg_back_disable
    script.set_shortcut_disable
    script.set_ctrl_skip_disable
    script.set_auto_savepoint_off
}

command $$fl_controls_leave
{
    script.set_auto_savepoint_on
    script.set_skip_disable_flag($fl_old_flags[0])
    script.set_ctrl_skip_disable_flag($fl_old_flags[1])
    script.set_mwnd_disp_off_flag($fl_old_flags[2])
    script.set_allow_joypad_mode_onoff($fl_old_flags[3])
    script.set_end_msg_by_key_enable
    script.set_mouse_move_by_key_enable
    script.set_msg_back_enable
    script.set_shortcut_enable
    syscom.set_read_skip_enable_flag($fl_old_flags[4])
    syscom.set_auto_skip_enable_flag($fl_old_flags[5])
    syscom.set_auto_mode_enable_flag($fl_old_flags[6])
    syscom.set_msg_back_enable_flag($fl_old_flags[7])
    syscom.set_save_enable_flag($fl_old_flags[8])
    syscom.set_load_enable_flag($fl_old_flags[9])
    syscom.set_hide_mwnd_enable_flag($fl_old_flags[10])
    syscom.set_mwnd_btn_enable
    syscom.set_mwnd_btn_touch_enable
    syscom.set_syscom_menu_enable
    input.clear
}
