// Original story music + original audio assets. No additional runtime library.
// Engine low/mid/high loops share source audio; standard Vorbis sample-rate
// variants give actual RPM/pitch changes, blended continuously with throttle.
// Channels: 1 wheel brakes, 2 low motor, 3 original motor, 4 ground roll, 5 high motor,
//           6 one-shot aircraft effects (first contact has absolute priority),
//           7 Aino's original voice, respecting the character voice category.
#inc_start
    #property $fl_a_started
    #property $fl_a_bgm_started
    #property $fl_a_paused
    #property $fl_a_finished
    #property $fl_a_airborne
    #property $fl_a_touch
    #property $fl_a_propeller
    #property $fl_a_turned
    #property $fl_a_approach
    #property $fl_a_landing_warning
    #property $fl_a_rolling
    #property $fl_a_low_volume
    #property $fl_a_mid_volume
    #property $fl_a_high_volume
    #property $fl_a_roll_volume
    #property $fl_a_braking
    #command $$fl_engine_mix
    #command $$fl_ground_sound
    #command $$fl_speech(int)
#inc_end

#z00
return

command $$fl_speech(property $id)
{
    property $no
    property $length
    $no = 0
    $length = 0
    // Actual Vorbis durations + a short readable subtitle tail (400ms).
    // 1 離陸しますよ / 2 順調ですよ！！ / 3 旋回して戻りますよって！！
    // 4 じゃあ、着陸しますよ！ / 5 揺れますよ！
    switch( $id ) {
    case(1) $no = 300700195
        $length = 1678
    case(2) $no = 300700214
        $length = 1712
    case(3) $no = 300700274
        $length = 3261
    case(4) $no = 300700313
        $length = 2713
    case(5) $no = 300700331
        $length = 1718
    }
    if( $no == 0 ) { return }
    pcmch[7].play(koe_no = $no, volume_type = 1, chara_no = 2)
    $fl_speech_id = $id
    $fl_speech_until = $fl_elapsed_ms + $length
    $fl_speech_serial += 1
}

command $$fl_sound_reset
{
    // Retries restart only aircraft sounds; the story music keeps its phrase.
    pcmch[1].stop(0)
    pcmch[2].stop(0)
    pcmch[3].stop(0)
    pcmch[4].stop(0)
    pcmch[5].stop(0)
    pcmch[6].stop(0)
    pcmch[7].stop(0)
    if( $fl_a_bgm_started == 0 ) {
        // 030_愛乃0813 original line 387: airborne sightseeing uses this BGM.
        @bgm(bgm27, 1200)
        $fl_a_bgm_started = 1
    }
    elseif( $fl_a_paused ) { bgm.resume(150) }
    $fl_a_started = 1
    $fl_a_paused = 0
    $fl_a_finished = 0
    $fl_a_airborne = 0
    $fl_a_touch = 0
    $fl_a_propeller = 0
    $fl_a_turned = 0
    $fl_a_approach = 0
    $fl_a_landing_warning = 0
    $fl_a_rolling = 0
    $fl_a_low_volume = -1
    $fl_a_mid_volume = -1
    $fl_a_high_volume = -1
    $fl_a_roll_volume = -1
    $fl_a_braking = 0
    $fl_speech_id = 0
    $fl_speech_until = 0
    pcmch[2].set_volume(0)
    pcmch[3].set_volume(0)
    pcmch[5].set_volume(0)
    pcmch[2].play("FL_engine_low", loop = 1)
    pcmch[3].play("ANB_airplane_motor_LOOP", loop = 1)
    pcmch[5].play("FL_engine_high", loop = 1)
    pcmch[6].set_volume(220)
    pcmch[6].play("SE_elec_plane_engine_start", fade = 100)
    $$fl_engine_mix
    $$fl_speech(1)
}

command $$fl_engine_mix
{
    property $t
    property $level
    property $low
    property $mid
    property $high
    if( $fl_a_started == 0 || $fl_a_finished || $fl_a_paused ) { return }
    $t = $$fl_clamp($fl_throttle, 0, 1000)
    $level = 72 + $t * 178 / 1000
    $low = 0
    $mid = 0
    $high = 0
    if( $t <= 500 ) {
        $low = $level * (1000 - $t * 2) / 1000
        $mid = $level * $t * 2 / 1000
    } else {
        $mid = $level * (2000 - $t * 2) / 1000
        $high = $level * ($t * 2 - 1000) / 1000
    }
    if( $fl_a_low_volume != $low ) {
        pcmch[2].set_volume($low, 160)
        $fl_a_low_volume = $low
    }
    if( $fl_a_mid_volume != $mid ) {
        pcmch[3].set_volume($mid, 160)
        $fl_a_mid_volume = $mid
    }
    if( $fl_a_high_volume != $high ) {
        pcmch[5].set_volume($high, 160)
        $fl_a_high_volume = $high
    }
}

command $$fl_ground_sound
{
    property $rolling
    property $volume
    $rolling = 0
    if( ($fl_airborne == 0 || $fl_touched) && $fl_speed > 100 && $fl_state == 1 ) {
        $rolling = 1
    }
    if( $rolling && $fl_a_rolling == 0 ) {
        pcmch[4].set_volume(0)
        pcmch[4].play("SE_elec_plane_runway_roll", loop = 1)
        $fl_a_rolling = 1
        $fl_a_roll_volume = -1
    }
    if( $rolling ) {
        $volume = $$fl_clamp(25 + $fl_speed * 130 / 3000, 25, 175)
        if( $fl_a_roll_volume != $volume ) {
            pcmch[4].set_volume($volume, 120)
            $fl_a_roll_volume = $volume
        }
    }
    elseif( $fl_a_rolling ) {
        pcmch[4].stop(180)
        $fl_a_rolling = 0
        $fl_a_roll_volume = -1
    }
}

command $$fl_sound_step
{
    if( $fl_a_started == 0 || $fl_a_paused ) { return }
    $$fl_engine_mix
    $$fl_ground_sound
    // Wheel brakes: the game's own brake squeal once as B goes down on the landing
    // roll; released brakes or a stopped aircraft fade it out.
    if( $fl_touched && $fl_in_brake && $fl_speed > 260 && $fl_state == 1 ) {
        if( $fl_a_braking == 0 ) {
            pcmch[1].set_volume(200)
            pcmch[1].play("SE_bike_brake")
            $fl_a_braking = 1
        }
    }
    elseif( $fl_a_braking ) {
        pcmch[1].stop(150)
        $fl_a_braking = 0
    }
    // A crash can change state during the same simulation tick as first contact.
    // Handle contact first, once, and return: no takeoff/start/approach sound can
    // overwrite the impact on channel 6 in this frame.
    if( $fl_touched && $fl_a_touch == 0 ) {
        $fl_a_touch = 1
        pcmch[6].set_volume(245)
        if( math.abs($fl_touch_fpm) > 500 ) {
            pcmch[6].play("SE_plane_land_rattle")
        } else {
            pcmch[6].play("SE_plane_land")
        }
        if( $fl_state == 3 || $fl_state == 4 ) {
            pcmch[2].stop(500)
            pcmch[3].stop(500)
            pcmch[5].stop(500)
            pcmch[4].stop(200)
            $fl_a_finished = 1
        }
        return
    }
    // Stop once at the end; repeated stop(fade) calls would keep restarting fade.
    if( $fl_state == 3 || $fl_state == 4 ) {
        if( $fl_a_finished == 0 ) {
            pcmch[2].stop(500)
            pcmch[3].stop(500)
            pcmch[5].stop(500)
            pcmch[4].stop(200)
            $fl_a_finished = 1
        }
        return
    }
    if( $fl_a_touch ) { return }
    // Transition latches follow physical flight, not a fragile exact phase match.
    if( $fl_airborne && $fl_a_airborne == 0 ) {
        $fl_a_airborne = 1
        pcmch[6].set_volume(220)
        pcmch[6].play("SE_elec_plane_takeoff")
        $$fl_speech(2)
        return
    }
    if( $fl_a_airborne && $fl_phase >= 5 && $fl_a_approach == 0 ) {
        $fl_a_approach = 1
        $fl_a_turned = 1
        pcmch[6].play("SE_elec_altitude_descend")
        $$fl_speech(4)
        return
    }
    if( $fl_a_approach && $fl_alt < 600 && $fl_vspeed < 0 && $fl_a_landing_warning == 0 ) {
        $fl_a_landing_warning = 1
        $$fl_speech(5)
        return
    }
    if( $fl_a_airborne && $fl_phase >= 2 && $fl_a_turned == 0 ) {
        $fl_a_turned = 1
        $$fl_speech(3)
        return
    }
    if( $fl_a_propeller == 0 && $fl_a_airborne == 0 && $fl_elapsed_ms > 2200 ) {
        $fl_a_propeller = 1
        pcmch[6].play("SE_elec_plane_propeller_start")
    }
}

command $$fl_sound_pause
{
    if( $fl_a_started == 0 || $fl_a_paused ) { return }
    pcmch[1].pause(100)
    pcmch[2].pause(100)
    pcmch[3].pause(100)
    pcmch[4].pause(100)
    pcmch[5].pause(100)
    pcmch[6].pause(100)
    pcmch[7].pause(100)
    bgm.pause(180)
    $fl_a_paused = 1
}

command $$fl_sound_resume
{
    if( $fl_a_started == 0 || $fl_a_paused == 0 ) { return }
    pcmch[1].resume(100)
    pcmch[2].resume(100)
    pcmch[3].resume(100)
    pcmch[4].resume(100)
    pcmch[5].resume(100)
    pcmch[6].resume(100)
    pcmch[7].resume(100)
    bgm.resume(180)
    $fl_a_paused = 0
}

command $$fl_sound_clear
{
    pcmch[1].stop(150)
    $fl_a_braking = 0
    pcmch[2].stop(200)
    pcmch[3].stop(200)
    pcmch[4].stop(200)
    pcmch[5].stop(200)
    pcmch[6].stop(200)
    pcmch[7].stop(150)
    if( $fl_a_bgm_started ) { @bgm_stop(400) }
    $fl_a_started = 0
    $fl_a_bgm_started = 0
    $fl_a_paused = 0
    $fl_speech_id = 0
    $fl_speech_until = 0
    $fl_speech_serial += 1
}
