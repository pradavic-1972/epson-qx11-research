; ============================================================================
; QX11_INVADERS_GOLD_V1.ASM
; Epson QX-11 Invaders GOLD v1.0
; NASM DOS .COM, 8086 compatible
;
; Completes four alien-engine features:
;   1. Dynamic left/right formation edges from living columns
;   2. Survivor-count-based speed table (fewer aliens = faster)
;   3. Bottom-most living alien lookup for 0EACh of 11 columns
;   4. Generic sprite draw/clear routines used by aliens and explosions
;
; Also retained:
;   - 55 aliens in a 5 x 11 formation
;   - Shared formation X/Y and direction
;   - Two animation frames per alien type
;   - Edge drop, direction reversal, and gradual depth acceleration
;   - Player bullet collision and alien explosions
;
; QX-11 640x200 planar color mode:
;   offset = Y*0100h + X_byte
;   Blue  = 8000h
;   Red   = 8008h
;   Green = 9000h
;
; Build:
;   nasm -f bin QX11_INVADERS_GOLD_V1.ASM -o QXINVJ.COM
;
; Left/Right arrows move the player ship. SPACE fires. ESC exits.
; One enemy shot at a time is fired by the lowest living alien in a column.
; Four destructible bunkers absorb both player and enemy shots.
; A mystery UFO periodically crosses the top and awards a bonus when hit.
; ============================================================================

BITS 16
CPU 8086
ORG 100h

QX_BLUE_SEG       equ 08000h
QX_RED_SEG        equ 08008h
QX_GREEN_SEG      equ 09000h
GAVDP_HORIGIN       equ 0C462h    ; physical address 8C462h
GAVDP_VORIGIN       equ 0C663h    ; physical address 8C663h
SHAKE_AMOUNT         equ 02h
PLAYER_SHAKE_TICKS  equ 18
UFO_RED_FLASH_TICKS equ 10
SOUND_PORT         equ 014h       ; SN76489AN

SPRITE_BYTES      equ 3
SPRITE_ROWS       equ 13
ALIENS_PER_ROW    equ 11
FORMATION_ROWS    equ 5
ALIEN_COUNT       equ 55

X_SPACING_BYTES   equ 5           ; 40 pixels between alien origins
Y_SPACING         equ 20
LEFT_SCREEN_EDGE  equ 4           ; leave 32-pixel margin
RIGHT_SCREEN_EDGE equ 76          ; right edge before 4-byte margin
START_X_BYTE      equ 12
START_Y           equ 10
BOTTOM_LIMIT      equ 112
DROP_ROWS         equ 4

; Slow enough to see two-frame animation on the real QX-11.
ALIEN_START_PERIOD equ 60       ; INT 71h ticks between formation steps
ALIEN_MIN_PERIOD   equ 24        ; fastest allowed formation period
DEPTH_PERIOD_DIV   equ 4        ; subtract one tick every two downward drops
; INT 71h is about 388.8 Hz on real hardware. These periods are intentionally
; conservative for first hardware testing and can be tuned after observation.

KILL_INTERVAL     equ 14
EXPLOSION_STEPS   equ 128          ; INT 71h ticks, independent of fleet motion
ALIEN_EXP_BYTES   equ 5
ALIEN_EXP_ROWS    equ 22

COLOR_MAGENTA     equ 3
COLOR_CYAN        equ 5
COLOR_GREEN       equ 4
COLOR_YELLOW      equ 6

SHIP_BYTES        equ 3
SHIP_ROWS         equ 16
SHIP_START_X      equ 38          ; byte coordinate, 24-pixel ship
SHIP_Y            equ 180
SHIP_LEFT_EDGE    equ 1
SHIP_RIGHT_EDGE   equ 76          ; 76 + 3 bytes = byte 79

BULLET_ROWS       equ 4
BULLET_MASK       equ 018h        ; two centered pixels in one QX byte
BULLET_STEP       equ 2           ; move upward two scanlines per update
BULLET_TICK_DIV   equ 6           ; update once per three INT 71h ticks
BULLET_TOP        equ 2

ENEMY_BULLET_ROWS      equ 5
ENEMY_BULLET_MASK      equ 018h
ENEMY_BULLET_STEP      equ 2
ENEMY_BULLET_TICK_DIV  equ 10
ENEMY_FIRE_MIN         equ 360     ; minimum INT 71h ticks between shots
ENEMY_FIRE_RANGE       equ 440     ; additional pseudo-random ticks, 0..439
ENEMY_BULLET_BOTTOM    equ 198
PLAYER_EXPLOSION_TICKS equ 240     ; approximately 0.62 s at 388.8 Hz
PLAYER_EXP_BYTES       equ 5
PLAYER_EXP_ROWS        equ 20
PLAYER_START_LIVES     equ 3

WAVE_CLEAR_BONUS  equ 500
ALIEN_GROUND_Y    equ 166     ; stop when lowest alien row reaches player zone
NEXT_WAVE_DELAY   equ 120     ; game ticks before new formation
ROUND_BANNER_XBYTE equ 20      ; center 320-pixel banner in 640-pixel screen
ROUND_BANNER_Y     equ 82
ROUND_BANNER_BYTES equ 40
ROUND_BANNER_ROWS  equ 32
; Phase H destructible bunker geometry. Byte aligned for fast QX VRAM access.
BUNKER_COUNT           equ 4
BUNKER_BYTES           equ 6          ; 48 pixels wide
BUNKER_ROWS            equ 12
BUNKER_Y               equ 160
BUNKER0_X              equ 8
BUNKER1_X              equ 27
BUNKER2_X              equ 46
BUNKER3_X              equ 65
BUNKER_SIZE            equ BUNKER_BYTES*BUNKER_ROWS

; Phase I mystery UFO. Byte-aligned 24x8 sprite with a larger 32x12 burst.
UFO_BYTES             equ 4
UFO_DRAW_BYTES        equ 5        ; shifted 32-pixel sprite can span 5 bytes
UFO_ROWS              equ 12
UFO_Y                 equ 10
UFO_LEFT_EDGE         equ 2
UFO_RIGHT_EDGE        equ 74
UFO_MOVE_TICK_DIV     equ 12       ; default period for 2-pixel UFO steps
UFO_WAIT_MIN          equ 1400
UFO_WAIT_RANGE        equ 1800
UFO_EXPLOSION_BYTES   equ 4
UFO_EXPLOSION_ROWS    equ 12
UFO_EXPLOSION_TICKS   equ 144
UFO_SCORE             equ 100


; Integrated startup splash: 320x120 pixels, centered in the 640x200 display.
SPLASH_X_BYTE         equ 20
SPLASH_Y              equ 32
SPLASH_BYTES          equ 40
SPLASH_ROWS           equ 120

start:
        push    cs
        pop     ds
        cld

        mov     ah,0Fh
        int     10h
        mov     [old_mode],al

        ; Same proven QX-11 graphics initialization as the SCI driver.
        mov     ax,0007h
        int     10h
        mov     ah,01h
        mov     cx,2000h
        int     10h

        call    sound_init
        call    show_splash_screen
        cmp     byte [exit_requested],0
        jne     exit_program_no_timer
        call    install_int71_timer
        call    restart_complete_game

main_loop:
        ; All gameplay is paced from the BIOS INT 71h callback. Busy-loop
        ; delays are no longer used. Missed ticks are intentionally dropped
        ; rather than queued, preventing catch-up bursts after heavy drawing.
        call    wait_for_int71_tick
        cmp     byte [wave_clear_active],0
        jne     .wave_clear_only

        call    process_game_tick
        cmp     byte [exit_requested],0
        jne     exit_program
        jmp     main_loop

.wave_clear_only:
        ; During the short between-wave pause, keep ESC/input and sound alive
        ; but freeze aliens, bullets, UFO and enemy fire.
        call    poll_player_input
        call    update_wave_clear_timing
        call    update_sound_timing
        cmp     byte [exit_requested],0
        jne     exit_program
        jmp     main_loop

exit_program:
        call    stop_visual_effects
        call    restore_int71_timer
exit_program_no_timer:
        call    sound_mute_all
        xor     ax,ax
        mov     al,[old_mode]
        int     10h
        mov     ax,4C00h
        int     21h


; ----------------------------------------------------------------------------
; Integrated 8-color startup splash. Any key starts; ESC exits.
; ----------------------------------------------------------------------------
show_splash_screen:
        call    clear_color_screen
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    cs
        pop     ds
        cld
        mov     word [splash_row_offset],0
        mov     word [splash_row_number],0
        mov     ax,SPLASH_Y
        mov     ah,al
        xor     al,al
        add     ax,SPLASH_X_BYTE
        mov     [splash_dst_offset],ax

        mov     dx,SPLASH_ROWS
        xor     bx,bx
.row:
        mov     di,[splash_dst_offset]
        mov     si,[splash_row_offset]
        add     si,splash_blue
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     cx,SPLASH_BYTES
        rep     movsb

        mov     di,[splash_dst_offset]
        mov     si,[splash_row_offset]
        add     si,splash_red
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     cx,SPLASH_BYTES
        rep     movsb

        mov     di,[splash_dst_offset]
        mov     si,[splash_row_offset]
        add     si,splash_green
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     cx,SPLASH_BYTES
        rep     movsb

        add     word [splash_row_offset],SPLASH_BYTES
        inc     word [splash_row_number]
        mov     ax,[splash_row_number]
        cmp     ax,SPLASH_ROWS
        jb      .prepare_next
        jmp     short .wait_key
.prepare_next:
        mov     bx,ax
        add     bx,SPLASH_Y
        mov     ax,bx
        mov     ah,al
        xor     al,al
        add     ax,SPLASH_X_BYTE
        mov     [splash_dst_offset],ax
        jmp     .row

.wait_key:
        xor     ax,ax
        int     16h
        cmp     al,1Bh
        jne     .start_game
        mov     byte [exit_requested],1
.start_game:
        mov     word [splash_row_offset],0
        mov     word [splash_row_number],0
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Phase F complete round reset.
; ----------------------------------------------------------------------------
restart_complete_game:
        call    clear_color_screen
        call    reset_alien_engine
        call    reset_player
        call    reset_player_bullet
        call    reset_enemy_system
        call    reset_ufo_system
        mov     byte [player_lives],PLAYER_START_LIVES
        mov     word [score_value],0
        mov     byte [game_over],0
        mov     byte [wave_clear_active],0
        mov     word [wave_clear_countdown],0
        mov     byte [wave_number],1
        call    draw_life_icons
        call    draw_score
        call    reset_bunkers
        call    draw_bunkers
        call    draw_formation
        call    draw_player_ship
        mov     ax,[cs:game_ticks]
        mov     [cs:last_game_tick],ax
        mov     ax,[cs:alien_period]
        mov     [cs:alien_countdown],ax
        ret

; ----------------------------------------------------------------------------
; Player ship: Phase B
;
; Left and right arrows move a 24x12, three-plane sprite. The ship is kept
; byte-aligned so 0EACh movement is exactly 8 pixels and drawing requires only
; 3 bytes x 12 rows x 3 planes.
; ----------------------------------------------------------------------------
reset_player:
        mov     word [player_x_byte],SHIP_START_X
        mov     word [player_y],SHIP_Y
        mov     byte [exit_requested],0
        ret

poll_player_input:
        push    ax
        mov     ah,01h
        int     16h
        jz      .done

        xor     ax,ax
        int     16h
        cmp     al,1Bh                  ; ESC
        je      .escape
        cmp     byte [game_over],0
        je      .normal_input
        cmp     al,'r'
        je      .restart
        cmp     al,'R'
        je      .restart
        cmp     al,0Dh                 ; ENTER
        je      .restart
        jmp     short .done
.restart:
        call    restart_complete_game
        jmp     short .done
.normal_input:
        cmp     byte [player_alive],0
        je      .done
        cmp     al,20h                  ; SPACE
        je      .fire
        cmp     ah,4Bh                  ; left arrow scan code
        je      .left
        cmp     ah,4Dh                  ; right arrow scan code
        je      .right
        jmp     short .done

.fire:
        call    fire_player_bullet
        jmp     short .done

.left:
        mov     ax,[player_x_byte]
        cmp     ax,SHIP_LEFT_EDGE
        jbe     .done
        call    erase_player_ship
        dec     word [player_x_byte]
        call    draw_player_ship
        jmp     short .done

.right:
        mov     ax,[player_x_byte]
        cmp     ax,SHIP_RIGHT_EDGE
        jae     .done
        call    erase_player_ship
        inc     word [player_x_byte]
        call    draw_player_ship
        jmp     short .done

.escape:
        mov     byte [exit_requested],1
.done:
        pop     ax
        ret

; Draw all three ship planes from independent bitmaps. This permits true
; multi-color pixels rather than assigning one flat color to the whole sprite.
draw_player_ship:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es

        mov     ax,[player_y]
        mov     ah,al
        xor     al,al
        add     ax,[player_x_byte]
        mov     di,ax
        xor     bx,bx
        mov     cx,SHIP_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     al,[cs:ship_blue+bx]
        mov     [es:di],al
        mov     al,[cs:ship_blue+bx+1]
        mov     [es:di+1],al
        mov     al,[cs:ship_blue+bx+2]
        mov     [es:di+2],al

        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     al,[cs:ship_red+bx]
        mov     [es:di],al
        mov     al,[cs:ship_red+bx+1]
        mov     [es:di+1],al
        mov     al,[cs:ship_red+bx+2]
        mov     [es:di+2],al

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     al,[cs:ship_green+bx]
        mov     [es:di],al
        mov     al,[cs:ship_green+bx+1]
        mov     [es:di+1],al
        mov     al,[cs:ship_green+bx+2]
        mov     [es:di+2],al

        add     bx,SHIP_BYTES
        add     di,0100h
        loop    .row

        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

erase_player_ship:
        push    ax
        push    bx
        push    cx
        push    di
        push    es

        mov     ax,[player_y]
        mov     ah,al
        xor     al,al
        add     ax,[player_x_byte]
        mov     di,ax
        mov     cx,SHIP_ROWS
        xor     ax,ax
.row:
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     [es:di],ax
        mov     [es:di+2],al
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     [es:di],ax
        mov     [es:di+2],al
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     [es:di],ax
        mov     [es:di+2],al
        add     di,0100h
        loop    .row

        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret


; ----------------------------------------------------------------------------
; Player bullet: Phase C
;
; Up to two player shots may exist at the same time. The
; shot is two pixels wide and four scanlines tall. It uses white in all three
; planes so it remains visible over every alien color. Collision detection is
; intentionally deferred to Phase D.
; ----------------------------------------------------------------------------
reset_player_bullet:
        mov     byte [bullet_active],0
        mov     byte [bullet_tick],BULLET_TICK_DIV
        mov     word [bullet_x_byte],0
        mov     word [bullet_y],0

        mov     byte [bullet2_active],0
        mov     byte [bullet2_tick],BULLET_TICK_DIV
        mov     word [bullet2_x_byte],0
        mov     word [bullet2_y],0
        ret

; Exchange the primary working bullet state with the second bullet slot.
; This lets the existing draw, collision, bunker and UFO routines operate on
; either shot without duplicating the proven collision engine.
swap_player_bullet_slots:
        push    ax

        mov     al,[bullet_active]
        xchg    al,[bullet2_active]
        mov     [bullet_active],al

        mov     al,[bullet_tick]
        xchg    al,[bullet2_tick]
        mov     [bullet_tick],al

        mov     ax,[bullet_x_byte]
        xchg    ax,[bullet2_x_byte]
        mov     [bullet_x_byte],ax

        mov     ax,[bullet_y]
        xchg    ax,[bullet2_y]
        mov     [bullet_y],ax

        pop     ax
        ret

; Spawn a shot in whichever bullet slot is currently loaded into the primary
; working variables. Caller guarantees that the current slot is inactive.
spawn_current_player_bullet:
        mov     ax,[player_x_byte]
        inc     ax
        mov     [bullet_x_byte],ax
        mov     ax,[player_y]
        sub     ax,BULLET_ROWS
        mov     [bullet_y],ax
        mov     byte [bullet_active],1
        mov     byte [bullet_tick],BULLET_TICK_DIV
        call    draw_player_bullet
        call    sound_player_shot
        ret

; Permit up to two simultaneous player shots. If the primary slot is busy,
; temporarily swap in the second slot and try it.
fire_player_bullet:
        cmp     byte [bullet_active],0
        je      .primary_free

        call    swap_player_bullet_slots
        cmp     byte [bullet_active],0
        jne     .both_busy

        call    spawn_current_player_bullet
        call    swap_player_bullet_slots
        ret

.both_busy:
        call    swap_player_bullet_slots
        ret

.primary_free:
        call    spawn_current_player_bullet
        ret

; Update both player bullets once per scheduler tick.
update_player_bullet_timing:
        call    update_current_player_bullet_timing
        call    swap_player_bullet_slots
        call    update_current_player_bullet_timing
        call    swap_player_bullet_slots
        ret

update_current_player_bullet_timing:
        cmp     byte [bullet_active],0
        je      .done
        dec     byte [bullet_tick]
        jnz     .done
        mov     byte [bullet_tick],BULLET_TICK_DIV
        call    update_player_bullet
.done:
        ret

erase_all_player_bullets:
        cmp     byte [bullet_active],0
        je      .primary_done
        call    erase_player_bullet
        mov     byte [bullet_active],0
.primary_done:
        call    swap_player_bullet_slots
        cmp     byte [bullet_active],0
        je      .secondary_done
        call    erase_player_bullet
        mov     byte [bullet_active],0
.secondary_done:
        call    swap_player_bullet_slots
        mov     byte [bullet_active],0
        mov     byte [bullet2_active],0
        ret

update_player_bullet:
        cmp     byte [bullet_active],0
        je      .done
        call    erase_player_bullet
        mov     ax,[bullet_y]
        cmp     ax,BULLET_TOP+BULLET_STEP
        jbe     .remove
        sub     ax,BULLET_STEP
        mov     [bullet_y],ax
        call    check_player_bullet_ufo_collision
        cmp     byte [bullet_active],0
        je      .done
        call    check_player_bullet_bunker_collision
        cmp     byte [bullet_active],0
        je      .done
        call    check_bullet_alien_collision
        cmp     byte [bullet_active],0
        je      .done
        call    draw_player_bullet
        jmp     short .done
.remove:
        mov     byte [bullet_active],0
.done:
        ret

draw_player_bullet:
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,[bullet_y]
        mov     ah,al
        xor     al,al
        add     ax,[bullet_x_byte]
        mov     di,ax
        mov     cx,BULLET_ROWS
.row:
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        or      byte [es:di],BULLET_MASK
        mov     bx,QX_RED_SEG
        mov     es,bx
        or      byte [es:di],BULLET_MASK
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        or      byte [es:di],BULLET_MASK
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

erase_player_bullet:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        mov     ax,[bullet_y]
        mov     ah,al
        xor     al,al
        add     ax,[bullet_x_byte]
        mov     di,ax
        mov     dl,BULLET_MASK
        not     dl
        mov     cx,BULLET_ROWS
.row:
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        and     [es:di],dl
        mov     bx,QX_RED_SEG
        mov     es,bx
        and     [es:di],dl
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        and     [es:di],dl
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Reset formation and all alien bookkeeping.
; ----------------------------------------------------------------------------
reset_alien_engine:
        mov     word [formation_x],START_X_BYTE
        mov     word [formation_y],START_Y
        mov     byte [direction],1
        mov     byte [frame_number],0
        mov     byte [kill_countdown],KILL_INTERVAL
        mov     byte [explosion_ticks],0
        mov     byte [explosion_index],0FFh
        mov     word [explosion_x_byte],0
        mov     word [explosion_y],0
        mov     byte [kill_cursor],54
        mov     byte [alive_count],ALIEN_COUNT
        mov     byte [drop_count],0

        mov     di,alive_table
        mov     cx,ALIEN_COUNT
        mov     al,1
        rep     stosb

        call    recalculate_live_columns
        call    rebuild_bottom_table
        call    recalculate_delay
        ret

; ----------------------------------------------------------------------------
; Shared formation movement with dynamic live edges.
;
; formation_x is a signed WORD measured in QX bytes. It is the virtual origin
; of column zero. When outer columns are dead this origin may move slightly
; outside the screen, while all living aliens remain visible.
; ----------------------------------------------------------------------------
update_formation_position:
        cmp     byte [direction],1
        jne     .moving_left

.moving_right:
        call    get_live_right_edge      ; AX = right edge after sprite
        cmp     ax,RIGHT_SCREEN_EDGE
        jae     .right_edge
        inc     word [formation_x]
        ret

.right_edge:
        mov     byte [direction],0FFh
        call    descend_formation
        ret

.moving_left:
        call    get_live_left_edge       ; AX = first live byte
        cmp     ax,LEFT_SCREEN_EDGE
        jle     .left_edge
        dec     word [formation_x]
        ret

.left_edge:
        mov     byte [direction],1
        call    descend_formation
        ret

descend_formation:
        add     word [formation_y],DROP_ROWS
        inc     byte [drop_count]
        call    recalculate_delay

        mov     ax,[formation_y]
        cmp     ax,BOTTOM_LIMIT
        jbe     .done

        ; Preserve killed aliens, but restart the formation at the top.
        mov     word [formation_x],START_X_BYTE
        mov     word [formation_y],START_Y
        mov     byte [direction],1
        mov     byte [drop_count],0
        call    recalculate_delay
.done:
        ret

; AX = formation origin + leftmost live column * spacing.
get_live_left_edge:
        xor     ax,ax
        mov     al,[left_live_col]
        call    multiply_ax_by_5
        add     ax,[formation_x]
        ret

; AX = formation origin + rightmost live column * spacing + sprite width.
get_live_right_edge:
        xor     ax,ax
        mov     al,[right_live_col]
        call    multiply_ax_by_5
        add     ax,[formation_x]
        add     ax,SPRITE_BYTES
        ret

; AX = AX * 5, preserving BX.
multiply_ax_by_5:
        push    bx
        mov     bx,ax
        shl     ax,1
        shl     ax,1              ; 4x
        add     ax,bx             ; 5x
        pop     bx
        ret

; ----------------------------------------------------------------------------
; Recalculate leftmost and rightmost columns containing at least one living
; alien. Called after 0EACh kill and after a complete fleet reset.
; ----------------------------------------------------------------------------
recalculate_live_columns:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si

        mov     byte [left_live_col],0
        mov     byte [right_live_col],10

        ; Find first live column from the left.
        xor     dx,dx                   ; DL = column
.find_left:
        cmp     dl,ALIENS_PER_ROW
        jae     .none_alive
        mov     al,dl
        call    column_has_living_alien
        or      al,al
        jnz     .left_found
        inc     dl
        jmp     short .find_left
.left_found:
        mov     [left_live_col],dl

        ; Find first live column from the right.
        mov     dl,10
.find_right:
        mov     al,dl
        call    column_has_living_alien
        or      al,al
        jnz     .right_found
        dec     dl
        jmp     short .find_right
.right_found:
        mov     [right_live_col],dl
        jmp     short .done

.none_alive:
        mov     byte [left_live_col],0
        mov     byte [right_live_col],0
.done:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; Input AL = column 0..10. Output AL = 1 if any row in that column is alive.
column_has_living_alien:
        push    bx
        push    cx
        push    dx

        xor     bx,bx
        mov     bl,al                   ; BX = current linear index
        mov     cx,FORMATION_ROWS
.scan:
        cmp     byte [alive_table+bx],0
        jne     .yes
        add     bx,ALIENS_PER_ROW
        loop    .scan
        xor     al,al
        jmp     short .done
.yes:
        mov     al,1
.done:
        pop     dx
        pop     cx
        pop     bx
        ret

; ----------------------------------------------------------------------------
; Survivor-count speed plus a small depth bonus.
;
; Thresholds deliberately remain conservative so the animation stays visible:
;   46-55 alive -> 32000
;   36-45 alive -> 29000
;   26-35 alive -> 26000
;   16-25 alive -> 23000
;    8-15 alive -> 20000
;    2-7  alive -> 17000
;    1    alive -> 15000
;
; 0EACh downward step subtracts DEPTH_DELAY_STEP, clamped at MIN_DELAY.
; ----------------------------------------------------------------------------
recalculate_delay:
        ; Convert the live-alien count and descent depth into a timer period.
        ; Larger values are slower. The curve is intentionally gradual:
        ; unlike the previous version, removing the first ten aliens no longer
        ; cuts the period from 60 directly to 27.
        push    ax
        push    bx

        mov     al,[alive_count]
        cmp     al,46
        jae     .p60
        cmp     al,36
        jae     .p56
        cmp     al,26
        jae     .p52
        cmp     al,16
        jae     .p48
        cmp     al,8
        jae     .p44
        cmp     al,2
        jae     .p36
        mov     ax,30
        jmp     short .apply_depth

.p36:  mov     ax,36
        jmp     short .apply_depth
.p44:  mov     ax,44
        jmp     short .apply_depth
.p48:  mov     ax,48
        jmp     short .apply_depth
.p52:  mov     ax,52
        jmp     short .apply_depth
.p56:  mov     ax,56
        jmp     short .apply_depth
.p60:  mov     ax,ALIEN_START_PERIOD

.apply_depth:
        ; One additional speed step for every four downward drops.
        xor     bx,bx
        mov     bl,[drop_count]
        mov     cl,2
        shr     bx,cl
        sub     ax,bx

        cmp     ax,ALIEN_MIN_PERIOD
        jae     .store
        mov     ax,ALIEN_MIN_PERIOD
.store:
        mov     [alien_period],ax
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Bottom-alien lookup table.
;
; bottom_alien_table[column] = linear alien index 0..54, or 0FFh if empty.
; This is the exact source table future enemy-shot code will use.
; ----------------------------------------------------------------------------
rebuild_bottom_table:
        push    ax
        push    cx
        xor     ax,ax
        mov     cx,ALIENS_PER_ROW
.loop:
        call    update_bottom_for_column
        inc     al
        loop    .loop
        pop     cx
        pop     ax
        ret

; Input AL = column 0..10.
update_bottom_for_column:
        push    ax
        push    bx
        push    cx
        push    dx

        xor     bx,bx
        mov     bl,al                   ; column
        mov     dl,al                   ; preserve table slot
        add     bx,44                   ; bottom row index = 44 + column
        mov     cx,FORMATION_ROWS
.scan_up:
        cmp     byte [alive_table+bx],0
        jne     .found
        sub     bx,ALIENS_PER_ROW
        loop    .scan_up
        mov     al,0FFh
        jmp     short .store
.found:
        mov     al,bl
.store:
        xor     bx,bx
        mov     bl,dl
        mov     [bottom_alien_table+bx],al

        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Formation renderer.
; render_mode: 1 = draw current sprites, 0 = clear old sprite rectangles.
; ----------------------------------------------------------------------------
draw_formation:
        mov     byte [render_mode],1
        jmp     short render_formation

erase_formation:
        mov     byte [render_mode],0

render_formation:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp

        xor     bp,bp
        mov     byte [alien_index],0
        mov     ax,[formation_y]
        mov     [row_y],ax

.row_loop:
        cmp     bp,FORMATION_ROWS
        jae     .done

        ; Select one of six true three-plane sprite frames.
        cmp     bp,0
        jne     .not_top
        mov     ax,squid_f1_blue
        mov     bx,squid_f1_red
        mov     dx,squid_f1_green
        cmp     byte [frame_number],0
        je      .selected
        mov     ax,squid_f2_blue
        mov     bx,squid_f2_red
        mov     dx,squid_f2_green
        jmp     short .selected

.not_top:
        cmp     bp,3
        jae     .bottom_type
        mov     ax,crab_f1_blue
        mov     bx,crab_f1_red
        mov     dx,crab_f1_green
        cmp     byte [frame_number],0
        je      .selected
        mov     ax,crab_f2_blue
        mov     bx,crab_f2_red
        mov     dx,crab_f2_green
        jmp     short .selected

.bottom_type:
        mov     ax,octopus_f1_blue
        mov     bx,octopus_f1_red
        mov     dx,octopus_f1_green
        cmp     byte [frame_number],0
        je      .selected
        mov     ax,octopus_f2_blue
        mov     bx,octopus_f2_red
        mov     dx,octopus_f2_green

.selected:
        mov     [sprite_blue_ptr],ax
        mov     [sprite_red_ptr],bx
        mov     [sprite_green_ptr],dx

        mov     ax,[formation_x]
        mov     [current_x_byte],ax
        mov     ax,[row_y]
        mov     [current_y],ax
        mov     cx,ALIENS_PER_ROW

.col_loop:
        push    cx
        xor     bx,bx
        mov     bl,[alien_index]

        cmp     byte [render_mode],0
        je      .consider_clear
        cmp     byte [alive_table+bx],0
        je      .one_done
        call    draw_sprite_planar
        jmp     short .one_done

.consider_clear:
        cmp     byte [alive_table+bx],0
        je      .one_done
        call    clear_sprite_rect

.one_done:
        pop     cx
        inc     byte [alien_index]
        add     word [current_x_byte],X_SPACING_BYTES
        loop    .col_loop

        add     word [row_y],Y_SPACING
        inc     bp
        jmp     .row_loop

.done:
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; True multicolor planar sprite renderer.
draw_sprite_planar:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es

        call    make_sprite_address
        xor     bp,bp
        mov     cx,SPRITE_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     si,[sprite_blue_ptr]
        add     si,bp
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     al,[cs:si+2]
        mov     [es:di+2],al

        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     si,[sprite_red_ptr]
        add     si,bp
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     al,[cs:si+2]
        mov     [es:di+2],al

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     si,[sprite_green_ptr]
        add     si,bp
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     al,[cs:si+2]
        mov     [es:di+2],al

        add     bp,SPRITE_BYTES
        add     di,0100h
        loop    .row

        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

clear_sprite_rect:
        push    ax
        push    bx
        push    cx
        push    di
        push    es

        call    make_sprite_address
        mov     cx,SPRITE_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     byte [es:di+2],0
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     byte [es:di+2],0
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     byte [es:di+2],0
        add     di,0100h
        loop    .row

        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

; DI = current_y*0100h + current_x_byte.
make_sprite_address:
        mov     ax,[current_y]
        mov     ah,al
        xor     al,al
        add     ax,[current_x_byte]
        mov     di,ax
        ret

; ----------------------------------------------------------------------------
; Phase D: player-shot collision and explosion state.
;
; The player bullet is one QX byte wide but only uses the center two bits.
; Alien X positions are byte-aligned and 0EACh alien occupies two bytes x eight
; rows. A collision occurs when the bullet byte is either alien byte and the
; four-line bullet overlaps the alien's vertical rectangle.
; ----------------------------------------------------------------------------
check_bullet_alien_collision:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp

        cmp     byte [bullet_active],0
        je      .done
        xor     bp,bp                    ; row 0..4
        mov     ax,[formation_y]
        mov     [collision_row_y],ax
        mov     byte [collision_index],0

.row_loop:
        cmp     bp,FORMATION_ROWS
        jae     .done

        ; Vertical overlap: bullet_bottom >= alien_top and bullet_top <= alien_bottom.
        mov     ax,[bullet_y]
        mov     dx,ax
        add     dx,BULLET_ROWS-1
        mov     bx,[collision_row_y]
        cmp     dx,bx
        jb      .next_row
        add     bx,SPRITE_ROWS-1
        cmp     ax,bx
        ja      .next_row

        mov     ax,[formation_x]
        mov     [collision_x_byte],ax
        mov     cx,ALIENS_PER_ROW
.col_loop:
        xor     bx,bx
        mov     bl,[collision_index]
        cmp     byte [alive_table+bx],0
        je      .next_col

        mov     ax,[bullet_x_byte]
        mov     dx,[collision_x_byte]
        cmp     ax,dx
        jb      .next_col
        add     dx,SPRITE_BYTES-1       ; last storage byte of 20-pixel alien
        cmp     ax,dx
        ja      .next_col

        ; Hit: remove the bullet, mark the alien dead, and draw an explosion
        ; immediately at the alien's current screen position.
        mov     byte [bullet_active],0
        call    clear_current_alien_explosion
        mov     al,[collision_index]
        mov     [explosion_index],al
        mov     ax,[collision_x_byte]
        mov     [explosion_x_byte],ax
        mov     ax,[collision_row_y]
        mov     [explosion_y],ax
        mov     byte [explosion_ticks],EXPLOSION_STEPS
        mov     byte [alive_table+bx],0
        dec     byte [alive_count]

        ; Award the destroyed alien's normal points before checking whether
        ; this was the final alien in the wave.
        call    add_score_for_hit

        cmp     byte [alive_count],0
        jne     .normal_alien_kill

        ; Final alien: start the bonus/wave-clear sequence and leave the
        ; collision routine immediately. start_wave_clear draws the banner and
        ; uses working registers, so we must not continue into the column DIV
        ; or draw an alien explosion over the bonus screen.
        call    check_round_end_conditions
        jmp     short .done

.normal_alien_kill:
        ; Update bottom-most firing source for only the affected column.
        mov     ax,bx
        mov     cl,ALIENS_PER_ROW
        div     cl                       ; AH = column
        mov     al,ah
        call    update_bottom_for_column
        call    recalculate_live_columns
        call    recalculate_delay
        call    draw_current_explosion
        call    sound_alien_hit
        jmp     short .done

.next_col:
        inc     byte [collision_index]
        add     word [collision_x_byte],X_SPACING_BYTES
        loop    .col_loop
        jmp     short .advance_row

.next_row:
        add     byte [collision_index],ALIENS_PER_ROW
.advance_row:
        add     word [collision_row_y],Y_SPACING
        inc     bp
        jmp     .row_loop
.done:
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; Draw a larger 32x16 explosion centered around the destroyed alien.
draw_current_explosion:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        cmp     byte [explosion_ticks],0
        je      .done
        mov     ax,[explosion_y]
        cmp     ax,4
        jb      .y_ok
        sub     ax,4
.y_ok:
        mov     ah,al
        xor     al,al
        mov     bx,[explosion_x_byte]
        cmp     bx,0
        je      .x_ok
        dec     bx
.x_ok:
        add     ax,bx
        mov     di,ax
        xor     bx,bx
        mov     cx,ALIEN_EXP_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     si,alien_explosion_blue
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     si,alien_explosion_red
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     si,alien_explosion_green
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        add     bx,ALIEN_EXP_BYTES
        add     di,0100h
        loop    .row
.done:
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

clear_current_alien_explosion:
        cmp     byte [explosion_ticks],0
        je      .done
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,[explosion_y]
        cmp     ax,4
        jb      .y_ok
        sub     ax,4
.y_ok:
        mov     ah,al
        xor     al,al
        mov     bx,[explosion_x_byte]
        cmp     bx,0
        je      .x_ok
        dec     bx
.x_ok:
        add     ax,bx
        mov     di,ax
        mov     cx,ALIEN_EXP_ROWS
        xor     ax,ax
.row:
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],0
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],0
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],0
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

update_explosion_state:
        cmp     byte [explosion_ticks],0
        je      .done
        dec     byte [explosion_ticks]
        jnz     .done
        mov     byte [explosion_ticks],1
        call    clear_current_alien_explosion
        mov     byte [explosion_ticks],0
        mov     byte [explosion_index],0FFh
.done:
        ret

; Phase G scoring: squid=30, crab=20, octopus=10.
; collision_index identifies the alien that was just destroyed.
add_score_for_hit:
        push    ax
        push    bx
        xor     ax,ax
        mov     al,[collision_index]
        mov     bl,ALIENS_PER_ROW
        div     bl                      ; AL = row 0..4
        cmp     al,1
        jb      .thirty
        cmp     al,3
        jb      .twenty
        mov     ax,10
        jmp     short .add
.twenty:
        mov     ax,20
        jmp     short .add
.thirty:
        mov     ax,30
.add:
        add     [score_value],ax
        call    draw_score
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Phase E: one enemy bullet and player hit/respawn.
;
; A round-robin column selector uses bottom_alien_table[] so only the lowest
; living alien in a non-empty column can fire. This is the lookup structure
; prepared in the alien-engine phase.
; ----------------------------------------------------------------------------
reset_enemy_system:
        mov     byte [enemy_bullet_active],0
        mov     byte [enemy_bullet_tick],ENEMY_BULLET_TICK_DIV
        mov     word [enemy_fire_countdown],ENEMY_FIRE_MIN
        mov     byte [enemy_fire_column],0
        mov     word [random_state],0ACE1h
        mov     byte [player_alive],1
        mov     byte [player_explosion_ticks],0
        ret

update_enemy_system_timing:
        call    update_player_respawn
        ; Pause new enemy fire while the player explosion is visible.
        cmp     byte [player_alive],0
        je      .done

        cmp     byte [enemy_bullet_active],0
        jne     .bullet_exists

        dec     word [enemy_fire_countdown]
        jnz     .done
        call    set_random_fire_delay
        call    fire_enemy_bullet
        jmp     short .done

.bullet_exists:
        dec     byte [enemy_bullet_tick]
        jnz     .done
        mov     byte [enemy_bullet_tick],ENEMY_BULLET_TICK_DIV
        call    update_enemy_bullet
.done:
        ret

; Choose a pseudo-random non-empty column. Only the lowest living alien in
; that column can fire. If the first random columns are empty, retry up to 11
; times with new random values.
fire_enemy_bullet:
        cmp     byte [enemy_bullet_active],0
        jne     .done
        cmp     byte [alive_count],0
        je      .done

        push    ax
        push    bx
        push    cx
        push    dx

        mov     cx,ALIENS_PER_ROW
.try_column:
        call    random_next
        xor     dx,dx
        mov     bx,ALIENS_PER_ROW
        div     bx                       ; DX = random column 0..10
        mov     bx,dx
        mov     al,[bottom_alien_table+bx]
        cmp     al,0FFh
        jne     .found
        loop    .try_column
        jmp     short .restore

.found:
        ; Preserve the selected linear index in DH.
        mov     dh,al

        ; X byte = formation_x + random column*5 + center byte.
        mov     ax,bx
        call    multiply_ax_by_5
        add     ax,[formation_x]
        inc     ax
        mov     [enemy_bullet_x_byte],ax

        ; Calculate the selected alien row from its linear index.
        mov     al,dh
        xor     ah,ah
        mov     dl,ALIENS_PER_ROW
        div     dl                       ; AL=row
        xor     ah,ah
        mov     bl,Y_SPACING
        mul     bl
        add     ax,[formation_y]
        add     ax,SPRITE_ROWS
        mov     [enemy_bullet_y],ax

        mov     byte [enemy_bullet_active],1
        mov     byte [enemy_bullet_tick],ENEMY_BULLET_TICK_DIV
        call    draw_enemy_bullet
        call    sound_enemy_shot
.restore:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

; 16-bit Galois LFSR. Returns a new pseudo-random value in AX.
random_next:
        mov     ax,[random_state]
        shr     ax,1
        jnc     .store
        xor     ax,0B400h
.store:
        mov     [random_state],ax
        ret

; Set the next firing delay to ENEMY_FIRE_MIN plus a pseudo-random amount.
set_random_fire_delay:
        push    ax
        push    bx
        push    dx
        call    random_next
        xor     dx,dx
        mov     bx,ENEMY_FIRE_RANGE
        div     bx                       ; DX = 0..ENEMY_FIRE_RANGE-1
        mov     ax,dx
        add     ax,ENEMY_FIRE_MIN
        mov     [enemy_fire_countdown],ax
        pop     dx
        pop     bx
        pop     ax
        ret

update_enemy_bullet:
        cmp     byte [enemy_bullet_active],0
        je      .done
        call    erase_enemy_bullet
        mov     ax,[enemy_bullet_y]
        add     ax,ENEMY_BULLET_STEP
        cmp     ax,ENEMY_BULLET_BOTTOM
        jae     .remove
        mov     [enemy_bullet_y],ax
        call    check_enemy_bullet_bunker_collision
        cmp     byte [enemy_bullet_active],0
        je      .done
        call    check_enemy_bullet_player_collision
        cmp     byte [enemy_bullet_active],0
        je      .done
        call    draw_enemy_bullet
        jmp     short .done
.remove:
        mov     byte [enemy_bullet_active],0
.done:
        ret

draw_enemy_bullet:
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,[enemy_bullet_y]
        mov     ah,al
        xor     al,al
        add     ax,[enemy_bullet_x_byte]
        mov     di,ax
        mov     cx,ENEMY_BULLET_ROWS
.row:
        ; Yellow enemy shot: Red + Green.
        mov     bx,QX_RED_SEG
        mov     es,bx
        or      byte [es:di],ENEMY_BULLET_MASK
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        or      byte [es:di],ENEMY_BULLET_MASK
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

erase_enemy_bullet:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        mov     ax,[enemy_bullet_y]
        mov     ah,al
        xor     al,al
        add     ax,[enemy_bullet_x_byte]
        mov     di,ax
        mov     dl,ENEMY_BULLET_MASK
        not     dl
        mov     cx,ENEMY_BULLET_ROWS
.row:
        mov     bx,QX_RED_SEG
        mov     es,bx
        and     [es:di],dl
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        and     [es:di],dl
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

check_enemy_bullet_player_collision:
        cmp     byte [player_alive],0
        je      .done

        ; Horizontal test: enemy bullet byte inside the three-byte ship.
        mov     ax,[enemy_bullet_x_byte]
        mov     bx,[player_x_byte]
        cmp     ax,bx
        jb      .done
        add     bx,SHIP_BYTES-1
        cmp     ax,bx
        ja      .done

        ; Vertical rectangle overlap.
        mov     ax,[enemy_bullet_y]
        mov     dx,ax
        add     dx,ENEMY_BULLET_ROWS-1
        mov     bx,[player_y]
        cmp     dx,bx
        jb      .done
        add     bx,SHIP_ROWS-1
        cmp     ax,bx
        ja      .done

        mov     byte [enemy_bullet_active],0
        call    destroy_player_ship
.done:
        ret

destroy_player_ship:
        cmp     byte [player_alive],0
        je      .done
        call    erase_player_ship
        mov     byte [player_alive],0
        call    erase_all_player_bullets
        mov     byte [player_explosion_ticks],PLAYER_EXPLOSION_TICKS
        cmp     byte [player_lives],0
        je      .draw_burst
        dec     byte [player_lives]
        call    draw_life_icons
.draw_burst:
        call    draw_player_explosion
        call    start_player_screen_shake
        call    sound_player_hit
.done:
        ret

; A larger 40x20 multicolor player explosion centered on the ship.
draw_player_explosion:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     ax,[player_y]
        cmp     ax,2
        jb      .y_ok
        sub     ax,2
.y_ok:
        mov     ah,al
        xor     al,al
        mov     bx,[player_x_byte]
        cmp     bx,1
        jb      .x_ok
        dec     bx
.x_ok:
        add     ax,bx
        mov     di,ax
        xor     bx,bx
        mov     cx,PLAYER_EXP_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     si,player_explosion_blue
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     si,player_explosion_red
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     si,player_explosion_green
        add     si,bx
        mov     ax,[cs:si]
        mov     [es:di],ax
        mov     ax,[cs:si+2]
        mov     [es:di+2],ax
        mov     al,[cs:si+4]
        mov     [es:di+4],al

        add     bx,PLAYER_EXP_BYTES
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

clear_player_explosion:
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,[player_y]
        cmp     ax,2
        jb      .y_ok
        sub     ax,2
.y_ok:
        mov     ah,al
        xor     al,al
        mov     bx,[player_x_byte]
        cmp     bx,1
        jb      .x_ok
        dec     bx
.x_ok:
        add     ax,bx
        mov     di,ax
        mov     cx,PLAYER_EXP_ROWS
        xor     ax,ax
.row:
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],al
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],al
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     word [es:di],ax
        mov     word [es:di+2],ax
        mov     byte [es:di+4],al
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

update_player_respawn:
        cmp     byte [player_alive],0
        jne     .done
        cmp     byte [game_over],0
        jne     .done
        cmp     byte [player_explosion_ticks],0
        je      .finish_death
        dec     byte [player_explosion_ticks]
        jz      .finish_death
        ; Repaint every slice so formation/bullet activity can never obscure it.
        call    draw_player_explosion
        jmp     short .done
.finish_death:
        call    clear_player_explosion
        cmp     byte [player_lives],0
        je      .no_lives
        ; Respawn at the position where the ship was destroyed.
        mov     byte [player_alive],1
        call    draw_player_ship
        call    sound_player_ready
        jmp     short .done
.no_lives:
        call    enter_game_over
.done:
        ret

; ----------------------------------------------------------------------------
; Phase F lives display and game-over state.
; Three small ship icons are drawn at the top-left. The count includes the
; current ship, so one icon disappears immediately after 0EACh hit.
; ----------------------------------------------------------------------------
draw_life_icons:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es

        ; Clear the icon strip: bytes 1..8, rows 2..7 in all planes.
        mov     dx,2
.clear_row:
        mov     ax,dx
        mov     ah,al
        xor     al,al
        inc     ax
        mov     di,ax
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     cx,8
        xor     al,al
        rep     stosb
        sub     di,8
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     cx,8
        rep     stosb
        sub     di,8
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     cx,8
        rep     stosb
        inc     dx
        cmp     dx,8
        jb      .clear_row

        xor     bx,bx
.draw_next:
        cmp     bl,[player_lives]
        jae     .done
        ; Icon X bytes: 1, 3, 5. Y = 2.
        mov     ax,bx
        shl     ax,1
        inc     ax
        mov     di,ax
        add     di,0200h
        xor     si,si
        mov     cx,5
.icon_row:
        mov     dl,[cs:life_icon+si]
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     [es:di],dl
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     [es:di],dl
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     [es:di],dl
        inc     si
        add     di,0100h
        loop    .icon_row
        inc     bx
        jmp     short .draw_next
.done:
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret


; ============================================================================
; ROUND / WAVE COMPLETION
; ============================================================================

; Called after alien movement and after every alien kill.
check_round_end_conditions:
        cmp     byte [game_over],0
        jne     .done
        cmp     byte [wave_clear_active],0
        jne     .done

        ; All aliens destroyed: start the wave-clear pause.
        cmp     byte [alive_count],0
        jne     .check_ground
        call    start_wave_clear
        jmp     .done

.check_ground:
        ; Find the lowest row that still contains at least one living alien.
        ; Do not use the original fixed row 4, because lower rows may already
        ; be completely destroyed.
        mov     bl,4

.find_live_row:
        push    bx
        call    row_has_living_alien
        pop     bx
        cmp     al,1
        je      .row_found
        dec     bl
        jns     .find_live_row
        jmp     .done

.row_found:
        ; bottom_y = formation_y + live_row * Y_SPACING
        ;          + SPRITE_ROWS - 1
        xor     bh,bh
        mov     ax,bx
        mov     dx,Y_SPACING
        mul     dx
        add     ax,[formation_y]
        add     ax,SPRITE_ROWS - 1
        cmp     ax,ALIEN_GROUND_Y
        jb      .done
        call    enter_game_over
.done:
        ret

; Input:
;   BL = alien row 0..4
; Return:
;   AL = 1 if any alien in that row is alive, otherwise 0
row_has_living_alien:
        push    bx
        push    cx
        push    dx
        push    si

        xor     bh,bh
        mov     ax,bx
        mov     dx,11
        mul     dx
        mov     si,ax
        mov     cx,11
        xor     al,al

.scan:
        cmp     byte [alive_table+si],0
        jne     .yes
        inc     si
        loop    .scan
        jmp     short .done

.yes:
        mov     al,1

.done:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret

start_wave_clear:
        cmp     byte [wave_clear_active],0
        jne     .done

        ; Remove active projectiles and transient effects.
        call    erase_all_player_bullets
        cmp     byte [enemy_bullet_active],0
        je      .enemy_done
        call    erase_enemy_bullet
        mov     byte [enemy_bullet_active],0
.enemy_done:
        call    clear_current_alien_explosion

        ; Award wave-clear bonus without resetting the current score.
        mov     ax,[score_value]
        add     ax,WAVE_CLEAR_BONUS
        jnc     .score_ok
        mov     ax,0FFFFh
.score_ok:
        mov     [score_value],ax
        call    draw_score

        call    draw_bonus_points_banner
        call    sound_bonus_fanfare
        mov     byte [wave_clear_active],1
        mov     word [wave_clear_countdown],NEXT_WAVE_DELAY
.done:
        ret

update_wave_clear_timing:
        cmp     byte [wave_clear_active],0
        je      .done
        cmp     word [wave_clear_countdown],0
        je      .new_wave
        dec     word [wave_clear_countdown]
        jnz     .done

.new_wave:
        call    begin_next_wave
.done:
        ret

begin_next_wave:
        ; Remove the banner before any game objects are restored.
        call    clear_round_banner

        ; Preserve score and lives, but reset every transient object that can
        ; still reference the previous wave.
        inc     byte [wave_number]
        mov     byte [wave_clear_active],0
        mov     word [wave_clear_countdown],0
        mov     byte [drop_count],0
        mov     byte [explosion_ticks],0
        mov     byte [explosion_index],0FFh
        mov     byte [ufo_explosion_ticks],0
        mov     byte [enemy_bullet_active],0
        mov     byte [bullet_active],0
        mov     byte [bullet2_active],0

        call    reset_ufo_system
        call    reset_enemy_system

        mov     word [formation_x],START_X_BYTE
        mov     word [formation_y],START_Y
        mov     byte [direction],1
        mov     byte [frame_number],0
        mov     byte [alive_count],ALIEN_COUNT

        ; Rebuild exactly 55 bytes. Do not use REP STOSB here: this transition
        ; follows BIOS/interrupt activity, and depending on DF or ES could write
        ; backward or into VRAM. CS overrides make the destination unambiguous.
        push    ax
        push    cx
        push    di
        xor     di,di
        mov     cx,ALIEN_COUNT
.fill_alive:
        mov     byte [cs:alive_table+di],1
        inc     di
        loop    .fill_alive
        pop     di
        pop     cx
        pop     ax

        call    rebuild_bottom_table
        call    recalculate_live_columns
        call    recalculate_delay
        mov     ax,[alien_period]
        mov     [alien_countdown],ax
        call    draw_formation
        call    sound_player_ready
        ret

enter_game_over:
        mov     byte [game_over],1
        mov     byte [enemy_bullet_active],0
        call    erase_all_player_bullets
        call    draw_game_over_panel
        ret

; Draw large native planar banners. R or ENTER restarts after GAME OVER.
draw_game_over_panel:
        mov     si,game_over_blue
        mov     bx,game_over_red
        mov     dx,game_over_green
        mov     ax,ROUND_BANNER_Y
        call    draw_full_width_banner
        ret

draw_bonus_points_banner:
        mov     si,bonus_points_blue
        mov     bx,bonus_points_red
        mov     dx,bonus_points_green
        mov     ax,ROUND_BANNER_Y
        call    draw_full_width_banner
        ret

clear_round_banner:
        cld
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,ROUND_BANNER_Y
        mov     ah,al
        xor     al,al
        add     ax,ROUND_BANNER_XBYTE
        mov     di,ax
        mov     bx,ROUND_BANNER_ROWS
.row:
        push    di
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        xor     ax,ax
        mov     cx,ROUND_BANNER_BYTES
        rep     stosb
        pop     di

        push    di
        mov     ax,QX_RED_SEG
        mov     es,ax
        xor     ax,ax
        mov     cx,ROUND_BANNER_BYTES
        rep     stosb
        pop     di

        push    di
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        xor     ax,ax
        mov     cx,ROUND_BANNER_BYTES
        rep     stosb
        pop     di

        add     di,0100h
        dec     bx
        jnz     .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = top Y, SI/BX/DX = blue/red/green 40-byte x 32-row planar data.
draw_full_width_banner:
        cld
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es

        mov     ah,al
        xor     al,al
        add     ax,ROUND_BANNER_XBYTE
        mov     di,ax
        xor     bp,bp
        push    cs
        pop     ds

.row:
        push    bx
        push    dx

        mov     ax,QX_BLUE_SEG
        mov     es,ax
        push    si
        add     si,bp
        mov     cx,ROUND_BANNER_BYTES
        rep     movsb
        pop     si
        sub     di,ROUND_BANNER_BYTES

        pop     dx
        pop     bx
        mov     ax,QX_RED_SEG
        mov     es,ax
        push    si
        mov     si,bx
        add     si,bp
        mov     cx,ROUND_BANNER_BYTES
        rep     movsb
        pop     si
        sub     di,ROUND_BANNER_BYTES

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        push    si
        mov     si,dx
        add     si,bp
        mov     cx,ROUND_BANNER_BYTES
        rep     movsb
        pop     si
        sub     di,ROUND_BANNER_BYTES

        add     di,0100h
        add     bp,ROUND_BANNER_BYTES
        cmp     bp,ROUND_BANNER_BYTES*ROUND_BANNER_ROWS
        jb      .row

        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Phase G score display: five larger 5x7 white digits at the upper-right.
; 0EACh digit occupies one QX byte (five pixels plus spacing), seven rows.
; ----------------------------------------------------------------------------
draw_score:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es

        mov     ax,[score_value]
        mov     di,score_digits+4
        mov     cx,5
.convert:
        xor     dx,dx
        mov     bx,10
        div     bx
        mov     [di],dl
        dec     di
        loop    .convert

        ; Clear ten bytes by fourteen rows at the upper-right.
        xor     dx,dx
.clear_row:
        mov     ax,dx
        inc     ax
        mov     ah,al
        xor     al,al
        add     ax,68
        mov     di,ax
        xor     ax,ax
        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     cx,5
        rep     stosw
        sub     di,10
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     cx,5
        rep     stosw
        sub     di,10
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     cx,5
        rep     stosw
        inc     dx
        cmp     dx,14
        jb      .clear_row

        xor     bp,bp
.next_digit:
        cmp     bp,5
        jae     .done
        xor     ax,ax
        mov     bx,bp
        mov     al,[score_digits+bx]
        mov     bl,28
        mul     bl
        mov     si,digit_font_10x14
        add     si,ax
        xor     cx,cx
.row:
        cmp     cx,14
        jae     .digit_done
        mov     ax,cx
        inc     ax
        mov     ah,al
        xor     al,al
        add     ax,68
        mov     di,ax
        mov     ax,bp
        shl     ax,1
        add     di,ax
        mov     ax,[cs:si]

        mov     bx,QX_BLUE_SEG
        mov     es,bx
        mov     [es:di],ax
        mov     bx,QX_RED_SEG
        mov     es,bx
        mov     [es:di],ax
        mov     bx,QX_GREEN_SEG
        mov     es,bx
        mov     [es:di],ax

        add     si,2
        inc     cx
        jmp     .row
.digit_done:
        inc     bp
        jmp     .next_digit
.done:
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; Phase H: four destructible bunkers.
;
; 0EACh bunker is a 48x12 one-bit damage map. The same mask is written to the
; Blue and Green planes, producing cyan/green shields. Bullets remove a small
; byte-oriented crater from the software map, then that bunker is redrawn.
; ----------------------------------------------------------------------------
reset_bunkers:
        push    ax
        push    cx
        push    si
        push    di
        push    es
        push    cs
        pop     es
        mov     si,bunker_template
        mov     di,bunker_data
        mov     cx,BUNKER_SIZE
        rep     movsb
        mov     si,bunker_template
        mov     cx,BUNKER_SIZE
        rep     movsb
        mov     si,bunker_template
        mov     cx,BUNKER_SIZE
        rep     movsb
        mov     si,bunker_template
        mov     cx,BUNKER_SIZE
        rep     movsb
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret

draw_bunkers:
        push    ax
        push    bx
        push    si
        xor     bx,bx
.loop:
        cmp     bx,BUNKER_COUNT
        jae     .done
        mov     ax,bx
        mov     si,BUNKER_SIZE
        mul     si
        add     ax,bunker_data
        mov     si,ax
        mov     al,bl
        call    get_bunker_x
        mov     [current_x_byte],ax
        mov     word [current_y],BUNKER_Y
        call    draw_one_bunker
        inc     bx
        jmp     .loop
.done:
        pop     si
        pop     bx
        pop     ax
        ret

; AL = bunker number, returns AX = byte X.
get_bunker_x:
        xor     ah,ah
        cmp     al,0
        je      .b0
        cmp     al,1
        je      .b1
        cmp     al,2
        je      .b2
        mov     ax,BUNKER3_X
        ret
.b0:    mov ax,BUNKER0_X
        ret
.b1:    mov ax,BUNKER1_X
        ret
.b2:    mov ax,BUNKER2_X
        ret

; SI = damage-map address, current_x_byte/current_y = destination.
draw_one_bunker:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    bp
        push    es
        mov     ax,[current_y]
        mov     ah,al
        xor     al,al
        add     ax,[current_x_byte]
        mov     di,ax
        xor     bp,bp
        mov     dx,BUNKER_ROWS
.row:
        xor     bx,bx
.byte:
        mov     al,[cs:si+bp]
        ; Blue plane receives a checker-highlight subset.
        mov     cx,QX_BLUE_SEG
        mov     es,cx
        mov     ah,al
        test    dl,1
        jz      .blue_store
        and     ah,0AAh
.blue_store:
        mov     [es:di+bx],ah
        ; Green plane receives full bunker body.
        mov     cx,QX_GREEN_SEG
        mov     es,cx
        mov     [es:di+bx],al
        ; Red remains clear.
        mov     cx,QX_RED_SEG
        mov     es,cx
        mov     byte [es:di+bx],0
        inc     bp
        inc     bx
        cmp     bx,BUNKER_BYTES
        jb      .byte
        add     di,0100h
        dec     dx
        jnz     .row
        pop     es
        pop     bp
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AL=bunker index. Clear its VRAM rectangle and redraw current damage map.
redraw_bunker:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     bl,al
        call    get_bunker_x
        mov     [current_x_byte],ax
        mov     word [current_y],BUNKER_Y
        mov     ax,BUNKER_Y
        mov     ah,al
        xor     al,al
        add     ax,[current_x_byte]
        mov     di,ax
        mov     dx,BUNKER_ROWS
.clear_row:
        mov     cx,QX_BLUE_SEG
        mov     es,cx
        mov     cx,BUNKER_BYTES
        xor     al,al
        push    di
        rep     stosb
        pop     di
        mov     cx,QX_RED_SEG
        mov     es,cx
        mov     cx,BUNKER_BYTES
        push    di
        rep     stosb
        pop     di
        mov     cx,QX_GREEN_SEG
        mov     es,cx
        mov     cx,BUNKER_BYTES
        push    di
        rep     stosb
        pop     di
        add     di,0100h
        dec     dx
        jnz     .clear_row
        xor     ax,ax
        mov     al,bl
        mov     si,BUNKER_SIZE
        mul     si
        add     ax,bunker_data
        mov     si,ax
        call    draw_one_bunker
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; Input AL=bunker index, AH=local byte, DL=local row.
; Remove a compact 3-row crater plus side pixels on the center row.
damage_bunker:
        ; Preserve all three input fields before doing any multiplication:
        ;   AL = bunker index, AH = local byte, DL = local row.
        ; The previous version reused AH after MUL, but MUL overwrites AX.
        ; That could index outside bunker_data and corrupt game/timing state.
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di

        mov     ch,al                    ; CH = bunker index
        mov     cl,ah                    ; CL = local byte 0..5
        mov     dh,dl                    ; DH = local row 0..11

        ; SI = bunker_data + bunker_index * BUNKER_SIZE
        xor     ax,ax
        mov     al,ch
        mov     bx,BUNKER_SIZE
        mul     bx
        add     ax,bunker_data
        mov     si,ax

        ; DI = local_row * BUNKER_BYTES + local_byte
        xor     ax,ax
        mov     al,dh
        mov     bx,BUNKER_BYTES
        mul     bx
        xor     bx,bx
        mov     bl,cl
        add     ax,bx
        mov     di,ax
        add     si,di

        ; Remove center byte and a compact cross-shaped crater.
        mov     byte [si],0
        cmp     dh,0
        je      .no_up
        mov     byte [si-BUNKER_BYTES],0
.no_up:
        cmp     dh,BUNKER_ROWS-1
        jae     .no_down
        mov     byte [si+BUNKER_BYTES],0
.no_down:
        cmp     cl,0
        je      .no_left
        mov     byte [si-1],0
.no_left:
        cmp     cl,BUNKER_BYTES-1
        jae     .redraw
        mov     byte [si+1],0
.redraw:
        xor     ax,ax
        mov     al,ch                    ; bunker index for redraw_bunker
        call    redraw_bunker

        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

check_player_bullet_bunker_collision:
        cmp     byte [bullet_active],0
        je      .done
        mov     ax,[bullet_y]
        mov     dx,ax
        add     dx,BULLET_ROWS-1
        cmp     dx,BUNKER_Y
        jb      .done
        cmp     ax,BUNKER_Y+BUNKER_ROWS-1
        ja      .done
        mov     bx,[bullet_x_byte]
        call    locate_bunker_from_x
        jc      .done
        ; AL=index, AH=local byte
        mov     dx,[bullet_y]
        add     dx,BULLET_ROWS/2
        sub     dx,BUNKER_Y
        cmp     dl,BUNKER_ROWS
        jb      .hit
        mov     dl,BUNKER_ROWS-1
.hit:
        mov     byte [bullet_active],0
        call    sound_bunker_hit
        call    damage_bunker
.done:
        ret

check_enemy_bullet_bunker_collision:
        cmp     byte [enemy_bullet_active],0
        je      .done
        mov     ax,[enemy_bullet_y]
        mov     dx,ax
        add     dx,ENEMY_BULLET_ROWS-1
        cmp     dx,BUNKER_Y
        jb      .done
        cmp     ax,BUNKER_Y+BUNKER_ROWS-1
        ja      .done
        mov     bx,[enemy_bullet_x_byte]
        call    locate_bunker_from_x
        jc      .done
        mov     dx,[enemy_bullet_y]
        add     dx,ENEMY_BULLET_ROWS/2
        sub     dx,BUNKER_Y
        cmp     dl,BUNKER_ROWS
        jb      .hit
        mov     dl,BUNKER_ROWS-1
.hit:
        mov     byte [enemy_bullet_active],0
        call    sound_bunker_hit
        call    damage_bunker
.done:
        ret

; BX = screen X byte. Return CF clear and AL=index, AH=local byte on hit.
locate_bunker_from_x:
        mov     ax,bx
        sub     ax,BUNKER0_X
        cmp     ax,BUNKER_BYTES
        jb      .b0
        mov     ax,bx
        sub     ax,BUNKER1_X
        cmp     ax,BUNKER_BYTES
        jb      .b1
        mov     ax,bx
        sub     ax,BUNKER2_X
        cmp     ax,BUNKER_BYTES
        jb      .b2
        mov     ax,bx
        sub     ax,BUNKER3_X
        cmp     ax,BUNKER_BYTES
        jb      .b3
        stc
        ret
.b0:    mov ah,al
        xor al,al
        clc
        ret
.b1:    mov ah,al
        mov al,1
        clc
        ret
.b2:    mov ah,al
        mov al,2
        clc
        ret
.b3:    mov ah,al
        mov al,3
        clc
        ret

; ----------------------------------------------------------------------------
; Phase I mystery UFO.
; ----------------------------------------------------------------------------
reset_ufo_system:
        mov     byte [ufo_active],0
        mov     byte [ufo_direction],1
        mov     byte [ufo_shift_phase],0
        mov     byte [ufo_move_period],UFO_MOVE_TICK_DIV
        mov     byte [ufo_move_tick],UFO_MOVE_TICK_DIV
        mov     byte [ufo_reverse_used],0
        mov     byte [ufo_step_counter],0
        mov     byte [ufo_explosion_ticks],0
        call    sound_ufo_stop
        call    set_random_ufo_wait
        ret

set_random_ufo_wait:
        push    ax
        push    bx
        push    dx
        call    random_next
        xor     dx,dx
        mov     bx,UFO_WAIT_RANGE
        div     bx
        add     dx,UFO_WAIT_MIN
        mov     [ufo_wait_countdown],dx
        pop     dx
        pop     bx
        pop     ax
        ret

; Choose a movement period from 9..16 timer ticks.
choose_ufo_speed:
        push    ax
        push    bx
        push    dx
        call    random_next
        xor     dx,dx
        mov     bx,8
        div     bx
        add     dl,9
        mov     [ufo_move_period],dl
        mov     [ufo_move_tick],dl
        pop     dx
        pop     bx
        pop     ax
        ret

update_ufo_timing:
        cmp     byte [game_over],0
        jne     .done
        cmp     byte [ufo_explosion_ticks],0
        je      .no_explosion
        dec     byte [ufo_explosion_ticks]
        jnz     .done
        call    clear_ufo_explosion
        call    set_random_ufo_wait
        jmp     short .done

.no_explosion:
        cmp     byte [ufo_active],0
        jne     .move_active
        cmp     word [ufo_wait_countdown],0
        je      .spawn
        dec     word [ufo_wait_countdown]
        jmp     short .done

.spawn:
        call    spawn_ufo
        jmp     short .done

.move_active:
        dec     byte [ufo_move_tick]
        jnz     .done
        mov     al,[ufo_move_period]
        mov     [ufo_move_tick],al
        call    move_ufo
.done:
        ret

spawn_ufo:
        call    random_next
        test    ax,1
        jz      .from_right
        mov     word [ufo_x_byte],UFO_LEFT_EDGE
        mov     byte [ufo_shift_phase],0
        mov     byte [ufo_direction],1
        jmp     short .activate

.from_right:
        mov     word [ufo_x_byte],UFO_RIGHT_EDGE
        mov     byte [ufo_shift_phase],3
        mov     byte [ufo_direction],0FFh

.activate:
        mov     byte [ufo_active],1
        mov     byte [ufo_reverse_used],0
        mov     byte [ufo_step_counter],0
        call    choose_ufo_speed
        call    draw_ufo
        call    sound_ufo_start
        ret

; Move two pixels per update by selecting one of four pre-shifted frames.
move_ufo:
        cmp     byte [ufo_active],0
        je      .done

        call    erase_ufo

        cmp     byte [ufo_direction],1
        jne     .move_left

.move_right:
        inc     byte [ufo_shift_phase]
        cmp     byte [ufo_shift_phase],4
        jb      .position_ready
        mov     byte [ufo_shift_phase],0
        inc     word [ufo_x_byte]
        mov     ax,[ufo_x_byte]
        cmp     ax,UFO_RIGHT_EDGE
        jbe     .position_ready
        jmp     short .leave

.move_left:
        cmp     byte [ufo_shift_phase],0
        jne     .left_within_byte
        mov     byte [ufo_shift_phase],3
        dec     word [ufo_x_byte]
        mov     ax,[ufo_x_byte]
        cmp     ax,UFO_LEFT_EDGE
        jae     .position_ready
        jmp     short .leave
.left_within_byte:
        dec     byte [ufo_shift_phase]

.position_ready:
        inc     byte [ufo_step_counter]

        ; Every sixteen 2-pixel steps, vary the cruise speed a little.
        mov     al,[ufo_step_counter]
        and     al,0Fh
        jnz     .maybe_reverse
        call    choose_ufo_speed

.maybe_reverse:
        ; At most once per appearance, a UFO may reverse after reaching the
        ; central portion of the screen. Probability is intentionally low.
        cmp     byte [ufo_reverse_used],0
        jne     .draw
        mov     ax,[ufo_x_byte]
        cmp     ax,18
        jb      .draw
        cmp     ax,58
        ja      .draw
        call    random_next
        and     al,07Fh
        jnz     .draw
        neg     byte [ufo_direction]
        mov     byte [ufo_reverse_used],1
        call    sound_ufo_reverse

.draw:
        call    draw_ufo
        jmp     short .done

.leave:
        mov     byte [ufo_active],0
        call    sound_ufo_stop
        call    set_random_ufo_wait
.done:
        ret

; Calculate SI = selected shifted-frame plane data.
; Input: SI = start of plane's four-frame table.
select_ufo_shifted_frame:
        push    ax
        push    bx
        xor     ax,ax
        mov     al,[ufo_shift_phase]
        mov     bx,UFO_ROWS*UFO_DRAW_BYTES
        mul     bx
        add     si,ax
        pop     bx
        pop     ax
        ret

draw_ufo:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es

        mov     ax,UFO_Y
        mov     ah,al
        xor     al,al
        add     ax,[ufo_x_byte]
        mov     di,ax

        mov     si,ufo_blue_shifted
        call    select_ufo_shifted_frame
        mov     ax,QX_BLUE_SEG
        call    draw_ufo_plane

        mov     si,ufo_red_shifted
        call    select_ufo_shifted_frame
        mov     ax,QX_RED_SEG
        call    draw_ufo_plane

        mov     si,ufo_green_shifted
        call    select_ufo_shifted_frame
        mov     ax,QX_GREEN_SEG
        call    draw_ufo_plane

        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = plane segment, SI = frame data, DI = first destination byte.
draw_ufo_plane:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     es,ax
        mov     bx,UFO_ROWS
.row:
        mov     cx,UFO_DRAW_BYTES
.byte:
        mov     al,[cs:si]
        mov     [es:di],al
        inc     si
        inc     di
        loop    .byte
        sub     di,UFO_DRAW_BYTES
        add     di,0100h
        dec     bx
        jnz     .row
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

erase_ufo:
        push    ax
        push    bx
        push    cx
        push    di
        push    es

        mov     ax,UFO_Y
        mov     ah,al
        xor     al,al
        add     ax,[ufo_x_byte]
        mov     di,ax
        mov     bx,UFO_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        push    di
        xor     ax,ax
        mov     cx,UFO_DRAW_BYTES
        rep     stosb
        pop     di

        mov     ax,QX_RED_SEG
        mov     es,ax
        push    di
        xor     ax,ax
        mov     cx,UFO_DRAW_BYTES
        rep     stosb
        pop     di

        mov     ax,QX_GREEN_SEG
        mov     es,ax
        push    di
        xor     ax,ax
        mov     cx,UFO_DRAW_BYTES
        rep     stosb
        pop     di

        add     di,0100h
        dec     bx
        jnz     .row

        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

check_player_bullet_ufo_collision:
        cmp     byte [ufo_active],0
        je      .done
        push    ax
        push    bx
        push    dx

        mov     ax,[bullet_y]
        mov     dx,ax
        add     dx,BULLET_ROWS-1
        cmp     dx,UFO_Y
        jb      .restore
        cmp     ax,UFO_Y+UFO_ROWS-1
        ja      .restore

        mov     ax,[bullet_x_byte]
        mov     bx,[ufo_x_byte]
        cmp     ax,bx
        jb      .restore
        add     bx,UFO_DRAW_BYTES-1
        cmp     ax,bx
        ja      .restore

        mov     byte [bullet_active],0
        call    erase_ufo
        mov     byte [ufo_active],0
        call    sound_ufo_stop

        mov     ax,[ufo_x_byte]
        cmp     ax,1
        jae     .xok
        mov     ax,1
.xok:
        dec     ax
        mov     [ufo_explosion_x],ax
        mov     byte [ufo_explosion_ticks],UFO_EXPLOSION_TICKS
        add     word [score_value],UFO_SCORE
        call    draw_score
        call    start_ufo_red_flash
        call    sound_ufo_destroyed
        call    draw_ufo_explosion

.restore:
        pop     dx
        pop     bx
        pop     ax
.done:
        ret

draw_ufo_explosion:
        push    ax
        push    bx
        push    cx
        push    di
        push    es
        mov     ax,UFO_Y-2
        mov     ah,al
        xor     al,al
        add     ax,[ufo_explosion_x]
        mov     di,ax
        xor     bx,bx
        mov     cx,UFO_EXPLOSION_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     ax,[cs:ufo_explosion_blue+bx]
        mov     [es:di],ax
        mov     ax,[cs:ufo_explosion_blue+bx+2]
        mov     [es:di+2],ax
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     ax,[cs:ufo_explosion_red+bx]
        mov     [es:di],ax
        mov     ax,[cs:ufo_explosion_red+bx+2]
        mov     [es:di+2],ax
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     ax,[cs:ufo_explosion_green+bx]
        mov     [es:di],ax
        mov     ax,[cs:ufo_explosion_green+bx+2]
        mov     [es:di+2],ax
        add     bx,UFO_EXPLOSION_BYTES
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret

clear_ufo_explosion:
        push    ax
        push    cx
        push    di
        push    es
        mov     ax,UFO_Y-2
        mov     ah,al
        xor     al,al
        add     ax,[ufo_explosion_x]
        mov     di,ax
        mov     cx,UFO_EXPLOSION_ROWS
.row:
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     word [es:di+2],0
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     word [es:di+2],0
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     word [es:di],0
        mov     word [es:di+2],0
        add     di,0100h
        loop    .row
        pop     es
        pop     di
        pop     cx
        pop     ax
        ret

; ----------------------------------------------------------------------------
; ============================================================================
; BASIC NON-BLOCKING SOUND - SN76489AN at I/O port 14h
;
; Tone channel 0: four-step alien movement pulse
; Tone channel 1: player shot
; Tone channel 2: UFO chirp
; Noise channel 3: alien/player explosions
;
; 0EACh effect only programs the chip and starts a short software lifetime.
; update_sound_timing() later mutes the channel without blocking game motion.
; ============================================================================
sound_init:
        mov     byte [sound_step_index],0
        mov     byte [sound_ufo_phase],0
        mov     byte [sound_ch0_ticks],0
        mov     byte [sound_ch1_ticks],0
        mov     byte [sound_ch2_ticks],0
        mov     byte [sound_noise_ticks],0
        mov     byte [sound_shot_volume],3
        mov     word [sound_shot_period],0048h
        mov     byte [sound_shot_sweep_div],0
        mov     byte [sound_noise_volume],15
        mov     byte [sound_noise_decay_div],0
        mov     byte [sound_noise_phase],0
        mov     byte [sound_noise_kind],0
        mov     byte [sound_alien_hit_variant],0
        mov     byte [sound_ufo_enabled],0
        mov     word [sound_ufo_period],0180h
        mov     byte [sound_ufo_sweep_dir],0FFh
        mov     byte [sound_ufo_sweep_tick],1
        mov     byte [sound_bonus_active],0
        mov     byte [sound_bonus_phase],0
        mov     byte [sound_bonus_tick],0
        mov     byte [sound_shot_echo_ticks],0
        mov     byte [sound_shot_echo_active],0
        call    sound_mute_all
        ret

sound_mute_all:
        push    ax
        push    dx
        mov     dx,SOUND_PORT
        mov     al,09Fh
        out     dx,al
        mov     al,0BFh
        out     dx,al
        mov     al,0DFh
        out     dx,al
        mov     al,0FFh
        out     dx,al
        pop     dx
        pop     ax
        ret

; AX = 10-bit period, BL = attenuation 0=loudest .. 15=mute.
sound_write_ch0:
        push    ax
        push    bx
        push    cx
        push    dx
        mov     dx,SOUND_PORT
        mov     cx,ax
        and     al,0Fh
        or      al,080h
        out     dx,al
        mov     ax,cx
        mov     cl,4
        shr     ax,cl
        and     al,03Fh
        out     dx,al
        mov     al,bl
        and     al,0Fh
        or      al,090h
        out     dx,al
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

sound_write_ch1:
        push    ax
        push    bx
        push    cx
        push    dx
        mov     dx,SOUND_PORT
        mov     cx,ax
        and     al,0Fh
        or      al,0A0h
        out     dx,al
        mov     ax,cx
        mov     cl,4
        shr     ax,cl
        and     al,03Fh
        out     dx,al
        mov     al,bl
        and     al,0Fh
        or      al,0B0h
        out     dx,al
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

sound_write_ch2:
        push    ax
        push    bx
        push    cx
        push    dx
        mov     dx,SOUND_PORT
        mov     cx,ax
        and     al,0Fh
        or      al,0C0h
        out     dx,al
        mov     ax,cx
        mov     cl,4
        shr     ax,cl
        and     al,03Fh
        out     dx,al
        mov     al,bl
        and     al,0Fh
        or      al,0D0h
        out     dx,al
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; Gold alien march: a short lead pulse plus a deeper bass layer.
; Channel 2 is used for the bass only when the UFO and major explosions are idle.
sound_alien_step:
        push    ax
        push    bx
        push    dx

        xor     bx,bx
        mov     bl,[sound_step_index]
        mov     ax,[cs:sound_alien_periods+bx]
        mov     dx,ax

        mov     bl,03h
        call    sound_write_ch0
        mov     byte [sound_ch0_ticks],8

        cmp     byte [sound_ufo_enabled],0
        jne     .advance
        cmp     byte [sound_noise_kind],2
        je      .advance
        shl     dx,1
        mov     ax,dx
        mov     bl,07h
        call    sound_write_ch2
        mov     byte [sound_ch2_ticks],6

.advance:
        add     byte [sound_step_index],2
        and     byte [sound_step_index],6

        pop     dx
        pop     bx
        pop     ax
        ret

; High shot onset followed by a downward sweep and volume decay.
sound_player_shot:
        mov     word [sound_shot_period],0048h
        mov     byte [sound_shot_volume],2
        mov     byte [sound_shot_sweep_div],0
        mov     byte [sound_ch1_ticks],18
        mov     byte [sound_shot_echo_ticks],24
        mov     byte [sound_shot_echo_active],1
        mov     ax,[sound_shot_period]
        mov     bl,[sound_shot_volume]
        call    sound_write_ch1
        ret

; UFO wobble on tone channel 2. Explosions may temporarily override it.
sound_ufo_start:
        mov     word [sound_ufo_period],0180h
        mov     byte [sound_ufo_sweep_dir],0FFh
        mov     byte [sound_ufo_sweep_tick],1
        mov     byte [sound_ufo_enabled],1
        mov     ax,[sound_ufo_period]
        mov     bl,5
        call    sound_write_ch2
        ret

sound_ufo_stop:
        mov     byte [sound_ufo_enabled],0
        cmp     byte [sound_noise_kind],2
        je      .done
        push    ax
        push    dx
        mov     dx,SOUND_PORT
        mov     al,0DFh
        out     dx,al
        pop     dx
        pop     ax
.done:
        ret

sound_ufo_reverse:
        ; A brief high chirp announces the unexpected reversal.
        mov     word [sound_ufo_period],0080h
        mov     byte [sound_ufo_sweep_dir],1
        mov     byte [sound_ufo_sweep_tick],1
        ret

sound_ufo_destroyed:
        ; Strong descending tone layered with the explosion noise.
        mov     word [sound_ufo_period],0050h
        mov     byte [sound_ufo_sweep_dir],1
        mov     byte [sound_ufo_sweep_tick],1
        mov     byte [sound_ufo_enabled],0
        mov     ax,0050h
        mov     bl,1
        call    sound_write_ch2
        mov     byte [sound_ch2_ticks],28
        call    sound_alien_hit
        ret

; Short dull impact for bunker damage.
sound_bunker_hit:
        push    ax
        push    dx
        mov     byte [sound_noise_kind],3
        mov     byte [sound_noise_phase],0
        mov     byte [sound_noise_volume],5
        mov     byte [sound_noise_decay_div],0
        mov     byte [sound_noise_ticks],18
        mov     dx,SOUND_PORT
        mov     al,0E0h                 ; periodic noise, lowest fixed rate
        out     dx,al
        mov     al,0F5h                 ; moderate volume
        out     dx,al
        pop     dx
        pop     ax
        ret

; Wave-complete rising fanfare on tone channel 0.
sound_bonus_fanfare:
        mov     byte [sound_bonus_active],1
        mov     byte [sound_bonus_phase],0
        mov     byte [sound_bonus_tick],1
        ret

; Enemy projectile: short falling pulse, lower and softer than player fire.
sound_enemy_shot:
        push    ax
        push    bx
        mov     ax,0120h
        mov     bl,6
        call    sound_write_ch0
        mov     byte [sound_ch0_ticks],8
        pop     bx
        pop     ax
        ret

; Player-ready cue: two simultaneous tones form a brief rising arcade chime.
sound_player_ready:
        push    ax
        push    bx
        mov     ax,0180h
        mov     bl,4
        call    sound_write_ch0
        mov     byte [sound_ch0_ticks],14

        mov     ax,00C0h
        mov     bl,5
        call    sound_write_ch1
        mov     byte [sound_ch1_ticks],14
        mov     byte [sound_shot_volume],5
        mov     word [sound_shot_period],00C0h
        pop     bx
        pop     ax
        ret

; Alien explosion: bright white-noise crack with a short red-noise tail.
sound_alien_hit:
        push    ax
        push    bx
        push    dx
        mov     byte [sound_noise_kind],1
        mov     byte [sound_noise_phase],0
        mov     byte [sound_noise_volume],0
        mov     byte [sound_noise_decay_div],0
        mov     byte [sound_noise_ticks],42
        mov     dx,SOUND_PORT
        mov     al,0E4h                 ; white noise, highest fixed rate
        out     dx,al
        mov     al,0F0h                 ; maximum noise volume
        out     dx,al
        ; Alternate the tonal impact so consecutive alien kills do not
        ; sound mechanically identical.
        xor     byte [sound_alien_hit_variant],1
        mov     ax,0060h
        cmp     byte [sound_alien_hit_variant],0
        je      .tone_ready
        mov     ax,0088h
.tone_ready:
        mov     bl,4
        call    sound_write_ch2
        mov     byte [sound_ch2_ticks],12
        pop     dx
        pop     bx
        pop     ax
        ret

; Player explosion: maximum-volume white noise plus low tone-2 rumble.
; A software envelope gradually increases attenuation, creating decay.
sound_player_hit:
        push    ax
        push    bx
        push    dx
        mov     byte [sound_noise_kind],2
        mov     byte [sound_noise_phase],0
        mov     byte [sound_noise_volume],0
        mov     byte [sound_noise_decay_div],0
        mov     byte [sound_noise_ticks],132
        mov     dx,SOUND_PORT
        mov     al,0E7h                 ; white noise clocked from tone channel 2
        out     dx,al
        mov     al,0F0h                 ; maximum volume
        out     dx,al
        mov     ax,02C0h                ; deep rumble period on channel 2
        mov     bl,1
        call    sound_write_ch2
        mov     byte [sound_ch2_ticks],108

        mov     ax,0360h                ; second, lower rumble layer
        mov     bl,3
        call    sound_write_ch0
        mov     byte [sound_ch0_ticks],72
        pop     dx
        pop     bx
        pop     ax
        ret

update_sound_timing:
        push    ax
        push    bx
        push    dx
        mov     dx,SOUND_PORT

        ; Alien march pulse: abrupt mute, like the arcade effect.
        cmp     byte [sound_ch0_ticks],0
        je      .shot
        dec     byte [sound_ch0_ticks]
        jnz     .shot
        mov     al,09Fh
        out     dx,al

.shot:
        ; Pitch sweep every two game ticks; attenuate every second sweep.
        cmp     byte [sound_ch1_ticks],0
        je      .shot_echo
        dec     byte [sound_ch1_ticks]
        jz      .mute_shot
        inc     byte [sound_shot_sweep_div]
        test    byte [sound_shot_sweep_div],1
        jnz     .shot_echo
        add     word [sound_shot_period],0012h
        test    byte [sound_shot_sweep_div],2
        jz      .write_shot
        cmp     byte [sound_shot_volume],13
        jae     .write_shot
        inc     byte [sound_shot_volume]
.write_shot:
        mov     ax,[sound_shot_period]
        mov     bl,[sound_shot_volume]
        call    sound_write_ch1
        jmp     .shot_echo
.mute_shot:
        mov     al,0BFh
        out     dx,al

.shot_echo:
        cmp     byte [sound_shot_echo_active],0
        je      .ch2
        cmp     byte [sound_shot_echo_ticks],0
        je      .play_echo
        dec     byte [sound_shot_echo_ticks]
        jmp     short .ch2

.play_echo:
        mov     byte [sound_shot_echo_active],0
        mov     ax,00B0h
        mov     bl,0Ah
        call    sound_write_ch1
        mov     byte [sound_ch1_ticks],8

.ch2:
        cmp     byte [sound_ch2_ticks],0
        je      .ufo_siren
        dec     byte [sound_ch2_ticks]
        jnz     .bonus
        mov     al,0DFh
        out     dx,al

.ufo_siren:
        cmp     byte [sound_ufo_enabled],0
        je      .bonus
        cmp     byte [sound_noise_kind],2
        je      .bonus
        dec     byte [sound_ufo_sweep_tick]
        jnz     .bonus
        mov     byte [sound_ufo_sweep_tick],3

        cmp     byte [sound_ufo_sweep_dir],1
        je      .ufo_period_up
        sub     word [sound_ufo_period],0006h
        cmp     word [sound_ufo_period],00A0h
        jae     .write_ufo
        mov     word [sound_ufo_period],00A0h
        mov     byte [sound_ufo_sweep_dir],1
        jmp     short .write_ufo

.ufo_period_up:
        add     word [sound_ufo_period],0006h
        cmp     word [sound_ufo_period],01A0h
        jbe     .write_ufo
        mov     word [sound_ufo_period],01A0h
        mov     byte [sound_ufo_sweep_dir],0FFh

.write_ufo:
        mov     ax,[sound_ufo_period]
        mov     bl,5
        call    sound_write_ch2

.bonus:
        cmp     byte [sound_bonus_active],0
        je      .noise
        dec     byte [sound_bonus_tick]
        jnz     .noise
        mov     byte [sound_bonus_tick],12
        xor     bx,bx
        mov     bl,[sound_bonus_phase]
        shl     bx,1
        mov     ax,[cs:sound_bonus_periods+bx]
        cmp     ax,0FFFFh
        je      .bonus_done
        mov     bl,2
        call    sound_write_ch0
        inc     byte [sound_bonus_phase]
        jmp     short .noise
.bonus_done:
        mov     byte [sound_bonus_active],0
        mov     al,09Fh
        out     dx,al

.noise:
        cmp     byte [sound_noise_ticks],0
        je      .done
        dec     byte [sound_noise_ticks]
        jz      .mute_noise

        ; Change noise character during the tail.
        inc     byte [sound_noise_phase]
        mov     al,[sound_noise_phase]
        cmp     al,8
        jne     .check_phase2
        mov     al,0E5h
        out     dx,al
.check_phase2:
        cmp     byte [sound_noise_phase],20
        jne     .decay
        mov     al,0E6h
        out     dx,al

.decay:
        inc     byte [sound_noise_decay_div]
        mov     al,[sound_noise_kind]
        cmp     al,2
        je      .player_decay
        cmp     byte [sound_noise_decay_div],3
        jb      .done
        jmp     .do_decay
.player_decay:
        cmp     byte [sound_noise_decay_div],6
        jb      .done
.do_decay:
        mov     byte [sound_noise_decay_div],0
        cmp     byte [sound_noise_volume],14
        jae     .done
        inc     byte [sound_noise_volume]
        mov     al,[sound_noise_volume]
        and     al,0Fh
        or      al,0F0h
        out     dx,al
        jmp     .done

.mute_noise:
        mov     al,0FFh
        out     dx,al
        mov     byte [sound_noise_kind],0
.done:
        pop     dx
        pop     bx
        pop     ax
        ret

sound_alien_periods:
        dw      02B0h,0230h,01D0h,0170h

sound_bonus_periods:
        dw      0240h,01C0h,0150h,0100h,00C0h,0090h,0068h,0FFFFh


; ============================================================================
; SCREEN VISUAL EFFECTS
; ============================================================================
; UFO destruction uses a reversible Red-plane XOR flash. Every black background
; pixel becomes red, and a second XOR restores the exact original image without
; requiring a 16 KiB backup buffer.
;
; Player impact uses the same GAVDP display-origin registers as the SCI driver:
;   8000:C462h = physical 8C462h, horizontal origin
;   8000:C663h = physical 8C663h, vertical origin
; The effect alternates between origins 0 and 2 and always restores both to 0.

start_ufo_red_flash:
        cmp     byte [red_flash_active],0
        jne     .restart_timer
        call    xor_visible_red_plane
        mov     byte [red_flash_active],1
.restart_timer:
        mov     byte [red_flash_ticks],UFO_RED_FLASH_TICKS
        ret

finish_ufo_red_flash:
        cmp     byte [red_flash_active],0
        je      .done
        call    xor_visible_red_plane
        mov     byte [red_flash_active],0
        mov     byte [red_flash_ticks],0
.done:
        ret

; XOR the 80 visible bytes of every 256-byte color row in the Red plane.
; This is infrequent (only on a UFO kill) and exactly reversible.
xor_visible_red_plane:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es

        mov     ax,QX_RED_SEG
        mov     es,ax
        xor     di,di
        mov     dx,200
.row:
        mov     cx,80
.byte:
        xor     byte [es:di],0FFh
        inc     di
        loop    .byte
        add     di,0100h-80
        dec     dx
        jnz     .row

        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

start_player_screen_shake:
        mov     byte [screen_shake_ticks],PLAYER_SHAKE_TICKS
        mov     byte [screen_shake_phase],0
        call    write_normal_origins
        ret

update_visual_effects:
        ; UFO red flash timer.
        cmp     byte [red_flash_active],0
        je      .shake
        cmp     byte [red_flash_ticks],0
        je      .finish_red
        dec     byte [red_flash_ticks]
        jnz     .shake
.finish_red:
        call    finish_ufo_red_flash

.shake:
        cmp     byte [screen_shake_ticks],0
        je      .done

        dec     byte [screen_shake_ticks]
        jz      .shake_done

        xor     byte [screen_shake_phase],1
        cmp     byte [screen_shake_phase],0
        je      .normal_phase
        call    write_shifted_origins
        jmp     .done

.normal_phase:
        call    write_normal_origins
        jmp     .done

.shake_done:
        call    write_normal_origins
        mov     byte [screen_shake_phase],0
.done:
        ret

write_shifted_origins:
        push    ax
        push    es
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     al,SHAKE_AMOUNT
        mov     [es:GAVDP_HORIGIN],al
        mov     [es:GAVDP_VORIGIN],al
        pop     es
        pop     ax
        ret

write_normal_origins:
        push    ax
        push    es
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        xor     al,al
        mov     [es:GAVDP_HORIGIN],al
        mov     [es:GAVDP_VORIGIN],al
        pop     es
        pop     ax
        ret

stop_visual_effects:
        call    finish_ufo_red_flash
        call    write_normal_origins
        mov     byte [screen_shake_ticks],0
        mov     byte [screen_shake_phase],0
        ret

; Native QX-11 INT 71h timer pacing (~388.8 Hz on real hardware).
; ----------------------------------------------------------------------------
install_int71_timer:
        push    ax
        push    bx
        push    dx
        push    es
        mov     ax,3571h               ; DOS: get INT 71h vector
        int     21h                    ; ES:BX = old INT 71h handler
        mov     [cs:old_int71_off],bx
        mov     [cs:old_int71_seg],es
        push    cs
        pop     ds
        mov     dx,int71_handler
        mov     ax,2571h               ; DOS: set INT 71h vector DS:DX
        int     21h
        mov     byte [cs:int71_installed],1
        pop     es
        pop     dx
        pop     bx
        pop     ax
        ret

restore_int71_timer:
        cmp     byte [cs:int71_installed],0
        je      .done
        push    ax
        push    dx
        push    ds
        mov     ax,[cs:old_int71_seg]
        mov     ds,ax
        mov     dx,[cs:old_int71_off]
        mov     ax,2571h
        int     21h
        mov     byte [cs:int71_installed],0
        pop     ds
        pop     dx
        pop     ax
.done:
        ret

int71_handler:
        push    ax
        push    ds

        push    cs
        pop     ds

        ; Fractional divider: add 2 on 0EACh native INT 71h interrupt and
        ; generate one game tick whenever the accumulator reaches 5.
        ; This yields one game tick per 2.5 INT 71h interrupts:
        ;     388.8 Hz / 2.5 = approximately 155.52 Hz.
        ; The physical intervals naturally alternate 3,2,3,2... interrupts.
        add     byte [int71_accumulator],2
        cmp     byte [int71_accumulator],5
        jb      .chain
        sub     byte [int71_accumulator],5
        inc     word [game_ticks]

.chain:
        pop     ds
        pop     ax
        jmp     far [cs:old_int71_off]

wait_for_int71_tick:
.wait:
        mov     ax,[cs:game_ticks]
        cmp     ax,[cs:last_game_tick]
        je      .wait
        ; Snap to the newest tick. Rendering time never creates a backlog.
        mov     [cs:last_game_tick],ax
        ret

process_game_tick:
        call    poll_player_input
        call    update_player_bullet_timing
        call    update_enemy_system_timing
        call    update_ufo_timing
        call    update_explosion_state
        call    update_visual_effects
        call    update_sound_timing

        cmp     byte [game_over],0
        jne     .done

        dec     word [alien_countdown]
        jnz     .done
        mov     ax,[alien_period]
        mov     [alien_countdown],ax

        call    erase_formation
        call    update_formation_position
        call    check_round_end_conditions
        cmp     byte [game_over],0
        jne     .done
        cmp     byte [wave_clear_active],0
        jne     .done

        xor     byte [frame_number],1
        call    draw_formation
        call    sound_alien_step
.done:
        ret

; ----------------------------------------------------------------------------
; Clear only 80 visible bytes in 0EACh 256-byte color row.
; ----------------------------------------------------------------------------
clear_color_screen:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        mov     bx,QX_BLUE_SEG
        call    clear_plane
        mov     bx,QX_RED_SEG
        call    clear_plane
        mov     bx,QX_GREEN_SEG
        call    clear_plane
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

clear_plane:
        mov     es,bx
        xor     di,di
        mov     dx,200
        xor     ax,ax
.row:
        mov     cx,40
        rep     stosw
        add     di,0100h-0050h
        dec     dx
        jnz     .row
        ret

; ----------------------------------------------------------------------------
; State
; ----------------------------------------------------------------------------
old_mode              db 0
exit_requested        db 0
player_x_byte         dw SHIP_START_X
player_y              dw SHIP_Y
bullet_active         db 0
bullet_tick           db BULLET_TICK_DIV
bullet_x_byte         dw 0
bullet_y              dw 0
bullet2_active        db 0
bullet2_tick          db BULLET_TICK_DIV
bullet2_x_byte        dw 0
bullet2_y             dw 0
enemy_bullet_active   db 0
enemy_bullet_tick     db ENEMY_BULLET_TICK_DIV
enemy_fire_countdown  dw ENEMY_FIRE_MIN
enemy_fire_column     db 0
random_state          dw 0ACE1h
enemy_bullet_x_byte   dw 0
enemy_bullet_y        dw 0
player_alive          db 1
player_lives          db PLAYER_START_LIVES
game_over             db 0
wave_clear_active     db 0
wave_clear_countdown  dw 0
wave_number           db 1
player_explosion_ticks db 0
frame_number          db 0
formation_x           dw START_X_BYTE
formation_y           dw START_Y
direction             db 1
render_mode           db 1
current_x_byte        dw 0
current_y             dw 0
sprite_blue_ptr      dw 0
sprite_red_ptr       dw 0
sprite_green_ptr     dw 0
row_y                  dw 0
game_ticks            dw 0
red_flash_active      db 0
red_flash_ticks       db 0
screen_shake_ticks    db 0
screen_shake_phase    db 0
int71_accumulator db 0        ; fractional divide-by-2.5 accumulator
last_game_tick         dw 0
alien_period           dw ALIEN_START_PERIOD
alien_countdown        dw ALIEN_START_PERIOD
old_int71_off          dw 0
old_int71_seg          dw 0
int71_installed        db 0
alien_index           db 0
kill_countdown        db KILL_INTERVAL
kill_cursor           db 54
collision_index       db 0
collision_x_byte      dw 0
collision_row_y       dw 0
explosion_index       db 0FFh
explosion_ticks       db 0
explosion_x_byte      dw 0
explosion_y           dw 0
score_value           dw 0
score_digits          times 5 db 0
alive_count           db ALIEN_COUNT
drop_count            db 0
left_live_col         db 0
right_live_col        db 10
alive_table           times ALIEN_COUNT db 1
bottom_alien_table    times ALIENS_PER_ROW db 0FFh
bunker_data           times BUNKER_COUNT*BUNKER_SIZE db 0
ufo_active            db 0
ufo_direction         db 1
ufo_move_tick         db UFO_MOVE_TICK_DIV
ufo_wait_countdown    dw UFO_WAIT_MIN
ufo_x_byte            dw UFO_LEFT_EDGE
ufo_shift_phase       db 0
ufo_move_period       db UFO_MOVE_TICK_DIV
ufo_reverse_used      db 0
ufo_step_counter      db 0
ufo_explosion_ticks   db 0
ufo_explosion_x       dw 0

; Non-blocking SN76489 channel lifetimes and phases.
sound_step_index      db 0
sound_ufo_phase       db 0
sound_ch0_ticks       db 0
sound_ch1_ticks       db 0
sound_ch2_ticks       db 0
sound_noise_ticks     db 0
sound_shot_period     dw 0048h
sound_shot_volume     db 3
sound_shot_sweep_div  db 0
sound_noise_volume    db 15
sound_noise_decay_div db 0
sound_noise_phase     db 0
sound_noise_kind      db 0       ; 0 none, 1 alien hit, 2 player, 3 bunker
sound_alien_hit_variant db 0
sound_ufo_enabled     db 0
sound_ufo_period      dw 0180h
sound_ufo_sweep_dir   db 0FFh
sound_ufo_sweep_tick  db 1
sound_bonus_active    db 0
sound_bonus_phase     db 0
sound_bonus_tick      db 0
sound_shot_echo_ticks db 0
sound_shot_echo_active db 0
splash_row_offset     dw 0
splash_row_number     dw 0
splash_dst_offset     dw 0

; ----------------------------------------------------------------------------
; Sprite data: 16x8, two bytes per row, bit 7 leftmost.
; ----------------------------------------------------------------------------

; Integrated 320x120 splash plane data.
; ============================================================================
; ARTISTIC 320x120 QX-11 SPLASH (3 planar 1bpp images)
; Generated for the native 8-color palette.
; ============================================================================

; ============================================================================
; PHASE P ARTISTIC 320x120 QX-11 SPLASH — exact 8-color planar artwork
; ============================================================================

splash_blue:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0FEh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0F0h,08h,00h,00h,00h,00h,00h,00h,00h,7Fh,0FFh,0E0h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh,00h,00h,00h,00h,00h,00h,00h
        db 03h,0F8h,01h,0FCh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,01h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,80h,00h,00h,00h,00h,02h,0Ch,0Fh,80h,00h,1Fh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0F0h,00h,00h,00h,00h,00h,00h
        db 1Eh,07h,0FEh,07h,80h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FEh,00h,00h,00h,00h,00h,00h,78h,38h,01h,0C1h,0E0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,00h,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,80h,0Ch,00h,00h,00h,00h
        db 0E1h,0C0h,00h,38h,70h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,80h,00h,00h,00h,01h,0C6h,00h,10h,06h,38h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h,00h,00h,00h,03h
        db 08h,00h,00h,01h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,8Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0F8h,00h,00h,00h,06h,10h,00h,00h,00h,86h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh,00h,00h,00h,0Ch
        db 60h,11h,01h,10h,63h,00h,00h,20h,00h,00h,00h,3Fh,00h,00h,00h,00h
        db 00h,00h,00h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,80h,00h,00h,18h,80h,00h,00h,00h,11h,80h,00h,00h
        db 00h,00h,00h,0FFh,0C0h,00h,00h,00h,00h,00h,00h,03h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h,00h,00h,39h
        db 00h,00h,00h,00h,09h,0C0h,00h,00h,00h,00h,01h,40h,0A0h,00h,00h,00h
        db 00h,00h,00h,0Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0F8h,00h,00h,31h,01h,00h,10h,01h,08h,0C0h,00h,00h
        db 00h,00h,03h,80h,70h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh,00h,00h,62h
        db 00h,00h,00h,00h,04h,60h,00h,00h,00h,00h,05h,00h,28h,00h,00h,00h
        db 00h,00h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,80h,00h,0E4h,00h,00h,00h,00h,02h,70h,00h,00h
        db 00h,00h,06h,00h,18h,00h,00h,00h,00h,00h,03h,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h,00h,0C9h
        db 10h,11h,01h,10h,11h,30h,00h,00h,00h,00h,0Ch,00h,0Ch,00h,00h,00h
        db 00h,00h,0Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0F8h,01h,0C0h,00h,00h,00h,00h,01h,38h,00h,00h
        db 00h,00h,0Ch,00h,0Ch,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh,01h,80h
        db 00h,00h,00h,00h,00h,98h,00h,00h,00h,00h,08h,00h,0Ch,00h,00h,00h
        db 00h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,81h,80h,01h,00h,10h,01h,00h,98h,00h,00h
        db 00h,00h,08h,00h,0Ch,00h,00h,00h,00h,03h,0FFh,0FFh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0FFh,0E3h,00h
        db 00h,00h,00h,00h,00h,8Ch,00h,02h,00h,00h,08h,00h,0Ch,00h,00h,00h
        db 00h,00h,0FFh,0FFh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,7Fh,0FFh,0C3h,00h,00h,00h,00h,03h,00h,4Ch,00h,00h
        db 00h,00h,08h,00h,0Ch,00h,00h,00h,00h,00h,3Fh,0FFh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0FFh,03h,01h
        db 10h,11h,01h,10h,10h,4Ch,00h,00h,00h,00h,04h,00h,18h,00h,00h,00h
        db 00h,00h,0Fh,0FFh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,7Fh,0FCh,03h,00h,00h,00h,00h,00h,00h,4Ch,00h,00h
        db 00h,08h,04h,00h,08h,00h,00h,00h,00h,03h,03h,0FFh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0F0h,06h,00h
        db 00h,80h,00h,00h,00h,26h,00h,00h,00h,00h,02h,00h,10h,00h,00h,00h
        db 00h,00h,00h,0FFh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,7Fh,0C0h,06h,10h,01h,00h,10h,01h,00h,26h,00h,00h
        db 00h,00h,01h,00h,20h,00h,00h,00h,00h,00h,00h,3Fh,0F8h,1Fh,81h,0F8h
        db 1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,00h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,0C0h,0C0h,00h,00h,00h
        db 00h,00h,00h,0Fh,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h
        db 0F8h,1Fh,81h,0F8h,1Ch,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,3Fh,00h,00h,00h,00h,00h,00h,00h,03h,0F8h,1Fh,81h,0F8h
        db 1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,10h,00h,06h,01h
        db 10h,11h,01h,10h,11h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h,0F8h,1Fh,81h
        db 0F8h,1Fh,81h,0F8h,00h,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,10h,20h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h
        db 00h,00h,00h,00h,0Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FCh,00h,00h,06h,10h,01h,00h,10h,01h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,08h,08h
        db 48h,08h,08h,08h,08h,08h,08h,09h,08h,08h,20h,00h,00h,00h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,04h,10h,50h,50h,50h,10h,50h,10h,50h,10h,51h
        db 10h,50h,10h,00h,00h,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,20h,22h
        db 0A0h,22h,20h,22h,20h,22h,20h,22h,0A0h,22h,10h,00h,00h,00h,03h,01h
        db 10h,11h,01h,10h,10h,4Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 40h,00h,00h,00h,00h,08h,50h,40h,0D0h,40h,50h,40h,50h,40h,50h,40h
        db 0D0h,40h,48h,00h,10h,00h,03h,00h,00h,00h,00h,00h,00h,4Ch,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,80h,80h
        db 80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,88h,00h,00h,00h,03h,00h
        db 00h,00h,00h,00h,00h,4Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0Dh,01h,05h,81h,05h,01h,05h,01h,05h,01h,05h
        db 81h,05h,08h,00h,00h,00h,03h,00h,01h,00h,10h,01h,00h,8Ch,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,12h,22h,03h
        db 22h,02h,22h,02h,22h,02h,22h,02h,62h,02h,24h,00h,00h,00h,01h,80h
        db 00h,00h,00h,00h,00h,98h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,04h,00h,14h,05h,05h,05h,04h,05h,04h,05h,04h,05h,04h
        db 45h,04h,04h,00h,00h,00h,01h,80h,00h,00h,00h,00h,00h,98h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,18h,08h,09h
        db 08h,08h,08h,08h,08h,08h,08h,08h,48h,08h,04h,00h,00h,00h,01h,0C1h
        db 10h,11h,01h,10h,10h,38h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,30h,50h,11h,50h,10h,50h,10h,50h,10h,50h,10h
        db 50h,10h,5Ah,00h,00h,00h,00h,0C0h,00h,00h,00h,00h,00h,30h,00h,00h
        db 00h,00h,00h,00h,00h,00h,7Fh,01h,0F8h,0Fh,0C0h,00h,0FEh,20h,7Fh,22h
        db 0A2h,0FCh,3Fh,27h,0EFh,0E1h,3Fh,0AFh,0E2h,2Fh,0FEh,00h,0FFh,0FCh,7Fh,0F0h
        db 00h,0FFh,00h,00h,10h,70h,00h,00h,00h,00h,00h,00h,00h,01h,80h,0E1h
        db 04h,10h,40h,07h,01h,53h,80h,0D2h,41h,04h,40h,0D4h,18h,30h,60h,0D8h
        db 10h,50h,01h,0C1h,00h,04h,80h,0Ch,03h,00h,0F0h,01h,00h,60h,00h,00h
        db 00h,00h,30h,00h,00h,06h,00h,30h,82h,30h,0C0h,04h,01h,42h,00h,82h
        db 81h,04h,0C0h,84h,14h,20h,0A0h,90h,10h,90h,00h,61h,00h,04h,80h,02h
        db 06h,00h,20h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,0Ch,00h,08h
        db 83h,20h,0C0h,04h,01h,42h,00h,83h,05h,05h,40h,44h,14h,11h,21h,90h
        db 1Dh,10h,00h,11h,00h,04h,80h,01h,0Ch,00h,20h,00h,01h,0C0h,00h,00h
        db 00h,00h,00h,18h,00h,08h,1Eh,0Ch,41h,41h,80h,04h,0C1h,22h,60h,0A2h
        db 03h,04h,40h,64h,14h,12h,41h,30h,0Ah,30h,78h,09h,07h,0FCh,83h,0C1h
        db 08h,3Eh,21h,10h,01h,80h,00h,00h,00h,00h,00h,00h,00h,10h,73h,04h
        db 20h,0C3h,00h,07h,0C1h,07h,0E0h,85h,05h,05h,40h,24h,16h,1Dh,41h,20h
        db 0Ch,10h,46h,09h,04h,00h,82h,61h,88h,61h,0A0h,00h,03h,00h,00h,00h
        db 00h,00h,00h,00h,80h,10h,41h,06h,30h,02h,00h,00h,41h,08h,20h,8Ch
        db 09h,04h,40h,3Ch,12h,08h,0C3h,21h,04h,10h,49h,05h,04h,00h,82h,21h
        db 88h,40h,60h,08h,06h,00h,00h,00h,00h,00h,00h,00h,00h,10h,0C0h,82h
        db 10h,06h,00h,00h,41h,50h,20h,94h,11h,04h,40h,14h,13h,08h,82h,41h
        db 84h,50h,51h,05h,07h,0F8h,82h,61h,88h,3Ch,00h,00h,0Ch,00h,00h,04h
        db 00h,00h,00h,00h,00h,20h,0C0h,82h,08h,0Ch,00h,00h,41h,22h,20h,0A6h
        db 21h,04h,41h,0Ch,11h,06h,86h,43h,84h,30h,41h,05h,00h,04h,83h,0C1h
        db 48h,07h,80h,00h,38h,00h,00h,00h,00h,00h,00h,00h,00h,20h,80h,82h
        db 0Ch,08h,3Fh,0E0h,41h,40h,60h,88h,51h,04h,41h,0Ch,11h,05h,04h,43h
        db 82h,50h,50h,87h,00h,04h,80h,03h,64h,00h,60h,00h,70h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,80h,82h,08h,08h,40h,20h,41h,00h,0A0h,88h
        db 81h,04h,0C1h,84h,10h,85h,04h,82h,0C2h,90h,40h,87h,00h,04h,80h,06h
        db 7Eh,00h,20h,01h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,20h,80h,82h
        db 18h,04h,40h,20h,41h,05h,20h,8Dh,01h,05h,41h,84h,11h,83h,0Dh,87h
        db 0C3h,10h,41h,07h,07h,0FCh,80h,02h,1Fh,0C0h,10h,17h,80h,00h,00h,00h
        db 00h,00h,00h,00h,00h,10h,0C0h,82h,10h,06h,40h,20h,41h,42h,20h,8Ah
        db 23h,04h,41h,40h,12h,82h,09h,80h,01h,10h,43h,05h,04h,00h,83h,83h
        db 0Fh,0FCh,10h,1Fh,00h,00h,00h,00h,00h,00h,00h,00h,00h,10h,41h,06h
        db 20h,82h,40h,20h,41h,04h,20h,94h,05h,04h,41h,40h,15h,42h,09h,00h
        db 01h,10h,45h,05h,04h,00h,82h,41h,0Fh,0F6h,11h,0FCh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,10h,63h,06h,61h,0C1h,3Fh,0E0h,41h,08h,20h,98h
        db 09h,04h,41h,20h,10h,40h,19h,00h,00h,90h,4Eh,0Dh,04h,00h,82h,60h
        db 8Bh,0FEh,17h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,1Eh,0Ch
        db 41h,0C1h,80h,07h,0C1h,0F3h,0E0h,0F0h,51h,04h,41h,20h,10h,60h,12h,0Fh
        db 0E0h,90h,78h,09h,07h,0FCh,82h,20h,88h,0FCh,16h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0Ch,00h,08h,83h,20h,80h,04h,00h,12h,00h,08h
        db 23h,04h,41h,30h,12h,20h,32h,08h,10h,0B0h,00h,19h,00h,04h,82h,30h
        db 48h,00h,30h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,00h,39h
        db 06h,10h,40h,04h,00h,12h,00h,08h,41h,04h,41h,58h,10h,60h,22h,18h
        db 50h,50h,00h,71h,00h,04h,82h,10h,48h,00h,60h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,80h,61h,04h,18h,60h,04h,00h,12h,00h,08h
        db 81h,04h,0C1h,08h,10h,90h,24h,10h,90h,50h,01h,0E5h,00h,04h,82h,18h
        db 2Eh,00h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,78h,21h
        db 0FCh,0Fh,0E0h,07h,0FFh,0F3h,0FFh,0F9h,05h,0FDh,3Fh,07h,0F5h,1Fh,0E7h,0F1h
        db 0Fh,0CFh,0FFh,04h,0FFh,0FCh,7Eh,0Fh,0E1h,0FFh,80h,00h,00h,00h,00h,00h
        db 00h,40h,00h,00h,00h,00h,04h,10h,00h,00h,00h,00h,00h,02h,00h,02h
        db 02h,00h,00h,22h,02h,20h,02h,02h,00h,00h,00h,22h,00h,00h,00h,00h
        db 00h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,18h
        db 00h,00h,00h,00h,24h,05h,04h,25h,04h,05h,04h,05h,04h,05h,04h,05h
        db 06h,05h,04h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,03h,08h,00h,00h,00h,00h,28h,08h,08h,48h
        db 08h,08h,08h,08h,08h,08h,08h,08h,09h,08h,08h,02h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,0F8h
        db 00h,00h,00h,00h,50h,50h,10h,50h,10h,50h,10h,50h,10h,50h,10h,50h
        db 11h,50h,10h,51h,00h,20h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,22h,20h,62h
        db 20h,22h,20h,22h,20h,22h,20h,22h,21h,22h,20h,21h,00h,00h,00h,00h
        db 00h,10h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h
        db 00h,00h,00h,00h,91h,40h,50h,40h,50h,40h,50h,40h,50h,40h,50h,40h
        db 51h,40h,50h,40h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,80h,80h,0C0h
        db 80h,80h,80h,80h,80h,80h,80h,80h,81h,80h,80h,80h,80h,00h,00h,00h
        db 00h,00h,00h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,81h,05h,01h,85h,01h,05h,01h,45h,01h,05h,01h,05h
        db 01h,85h,01h,04h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,22h,02h,22h,82h
        db 22h,02h,0E2h,42h,22h,02h,22h,02h,22h,82h,22h,00h,40h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,00h,01h,05h,04h,05h,84h,05h,04h,05h,44h,05h,04h,05h,04h
        db 05h,84h,05h,04h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,90h,00h,01h,08h,08h,68h,88h
        db 08h,08h,88h,48h,08h,08h,08h,08h,0E8h,88h,08h,08h,40h,90h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,60h,00h,02h,50h,10h,0F1h,10h,50h,10h,50h,50h,50h,10h,50h,11h
        db 0D8h,50h,50h,10h,20h,60h,00h,00h,00h,00h,00h,00h,08h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,01h,0F8h,00h,02h,22h,21h,0FBh,20h
        db 22h,20h,22h,40h,22h,20h,22h,23h,0BEh,60h,22h,20h,21h,0F8h,00h,00h
        db 08h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 03h,6Ch,00h,04h,40h,53h,6Dh,50h,40h,58h,40h,50h,40h,50h,40h,53h
        db 68h,50h,40h,50h,13h,6Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,08h,00h,08h,00h,00h,03h,0FCh,10h,04h,80h,83h,0FDh,80h
        db 80h,80h,80h,0C0h,80h,80h,80h,82h,0F4h,0C0h,80h,80h,13h,0FCh,40h,18h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,00h,08h,00h,08h,00h,08h
        db 02h,0F4h,00h,05h,05h,01h,97h,01h,05h,01h,05h,41h,05h,09h,05h,01h
        db 85h,21h,05h,01h,12h,0F4h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,00h,1Ch,00h,1Ch,00h,08h,02h,9Ch,00h,08h,02h,23h,6Ah,22h
        db 02h,22h,02h,42h,02h,2Ah,02h,23h,4Ah,26h,02h,22h,02h,94h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,1Ch,00h,1Ch,00h,1Ch,00h,1Ch
        db 01h,08h,00h,09h,00h,0Fh,06h,05h,04h,05h,00h,45h,04h,1Dh,04h,07h
        db 94h,25h,04h,05h,01h,08h,00h,08h,00h,00h,00h,00h,00h,00h,00h,08h
        db 00h,1Ch,00h,1Ch,00h,1Ch,00h,1Ch,01h,1Ch,00h,08h,00h,08h,00h,00h
        db 00h,00h,00h,40h,00h,1Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h
        db 00h,00h,00h,08h,00h,00h,00h,08h,00h,1Ch,00h,1Ch,00h,1Ch,00h,1Ch
        db 00h,1Ch,00h,1Ch,00h,1Ch,00h,00h,00h,00h,00h,40h,00h,3Ch,00h,00h
        db 00h,00h,00h,08h,00h,00h,00h,1Ch,00h,08h,00h,08h,00h,00h,00h,1Ch
        db 00h,1Ch,00h,3Eh,00h,3Eh,00h,1Ch,00h,1Ch,10h,1Ch,00h,1Ch,00h,08h
        db 00h,00h,00h,40h,00h,1Ch,00h,08h,00h,08h,00h,08h,00h,00h,00h,1Ch
        db 00h,08h,00h,1Ch,00h,08h,00h,1Ch,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh
        db 00h,3Eh,00h,1Ch,00h,1Ch,00h,08h,00h,01h,00h,48h,00h,3Eh,00h,08h
        db 00h,08h,00h,1Ch,00h,08h,00h,1Ch,00h,1Ch,00h,1Ch,00h,08h,00h,1Ch
        db 00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,1Ch
        db 00h,08h,00h,08h,00h,3Eh,00h,1Ch,00h,1Ch,00h,1Ch,00h,08h,00h,3Eh
        db 00h,1Ch,01h,1Ch,80h,1Ch,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh
        db 00h,3Eh,00h,3Eh,00h,3Eh,00h,1Ch,00h,1Ch,00h,1Ch,00h,3Eh,00h,1Ch
        db 00h,1Ch,00h,3Eh,0C0h,1Ch,00h,3Eh,00h,3Eh,00h,3Eh,00h,1Ch,00h,3Eh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh
        db 00h,1Ch,00h,1Ch,00h,7Fh,00h,3Eh,00h,3Eh,00h,3Eh,00h,1Ch,00h,3Eh
        db 00h,3Eh,00h,3Eh,00h,3Eh,00h,3Eh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,3Eh,00h,3Eh,00h,3Eh,00h,7Fh,00h,3Eh
        db 00h,3Eh,00h,3Eh,00h,3Eh,00h,7Fh,00h,3Eh,00h,7Fh,00h,3Eh,00h,7Fh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh
        db 00h,3Eh,01h,0FEh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,3Eh,00h,7Fh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,03h,0FFh,00h,7Fh,00h,7Fh
        db 00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh,00h,7Fh
        db 00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,80h,0FFh,00h,0FFh,00h,0FFh
        db 00h,7Fh,03h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,7Fh,00h,0FFh
        db 00h,0FFh,80h,0FFh,80h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh
        db 00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,03h,0FDh,00h,0FFh,00h,0FFh
        db 00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h,0FFh
        db 80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,40h,80h,00h,80h,00h
        db 80h,00h,82h,0F4h,00h,00h,80h,00h,80h,00h,84h,00h,80h,00h,80h,00h
        db 80h,00h,80h,00h,80h,00h,80h,00h,00h,40h,00h,41h,00h,40h,00h,41h
        db 00h,40h,00h,41h,00h,40h,00h,41h,00h,40h,00h,00h,00h,40h,00h,41h
        db 00h,40h,00h,41h,00h,40h,00h,41h,00h,40h,00h,41h,00h,40h,00h,41h
        db 20h,00h,20h,02h,20h,00h,20h,02h,20h,00h,20h,02h,20h,00h,20h,02h
        db 20h,00h,00h,02h,20h,00h,20h,02h,20h,00h,20h,02h,20h,00h,20h,02h
        db 20h,00h,20h,02h,20h,00h,20h,02h,00h,10h,00h,14h,00h,10h,60h,14h
        db 00h,10h,00h,14h,00h,10h,00h,16h,00h,10h,00h,04h,00h,10h,00h,14h
        db 00h,10h,00h,14h,00h,10h,00h,14h,00h,10h,00h,14h,00h,10h,00h,14h
        db 08h,00h,08h,08h,08h,00h,08h,08h,08h,00h,08h,08h,08h,00h,08h,08h
        db 08h,00h,08h,08h,08h,00h,08h,08h,08h,00h,08h,08h,08h,00h,08h,08h
        db 08h,00h,08h,08h,08h,00h,08h,08h,00h,04h,00h,14h,00h,04h,00h,14h
        db 00h,04h,00h,14h,00h,04h,00h,14h,00h,04h,20h,14h,00h,04h,00h,14h
        db 00h,04h,00h,14h,00h,04h,00h,14h,00h,04h,00h,14h,00h,04h,00h,14h
        db 02h,00h,02h,20h,02h,00h,02h,20h,02h,00h,02h,20h,02h,00h,02h,20h
        db 02h,00h,02h,20h,02h,00h,02h,20h,02h,00h,02h,20h,02h,00h,02h,20h
        db 02h,00h,02h,20h,02h,00h,02h,20h,00h,01h,00h,41h,00h,01h,00h,41h
        db 00h,01h,00h,41h,00h,01h,00h,41h,00h,01h,00h,41h,00h,01h,00h,41h
        db 00h,01h,00h,41h,00h,01h,00h,41h,00h,01h,00h,41h,00h,01h,00h,41h
        db 00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h
        db 00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h
        db 00h,80h,00h,80h,00h,80h,00h,80h,40h,00h,41h,00h,40h,00h,41h,00h
        db 40h,03h,0CFh,77h,64h,0E0h,0E3h,39h,0F9h,00h,4Fh,1Eh,0F2h,1Eh,71h,0F2h
        db 0C3h,18h,79h,0C7h,0E9h,0E4h,0C1h,00h,40h,00h,41h,00h,40h,00h,41h,00h
        db 00h,20h,02h,20h,00h,20h,02h,20h,00h,22h,4Ah,64h,34h,0B0h,87h,2Ch
        db 49h,26h,0Ah,30h,92h,32h,5Ah,0B3h,81h,28h,23h,24h,89h,26h,82h,20h
        db 00h,20h,02h,20h,00h,20h,02h,20h,10h,00h,14h,00h,10h,00h,14h,00h
        db 10h,02h,5Eh,77h,34h,90h,0F5h,38h,5Fh,06h,1Fh,0F1h,9Ah,33h,75h,99h
        db 0B9h,08h,3Dh,24h,9Bh,36h,94h,00h,10h,00h,14h,00h,10h,00h,14h,00h
        db 00h,08h,08h,08h,00h,08h,08h,08h,00h,0Ah,48h,4Ch,2Ch,98h,8Fh,0ACh
        db 49h,08h,1Ah,18h,92h,1Ah,58h,9Bh,81h,08h,29h,2Ch,89h,2Dh,88h,08h
        db 00h,08h,08h,08h,00h,08h,08h,08h,04h,00h,14h,00h,04h,00h,14h,00h
        db 04h,03h,9Eh,7Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0E5h,94h,00h,04h,00h,14h,00h,04h,00h,14h,00h
        db 00h,02h,20h,02h,00h,02h,20h,02h,00h,02h,20h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,02h,20h,02h
        db 00h,02h,20h,02h,00h,02h,20h,02h,01h,00h,41h,00h,01h,00h,41h,00h
        db 01h,00h,41h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,00h,41h,00h,01h,00h,41h,00h,01h,00h,41h,00h
        db 80h,00h,80h,00h,80h,00h,80h,00h,80h,00h,80h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,80h,00h
        db 80h,00h,80h,00h,80h,00h,80h,00h,00h,41h,00h,40h,00h,41h,00h,40h
        db 00h,41h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,41h,00h,40h,00h,41h,00h,40h,00h,41h,00h,40h
        db 20h,02h,20h,00h,20h,02h,20h,00h,20h,02h,20h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,02h,20h,00h
        db 20h,02h,20h,00h,20h,02h,20h,00h,00h,14h,00h,10h,00h,14h,00h,10h
        db 00h,14h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,14h,00h,10h,00h,14h,00h,10h,00h,14h,00h,10h
        db 08h,08h,08h,00h,08h,08h,08h,00h,08h,08h,08h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,08h,08h,00h
        db 08h,08h,08h,00h,08h,08h,08h,00h,00h,14h,00h,04h,00h,14h,00h,04h
        db 00h,14h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,14h,00h,04h,00h,14h,00h,04h,00h,14h,00h,04h
        db 02h,20h,02h,00h,02h,20h,02h,00h,02h,20h,02h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,20h,02h,00h
        db 02h,20h,02h,00h,02h,20h,02h,00h,00h,41h,00h,01h,00h,41h,00h,01h
        db 00h,41h,00h,7Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,41h,00h,01h,00h,41h,00h,01h,00h,41h,00h,01h

splash_red:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,01h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,80h,00h,00h,00h,00h,02h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0F0h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0FEh,00h,00h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FEh,00h,00h,00h,00h,00h,00h,00h,38h,01h,0C0h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,80h,0Ch,00h,00h,00h,00h
        db 01h,0C0h,00h,38h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,03h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0E0h,00h,00h,00h,00h,00h,06h,00h,00h,06h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 08h,00h,00h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,10h,00h,00h,00h,80h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 60h,00h,00h,00h,60h,00h,00h,00h,00h,00h,00h,3Fh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,80h,00h,00h,00h,10h,00h,00h,00h
        db 00h,00h,00h,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h
        db 00h,00h,00h,00h,08h,00h,00h,00h,00h,01h,01h,40h,0A0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h,00h,08h,00h,00h,00h
        db 00h,00h,03h,80h,70h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h
        db 00h,00h,00h,00h,04h,00h,00h,00h,00h,00h,05h,00h,28h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,00h,00h,00h,00h,02h,00h,00h,00h
        db 00h,00h,06h,00h,18h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h
        db 00h,00h,00h,00h,01h,00h,00h,00h,00h,00h,0Ch,00h,0Ch,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h
        db 00h,00h,0Ch,00h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,80h,00h,00h,00h,00h,08h,00h,0Ch,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,00h,00h
        db 00h,00h,08h,00h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,80h,00h,02h,00h,00h,08h,00h,0Ch,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h
        db 00h,00h,08h,00h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,40h,00h,00h,00h,00h,04h,00h,18h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h
        db 00h,08h,04h,00h,08h,00h,00h,00h,00h,03h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,80h,00h,00h,00h,20h,00h,00h,00h,00h,02h,00h,10h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h
        db 00h,00h,01h,00h,20h,00h,00h,00h,00h,00h,00h,00h,07h,0E0h,7Eh,07h
        db 0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,00h,00h,00h,00h,00h,0C0h,0C0h,00h,00h,00h
        db 00h,00h,00h,00h,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh
        db 07h,0E0h,7Eh,07h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h
        db 00h,00h,00h,3Fh,00h,00h,00h,00h,00h,00h,00h,00h,07h,0E0h,7Eh,07h
        db 0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh
        db 07h,0E0h,7Eh,07h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,10h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,08h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,7Fh,01h,0F8h,0Fh,0C0h,00h,0FEh,00h,7Fh,00h
        db 00h,0FCh,3Fh,07h,0EFh,0E0h,1Fh,8Fh,0E0h,0Fh,0FEh,00h,0FFh,0FCh,7Fh,0F0h
        db 00h,0FFh,00h,00h,10h,00h,00h,00h,00h,00h,80h,00h,00h,01h,0FFh,0E1h
        db 0FCh,1Fh,0C0h,07h,0FFh,03h,0FFh,80h,01h,0FCh,7Fh,87h,0FFh,0E0h,3Fh,8Fh
        db 0F0h,1Fh,0FFh,0C1h,0FFh,0FCh,0FFh,0FCh,03h,0FFh,0E0h,00h,00h,00h,00h,00h
        db 00h,10h,00h,00h,00h,07h,0FFh,0F0h,0FEh,3Fh,0C0h,87h,0FFh,03h,0FFh,80h
        db 01h,0FCh,7Fh,87h,0F7h,0E0h,3Fh,9Fh,0F0h,1Fh,0FFh,0E1h,0FFh,0FCh,0FFh,0FEh
        db 07h,0FFh,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0FFh,0F8h
        db 0FFh,3Fh,0E0h,07h,0FFh,83h,0FFh,0C0h,01h,0FEh,7Fh,0C7h,0FFh,0F0h,3Fh,0DFh
        db 0F8h,1Fh,0FFh,0F1h,0FFh,0FEh,0FFh,0FFh,0Fh,0FFh,0E0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,18h,00h,0Fh,0FFh,0FCh,7Fh,7Fh,0C0h,07h,0FFh,83h,0FFh,0C0h
        db 01h,0FEh,7Fh,0E7h,0FFh,0F0h,7Fh,0FFh,0F8h,1Fh,0FFh,0F9h,0FFh,0FEh,0FFh,0FFh
        db 0Fh,0FFh,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,1Fh,0FFh,0FCh
        db 3Fh,0FFh,0C0h,07h,0FFh,83h,0FFh,0C0h,01h,0FEh,7Fh,0E7h,0FBh,0F8h,7Fh,0BFh
        db 0FCh,1Fh,0FFh,0FDh,0FFh,0FEh,0FFh,0FFh,8Fh,0FFh,0F0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,1Fh,0F9h,0FEh,3Fh,0FFh,80h,00h,0FFh,80h,7Fh,0C0h
        db 01h,0FEh,7Fh,0F7h,0FBh,0F8h,0FFh,0BFh,0FCh,1Fh,0E3h,0FDh,0FEh,00h,0FFh,3Fh
        db 8Fh,0F0h,0F0h,08h,00h,00h,00h,00h,00h,00h,00h,00h,00h,1Fh,0E0h,0FEh
        db 1Fh,0FFh,00h,00h,7Fh,80h,3Fh,0C0h,01h,0FEh,7Fh,0F7h,0FBh,0FCh,0FFh,0FFh
        db 0FCh,1Fh,0E1h,0FDh,0FFh,0F8h,0FFh,7Fh,0CFh,0FCh,10h,00h,00h,00h,00h,04h
        db 00h,00h,00h,00h,00h,3Fh,0E0h,0FEh,0Fh,0FFh,00h,00h,7Fh,80h,3Fh,0C0h
        db 01h,0FEh,7Fh,0FFh,0F9h,0FCh,0FFh,7Fh,0FEh,1Fh,0E1h,0FFh,0FFh,0FCh,0FFh,0FFh
        db 8Fh,0FFh,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0C0h,0FFh
        db 0Fh,0FEh,3Fh,0E0h,7Fh,80h,3Fh,0C0h,01h,0FEh,7Fh,0FFh,0F9h,0FDh,0FFh,7Fh
        db 0FEh,1Fh,0E0h,0FFh,0FFh,0FCh,0FFh,0FFh,87h,0FFh,0E0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,3Fh,0C0h,0FFh,0Fh,0FCh,7Fh,0E0h,7Fh,80h,3Fh,0C0h
        db 01h,0FEh,7Fh,0FFh,0F8h,0FFh,0FEh,0FFh,0FEh,1Fh,0E0h,0FFh,0FFh,0FEh,0FFh,0FFh
        db 87h,0FFh,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0C0h,0FFh
        db 1Fh,0FCh,7Fh,0E0h,7Fh,80h,3Fh,0C0h,01h,0FEh,7Fh,0FFh,0F8h,0FFh,0FEh,0FFh
        db 0FFh,1Fh,0E1h,0FFh,0FFh,0FEh,0FFh,0FFh,01h,0FFh,0F0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,1Fh,0C0h,0FFh,1Fh,0FEh,7Fh,0F0h,7Fh,0C0h,3Fh,0C0h
        db 01h,0FEh,7Fh,0FFh,0F8h,0FFh,0FFh,0FFh,0FFh,1Fh,0E1h,0FFh,0FFh,0FEh,0FFh,0FFh
        db 00h,7Fh,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,1Fh,0C1h,0FFh
        db 3Fh,0FEh,7Fh,0F0h,7Fh,80h,3Fh,0C0h,01h,0FEh,7Fh,0FFh,0F8h,7Fh,0FDh,0FFh
        db 0FFh,9Fh,0E1h,0FFh,0FEh,00h,0FFh,0FFh,0Ch,0Fh,0F8h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,1Fh,0E3h,0FFh,7Fh,0FFh,3Fh,0F0h,7Fh,80h,3Fh,0C0h
        db 01h,0FEh,7Fh,0BFh,0F8h,7Fh,0FDh,0FFh,0FFh,9Fh,0E7h,0FFh,0FEh,00h,0FFh,7Fh
        db 8Fh,87h,0F8h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0FFh,0FEh
        db 7Fh,0FFh,8Fh,0F7h,0FFh,0E3h,0FFh,0F0h,01h,0FEh,7Fh,0BFh,0F8h,7Fh,0FFh,0FFh
        db 0FFh,9Fh,0FFh,0FFh,0FFh,0FCh,0FFh,3Fh,8Fh,0FFh,0F8h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0Fh,0FFh,0FEh,0FFh,0FFh,80h,07h,0FFh,0F3h,0FFh,0F8h
        db 01h,0FEh,7Fh,9Fh,0F8h,3Fh,0FBh,0FFh,0FFh,0DFh,0FFh,0FDh,0FFh,0FCh,0FFh,3Fh
        db 0CFh,0FFh,0F8h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0FFh,0FDh
        db 0FFh,9Fh,0C0h,07h,0FFh,0F3h,0FFh,0F8h,01h,0FEh,7Fh,9Fh,0F8h,3Fh,0FBh,0FCh
        db 1Fh,0DFh,0FFh,0FDh,0FFh,0FCh,0FFh,1Fh,0CFh,0FFh,0F8h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,0FFh,0FDh,0FFh,1Fh,0E0h,07h,0FFh,0FBh,0FFh,0FCh
        db 01h,0FEh,7Fh,8Fh,0F8h,1Fh,0F7h,0FCh,1Fh,0DFh,0FFh,0F9h,0FFh,0FEh,0FFh,1Fh
        db 0EFh,0FFh,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0F1h
        db 0FEh,0Fh,0E0h,07h,0FFh,0FBh,0FFh,0FCh,00h,0FEh,3Fh,87h,0F8h,1Fh,0F7h,0F8h
        db 0Fh,0EFh,0FFh,0E0h,0FFh,0FEh,7Fh,0Fh,0E1h,0FFh,0E0h,00h,00h,00h,00h,00h
        db 00h,40h,00h,00h,00h,00h,1Fh,0F0h,3Eh,01h,0E0h,00h,0FFh,0F8h,7Fh,0FCh
        db 00h,3Eh,0Fh,81h,0F8h,03h,0F0h,0F8h,03h,0E3h,0FFh,80h,3Fh,0FEh,1Fh,01h
        db 0F0h,7Fh,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0F8h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,03h,0F8h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,0FCh
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,20h,80h,00h,00h,00h,00h,30h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,3Ch,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,10h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h
        db 00h,00h,00h,00h,01h,20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,0C0h,60h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,10h,00h,00h,00h,00h,10h,00h,00h,02h,00h,60h,00h
        db 00h,00h,00h,60h,00h,00h,00h,00h,0F0h,00h,00h,00h,00h,10h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h,00h
        db 00h,20h,00h,00h,00h,00h,0F0h,00h,00h,00h,00h,60h,00h,00h,00h,01h
        db 0F8h,00h,00h,00h,00h,20h,00h,00h,00h,00h,20h,00h,08h,00h,00h,00h
        db 00h,00h,00h,00h,40h,00h,00h,00h,00h,40h,00h,00h,00h,01h,0F8h,00h
        db 00h,00h,00h,60h,00h,00h,00h,03h,0FCh,00h,00h,00h,00h,40h,00h,00h
        db 08h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h,00h,00h,00h
        db 00h,04h,00h,00h,00h,03h,6Ch,00h,00h,08h,00h,60h,00h,00h,00h,03h
        db 6Ch,00h,00h,00h,00h,04h,00h,00h,00h,00h,04h,00h,00h,00h,08h,00h
        db 00h,00h,00h,09h,08h,08h,00h,00h,01h,08h,10h,00h,00h,03h,0FCh,00h
        db 00h,00h,08h,60h,00h,00h,00h,03h,0FCh,00h,00h,00h,01h,08h,40h,00h
        db 00h,01h,08h,00h,00h,00h,08h,00h,08h,08h,08h,08h,10h,08h,00h,08h
        db 02h,10h,00h,00h,08h,00h,90h,00h,00h,00h,08h,60h,00h,08h,00h,00h
        db 90h,00h,00h,00h,02h,10h,00h,00h,08h,00h,10h,00h,00h,00h,08h,00h
        db 08h,08h,08h,1Ch,20h,1Ch,00h,08h,08h,08h,00h,00h,08h,01h,68h,00h
        db 00h,00h,1Ch,60h,08h,08h,08h,01h,68h,00h,00h,00h,08h,00h,00h,00h
        db 08h,00h,20h,00h,00h,00h,1Ch,00h,1Ch,1Ch,1Ch,1Ch,00h,1Ch,08h,1Ch
        db 08h,08h,00h,08h,1Ch,0Ah,04h,00h,00h,00h,1Ch,60h,08h,1Ch,08h,02h
        db 9Ch,00h,00h,00h,08h,00h,00h,08h,1Ch,00h,00h,00h,00h,00h,1Ch,08h
        db 1Ch,1Ch,1Ch,1Ch,00h,1Ch,08h,1Ch,1Dh,1Ch,00h,08h,1Ch,08h,00h,00h
        db 00h,00h,1Ch,60h,1Ch,1Ch,1Ch,00h,08h,00h,00h,00h,1Ch,00h,08h,08h
        db 1Ch,00h,00h,08h,00h,00h,1Ch,08h,1Ch,1Ch,1Ch,1Ch,00h,1Ch,1Ch,1Ch
        db 1Ch,1Ch,00h,1Ch,1Ch,1Ch,08h,00h,08h,00h,1Ch,60h,1Ch,3Ch,1Ch,00h
        db 1Ch,00h,08h,08h,1Ch,00h,08h,1Ch,1Ch,08h,00h,08h,00h,00h,1Ch,1Ch
        db 1Ch,1Ch,1Ch,3Eh,08h,3Eh,1Ch,1Ch,1Ch,1Ch,10h,1Ch,1Ch,1Ch,08h,08h
        db 08h,00h,3Eh,60h,1Ch,1Ch,1Ch,08h,1Ch,08h,08h,08h,1Ch,00h,1Ch,1Ch
        db 1Ch,08h,00h,1Ch,00h,08h,3Eh,1Ch,3Eh,3Eh,3Eh,3Eh,08h,3Eh,1Ch,3Eh
        db 3Eh,3Eh,08h,1Ch,3Eh,1Ch,1Ch,08h,1Ch,00h,3Eh,68h,3Eh,3Eh,3Eh,08h
        db 1Ch,08h,1Ch,1Ch,3Eh,08h,1Ch,1Ch,3Eh,1Ch,00h,1Ch,08h,08h,3Eh,1Ch
        db 3Eh,3Eh,3Eh,3Eh,1Ch,3Eh,3Eh,3Eh,3Eh,3Eh,08h,3Eh,3Eh,3Eh,1Ch,1Ch
        db 1Ch,08h,3Eh,08h,3Eh,3Eh,3Eh,1Ch,3Eh,1Ch,1Ch,1Ch,3Eh,08h,1Ch,3Eh
        db 3Eh,1Ch,08h,1Ch,08h,1Ch,3Eh,3Eh,3Eh,3Eh,3Eh,3Eh,1Ch,3Eh,3Eh,3Eh
        db 3Eh,3Eh,1Ch,3Eh,3Eh,3Eh,3Eh,1Ch,3Eh,1Ch,3Eh,1Ch,3Eh,3Eh,3Eh,1Ch
        db 3Eh,1Ch,3Eh,3Eh,3Eh,1Ch,3Eh,3Eh,3Eh,3Eh,1Ch,3Eh,1Ch,1Ch,3Eh,3Eh
        db 7Fh,7Fh,7Fh,7Fh,3Eh,7Fh,3Eh,7Fh,3Eh,3Eh,1Ch,3Eh,7Fh,3Eh,3Eh,3Eh
        db 3Eh,1Ch,7Fh,1Ch,3Eh,7Fh,3Eh,3Eh,3Eh,3Eh,3Eh,3Eh,3Eh,1Ch,3Eh,3Eh
        db 7Fh,3Eh,1Ch,3Eh,1Ch,3Eh,7Fh,3Eh,7Fh,7Fh,7Fh,7Fh,3Eh,7Fh,7Fh,7Fh
        db 7Fh,7Fh,3Eh,7Fh,7Fh,7Fh,3Eh,3Eh,3Eh,3Eh,7Fh,3Eh,7Fh,7Fh,7Fh,3Eh
        db 7Fh,3Eh,3Eh,3Eh,7Fh,3Eh,7Fh,7Fh,7Fh,3Eh,3Eh,7Fh,3Eh,3Eh,7Fh,7Fh
        db 7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,3Eh,7Fh,7Fh,7Fh,7Fh,7Fh
        db 7Fh,3Eh,7Eh,0FEh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,3Eh,7Fh,7Fh
        db 7Fh,7Fh,3Eh,7Fh,3Eh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh
        db 7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Ch,0F7h,7Fh,7Fh,7Fh,7Fh
        db 7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FCh,03h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh,03h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h,00h,00h
        db 00h,00h,1Ch,03h,80h,00h,00h,00h,00h,00h,04h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h,01h
        db 00h,00h,00h,01h,00h,00h,00h,01h,00h,00h,3Ch,0F3h,0C0h,00h,00h,01h
        db 00h,00h,00h,01h,00h,00h,00h,01h,00h,00h,00h,01h,00h,00h,00h,01h
        db 00h,00h,00h,02h,00h,00h,00h,02h,00h,00h,00h,02h,00h,00h,00h,02h
        db 00h,00h,30h,0F2h,0C0h,00h,00h,02h,00h,00h,00h,02h,00h,00h,00h,02h
        db 00h,00h,00h,02h,00h,00h,00h,02h,00h,00h,00h,04h,00h,00h,00h,04h
        db 00h,00h,00h,04h,00h,00h,00h,06h,00h,00h,20h,0F4h,40h,00h,00h,04h
        db 00h,00h,00h,04h,00h,00h,00h,04h,00h,00h,00h,04h,00h,00h,00h,04h
        db 00h,00h,00h,08h,00h,00h,00h,08h,00h,00h,00h,08h,00h,00h,00h,08h
        db 00h,00h,00h,08h,00h,00h,00h,08h,00h,00h,00h,08h,00h,00h,00h,08h
        db 00h,00h,00h,08h,00h,00h,30h,08h,00h,00h,00h,10h,00h,00h,00h,10h
        db 00h,00h,00h,10h,00h,00h,00h,10h,00h,00h,00h,10h,00h,00h,00h,10h
        db 00h,00h,00h,10h,00h,00h,00h,10h,00h,00h,00h,10h,00h,00h,00h,10h
        db 00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,20h
        db 00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,20h
        db 00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,40h,00h,00h,00h,40h
        db 00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h
        db 00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h,01h,00h
        db 00h,03h,8Fh,77h,24h,0E0h,0E3h,39h,0F9h,00h,0Fh,1Eh,0F2h,1Eh,71h,0F2h
        db 0C3h,18h,39h,0C7h,0E9h,0E4h,81h,00h,00h,00h,01h,00h,00h,00h,01h,00h
        db 00h,00h,02h,00h,00h,00h,02h,00h,00h,02h,4Ah,44h,34h,90h,87h,2Ch
        db 49h,06h,0Ah,10h,92h,12h,5Ah,93h,81h,08h,23h,24h,89h,26h,82h,00h
        db 00h,00h,02h,00h,00h,00h,02h,00h,00h,00h,04h,00h,00h,00h,04h,00h
        db 00h,02h,4Eh,77h,34h,90h,0E5h,38h,4Fh,06h,0Fh,0F1h,9Ah,33h,75h,99h
        db 0B9h,08h,3Dh,24h,8Bh,36h,84h,00h,00h,00h,04h,00h,00h,00h,04h,00h
        db 00h,00h,08h,00h,00h,00h,08h,00h,00h,02h,48h,44h,2Ch,90h,8Fh,0ACh
        db 49h,00h,1Ah,10h,92h,12h,58h,93h,81h,08h,29h,24h,89h,25h,88h,00h
        db 00h,00h,08h,00h,00h,00h,08h,00h,00h,00h,10h,00h,00h,00h,10h,00h
        db 00h,03h,9Eh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0E5h,90h,00h,00h,00h,10h,00h,00h,00h,10h,00h
        db 00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h
        db 00h,00h,20h,00h,00h,00h,20h,00h,00h,00h,40h,00h,00h,00h,40h,00h
        db 00h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,0F3h,0E3h,0E3h,0C7h
        db 81h,0E3h,0E3h,07h,9Fh,0Fh,0E7h,80h,7Bh,0F9h,87h,0DFh,0C0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h,01h,00h,00h
        db 00h,01h,00h,01h,9Bh,63h,06h,4Ch,83h,23h,37h,8Ch,18h,03h,0Ch,0C0h
        db 0C8h,0C3h,0C6h,0C6h,00h,01h,00h,00h,00h,01h,00h,00h,00h,01h,00h,00h
        db 00h,02h,00h,00h,00h,02h,00h,00h,00h,02h,00h,01h,9Bh,33h,06h,0Ch
        db 03h,03h,35h,8Ch,18h,03h,0Ch,60h,0C0h,0C2h,0C6h,66h,00h,02h,00h,00h
        db 00h,02h,00h,00h,00h,02h,00h,00h,00h,04h,00h,00h,00h,04h,00h,00h
        db 00h,04h,00h,01h,9Bh,63h,0E7h,0CFh,83h,0E3h,3Ch,88h,1Fh,03h,08h,60h
        db 0F8h,0C6h,46h,0C6h,00h,04h,00h,00h,00h,04h,00h,00h,00h,04h,00h,00h
        db 00h,08h,00h,00h,00h,08h,00h,00h,00h,08h,00h,01h,0F3h,0E3h,00h,0C1h
        db 80h,63h,0EFh,0CCh,18h,03h,0Ch,60h,18h,0C7h,0E7h,0C6h,00h,08h,00h,00h
        db 00h,08h,00h,00h,00h,08h,00h,00h,00h,10h,00h,00h,00h,10h,00h,00h
        db 00h,10h,00h,01h,83h,63h,04h,0C9h,82h,63h,08h,0CCh,18h,03h,0Ch,0C0h
        db 98h,0C4h,66h,0C6h,00h,10h,00h,00h,00h,10h,00h,00h,00h,10h,00h,00h
        db 00h,20h,00h,00h,00h,20h,00h,00h,00h,20h,00h,01h,83h,33h,0E7h,0CFh
        db 83h,0E3h,18h,47h,9Fh,03h,07h,80h,0F8h,0CCh,26h,66h,00h,20h,00h,00h
        db 00h,20h,00h,00h,00h,20h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h
        db 00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h,00h,40h,00h,00h

splash_green:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0FEh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,06h,00h,00h,00h,00h,00h,00h,00h,00h
        db 30h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0FFh,0E0h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,38h
        db 00h,00h,00h,00h,00h,00h,00h,00h,0Eh,00h,00h,00h,00h,00h,00h,00h
        db 03h,0F8h,01h,0FCh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,01h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h
        db 01h,80h,00h,00h,00h,00h,00h,0Ch,0Fh,80h,00h,1Fh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,70h,00h,00h,00h,00h,00h,00h
        db 1Eh,07h,0FEh,07h,80h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,38h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,0Eh,00h,00h,00h,00h,00h,00h,78h,38h,01h,0C1h,0E0h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,80h,0Ch,00h,00h,00h,00h
        db 0E1h,0C0h,00h,38h,70h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,80h,00h,00h,00h,01h,0C6h,00h,00h,06h,38h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,00h,00h,03h
        db 08h,00h,00h,01h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,8Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,18h,00h,00h,00h,06h,10h,00h,00h,00h,86h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,30h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,00h,00h,00h,0Ch
        db 60h,00h,00h,00h,63h,00h,00h,20h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,01h,80h,00h,00h,18h,80h,00h,00h,00h,11h,80h,00h,00h
        db 00h,00h,00h,3Fh,00h,00h,00h,00h,00h,00h,00h,03h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,00h,39h
        db 00h,00h,00h,00h,09h,0C0h,00h,00h,00h,01h,00h,40h,80h,00h,00h,00h
        db 00h,00h,00h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,18h,00h,00h,31h,00h,00h,00h,00h,08h,0C0h,00h,00h
        db 00h,00h,01h,80h,60h,00h,00h,00h,00h,00h,00h,30h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,00h,00h,62h
        db 00h,00h,00h,00h,04h,60h,00h,00h,00h,00h,01h,00h,20h,00h,00h,00h
        db 00h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,80h,00h,0E4h,00h,00h,00h,00h,02h,70h,00h,00h
        db 00h,00h,02h,00h,10h,00h,00h,00h,00h,00h,03h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,0C8h
        db 00h,00h,00h,00h,01h,30h,00h,00h,00h,00h,04h,00h,08h,00h,00h,00h
        db 00h,00h,0Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,18h,01h,0C0h,00h,00h,00h,00h,01h,38h,00h,00h
        db 00h,00h,04h,00h,08h,00h,00h,00h,00h,00h,30h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,06h,01h,80h
        db 00h,00h,00h,00h,00h,98h,00h,00h,00h,00h,00h,00h,08h,00h,00h,00h
        db 00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,81h,80h,00h,00h,00h,00h,00h,98h,00h,00h
        db 00h,00h,00h,00h,08h,00h,00h,00h,00h,03h,00h,00h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,80h,00h,63h,00h
        db 00h,00h,00h,00h,00h,8Ch,00h,02h,00h,00h,00h,00h,08h,00h,00h,00h
        db 00h,00h,0C0h,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,80h,00h,0C3h,00h,00h,00h,00h,00h,00h,4Ch,00h,00h
        db 00h,00h,00h,00h,08h,00h,00h,00h,00h,00h,30h,00h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,80h,03h,03h,00h
        db 00h,00h,00h,00h,00h,4Ch,00h,00h,00h,00h,00h,00h,10h,00h,00h,00h
        db 00h,00h,0Ch,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,80h,0Ch,03h,00h,00h,00h,00h,00h,00h,4Ch,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,03h,00h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,80h,30h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,0C0h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,80h,0C0h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,30h,07h,0E0h,7Eh,07h
        db 0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E3h,00h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,0Ch,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh
        db 07h,0E0h,7Eh,07h,0ECh,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,07h,0E0h,7Eh,07h
        db 0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0F0h,00h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0C7h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh,07h,0E0h,7Eh
        db 07h,0E0h,7Eh,07h,0E0h,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,30h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,10h,20h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0Fh,0FFh,0FFh,0FFh,0BFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FEh
        db 0FFh,0FFh,0FFh,0FCh,00h,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,08h,08h
        db 08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,20h,00h,00h,00h,06h,00h
        db 00h,00h,00h,00h,00h,26h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,04h,10h,10h,10h,10h,10h,10h,10h,10h,10h,10h
        db 10h,10h,10h,00h,00h,00h,06h,00h,00h,00h,00h,00h,00h,26h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h,20h,20h
        db 20h,20h,20h,20h,20h,20h,20h,20h,20h,20h,10h,00h,00h,00h,03h,00h
        db 00h,00h,00h,00h,00h,4Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 40h,00h,00h,00h,00h,08h,40h,40h,40h,40h,40h,40h,40h,40h,40h,40h
        db 40h,40h,48h,00h,00h,00h,03h,00h,00h,00h,00h,00h,00h,4Ch,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,80h,80h
        db 80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,88h,00h,00h,00h,03h,00h
        db 00h,00h,00h,00h,00h,4Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,09h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h
        db 01h,01h,08h,00h,00h,00h,03h,00h,00h,00h,00h,00h,00h,8Ch,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,12h,02h,02h
        db 02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,04h,00h,00h,00h,01h,80h
        db 00h,00h,00h,00h,00h,98h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,04h,00h,14h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h
        db 04h,04h,04h,20h,00h,00h,01h,80h,00h,00h,00h,00h,00h,98h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,18h,08h,08h
        db 08h,08h,08h,08h,08h,28h,08h,08h,08h,08h,04h,00h,00h,00h,01h,0C0h
        db 00h,00h,00h,00h,00h,38h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,30h,10h,10h,10h,10h,10h,10h,10h,10h,10h,10h
        db 10h,10h,1Ah,00h,00h,00h,00h,0C0h,00h,00h,00h,00h,00h,30h,00h,00h
        db 00h,00h,00h,00h,00h,00h,7Fh,01h,0F8h,0Fh,0C0h,00h,0FEh,20h,7Fh,20h
        db 0A0h,0FCh,3Fh,27h,0EFh,0E0h,3Fh,0AFh,0E0h,2Fh,0FEh,00h,0FFh,0FCh,7Fh,0F0h
        db 00h,0FFh,00h,00h,10h,70h,00h,00h,00h,00h,80h,00h,00h,01h,0FFh,0E1h
        db 0FCh,1Fh,0C0h,07h,0FFh,43h,0FFh,0C0h,41h,0FCh,7Fh,0C7h,0FFh,0E0h,7Fh,0CFh
        db 0F0h,5Fh,0FFh,0C1h,0FFh,0FCh,0FFh,0FCh,03h,0FFh,0E0h,00h,00h,60h,00h,00h
        db 00h,10h,30h,00h,00h,07h,0FFh,0F0h,0FEh,3Fh,0C0h,87h,0FFh,43h,0FFh,80h
        db 81h,0FCh,0FFh,87h,0F7h,0E0h,0BFh,9Fh,0F0h,9Fh,0FFh,0E1h,0FFh,0FCh,0FFh,0FEh
        db 07h,0FFh,0E0h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,0Fh,0FFh,0F8h
        db 0FFh,3Fh,80h,07h,0FFh,43h,0FFh,81h,01h,0FDh,7Fh,0C7h,0F7h,0F1h,3Fh,1Fh
        db 0F1h,1Fh,0FFh,0F1h,0FFh,0FCh,0FFh,0FFh,0Fh,0FFh,0E0h,00h,01h,0C0h,00h,00h
        db 00h,00h,00h,00h,00h,0Fh,0FFh,0FCh,7Fh,7Fh,00h,07h,0FFh,03h,0FFh,82h
        db 03h,0FCh,7Fh,0E7h,0F7h,0F2h,7Fh,3Fh,0FAh,1Fh,0FFh,0F9h,0FFh,0FCh,0FFh,0FFh
        db 0Fh,0FFh,0E0h,00h,01h,80h,00h,00h,00h,00h,00h,00h,00h,1Fh,0E3h,0FCh
        db 3Fh,0FFh,00h,07h,7Fh,07h,0BFh,84h,05h,0FCh,7Fh,0E7h,0F7h,0FCh,7Fh,3Fh
        db 0FCh,1Fh,0C7h,0F9h,0FCh,00h,0FEh,7Fh,0Fh,0C1h,0E0h,00h,03h,00h,00h,00h
        db 00h,00h,00h,00h,80h,1Fh,0C1h,0FCh,3Fh,0FEh,00h,00h,7Fh,08h,3Fh,88h
        db 09h,0FCh,7Fh,0FFh,0F3h,0F8h,0FEh,3Fh,0FCh,1Fh,0C9h,0FDh,0FCh,00h,0FEh,3Fh
        db 0Fh,0C0h,60h,08h,06h,00h,00h,00h,00h,00h,00h,00h,00h,1Fh,80h,0FEh
        db 1Fh,0FCh,00h,00h,7Fh,10h,3Fh,90h,11h,0FCh,7Fh,0F7h,0F3h,0F8h,0FEh,7Fh
        db 0FCh,1Fh,0D1h,0FDh,0FFh,0F8h,0FEh,7Fh,4Fh,0FCh,00h,00h,0Ch,00h,00h,00h
        db 00h,00h,00h,00h,00h,3Fh,80h,0FEh,0Fh,0FCh,00h,00h,7Fh,20h,3Fh,0A0h
        db 21h,0FCh,7Fh,0FFh,0F1h,0FCh,0FCh,7Fh,0FCh,3Fh,0C1h,0FDh,0FFh,0FCh,0FFh,0FFh
        db 4Fh,0FFh,80h,00h,38h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,80h,0FEh
        db 0Fh,0F8h,3Fh,0E0h,7Fh,40h,7Fh,80h,41h,0FCh,7Fh,0FFh,0F1h,0FDh,0FCh,7Eh
        db 0FEh,5Fh,0C0h,0FDh,0FFh,0FCh,0FFh,0FEh,67h,0FFh,0E0h,00h,70h,00h,00h,00h
        db 00h,00h,00h,00h,00h,3Fh,80h,0FEh,0Fh,0F8h,7Fh,0E0h,7Fh,00h,0BFh,80h
        db 81h,0FCh,0FFh,0FFh,0F0h,0FDh,0FCh,0FEh,0FEh,9Fh,0C0h,0FDh,0FFh,0FCh,0FFh,0FCh
        db 7Fh,0FFh,0E0h,01h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,80h,0FEh
        db 1Fh,0FCh,7Fh,0E0h,7Fh,01h,3Fh,81h,01h,0FDh,7Fh,0FFh,0F1h,0FFh,0F9h,0FFh
        db 0FFh,1Fh,0C1h,0FDh,0FFh,0F8h,0FFh,0FEh,1Fh,0FFh,0F0h,07h,80h,00h,00h,00h
        db 00h,00h,00h,00h,00h,1Fh,80h,0FEh,1Fh,0FEh,7Fh,0E0h,7Fh,42h,3Fh,82h
        db 03h,0FCh,7Fh,7Fh,0F2h,0FFh,0F9h,0FFh,0FFh,1Fh,0C3h,0FDh,0FCh,00h,0FFh,0FFh
        db 0Fh,0BFh,0F0h,1Fh,00h,00h,00h,00h,00h,00h,00h,00h,00h,1Fh,0C1h,0FCh
        db 3Fh,0FEh,7Fh,0E0h,7Fh,04h,3Fh,84h,05h,0FCh,7Fh,7Fh,0F4h,7Fh,0F9h,0FFh
        db 0FFh,1Fh,0C5h,0FDh,0FCh,00h,0FEh,7Fh,0Fh,0F7h,0F1h,0FCh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,1Fh,0E3h,0FCh,7Fh,0FFh,3Fh,0E0h,7Fh,08h,3Fh,88h
        db 09h,0FCh,7Fh,3Fh,0F0h,7Fh,0F1h,0FFh,0FFh,9Fh,0CFh,0F9h,0FCh,00h,0FEh,7Fh
        db 8Fh,0FFh,0F7h,0E0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0FFh,0FCh
        db 7Fh,7Fh,80h,07h,0FFh,0F3h,0FFh,0F0h,11h,0FCh,7Fh,3Fh,0F0h,7Fh,0F3h,0FFh
        db 0FFh,9Fh,0FFh,0F9h,0FFh,0FCh,0FEh,3Fh,8Fh,0FFh,0F6h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,0Fh,0FFh,0F8h,0FEh,3Fh,80h,07h,0FFh,0F3h,0FFh,0F8h
        db 21h,0FCh,7Fh,3Fh,0F0h,3Fh,0E3h,0F8h,1Fh,0BFh,0FFh,0F1h,0FFh,0FCh,0FEh,3Fh
        db 0CFh,0FFh,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0FFh,0F1h
        db 0FEh,1Fh,0C0h,07h,0FFh,0F3h,0FFh,0F8h,41h,0FCh,7Fh,5Fh,0F0h,7Fh,0E3h,0F0h
        db 5Fh,0DFh,0FFh,0E1h,0FFh,0FCh,0FEh,1Fh,0CFh,0FFh,0E0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,0FFh,0E1h,0FCh,1Fh,0E0h,07h,0FFh,0F3h,0FFh,0F8h
        db 81h,0FCh,0FFh,0Fh,0F0h,9Fh,0E7h,0F0h,9Fh,0DFh,0FFh,0C5h,0FFh,0FCh,0FEh,1Fh
        db 0EFh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,7Fh,0E1h
        db 0F8h,0Fh,0E0h,07h,0FFh,0E3h,0FFh,0F1h,01h,0FDh,3Eh,07h,0E1h,1Fh,0C7h,0F1h
        db 0Fh,0CFh,0FEh,04h,0FFh,0FCh,7Eh,0Fh,0C1h,0FFh,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,07h,0F0h,00h,00h,00h,00h,00h,02h,00h,02h
        db 02h,00h,00h,02h,02h,00h,02h,02h,00h,00h,00h,02h,00h,00h,00h,00h
        db 00h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0F8h
        db 00h,00h,00h,00h,24h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h
        db 04h,04h,04h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,03h,0F8h,00h,00h,00h,00h,28h,08h,08h,08h
        db 08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,02h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,0F8h
        db 00h,00h,00h,00h,50h,10h,10h,10h,10h,10h,10h,10h,10h,10h,10h,10h
        db 10h,10h,10h,11h,00h,00h,00h,00h,00h,00h,00h,30h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,20h,20h,20h
        db 20h,20h,20h,20h,20h,20h,20h,20h,20h,20h,20h,21h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h
        db 00h,00h,00h,00h,80h,60h,40h,40h,40h,40h,40h,40h,40h,40h,40h,40h
        db 40h,40h,40h,40h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,80h,80h,80h
        db 80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,80h,00h,00h,00h
        db 00h,00h,00h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,81h,01h,01h,01h,01h,01h,01h,61h,01h,01h,01h,01h
        db 01h,01h,01h,00h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,02h,02h,02h,02h
        db 02h,02h,02h,62h,02h,02h,02h,02h,02h,02h,02h,00h,40h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,01h,04h,04h,04h,04h,04h,04h,04h,64h,04h,04h,04h,04h
        db 04h,04h,04h,04h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0F0h,00h,00h,00h,00h,90h,00h,01h,0Ah,08h,08h,08h
        db 08h,08h,88h,68h,08h,08h,08h,08h,18h,08h,08h,08h,40h,90h,00h,00h
        db 00h,00h,60h,00h,00h,00h,00h,00h,00h,00h,00h,01h,0F8h,00h,00h,00h
        db 00h,60h,00h,02h,10h,10h,20h,10h,10h,10h,10h,70h,10h,10h,10h,10h
        db 20h,10h,10h,10h,20h,60h,00h,00h,00h,00h,0F0h,00h,00h,00h,00h,00h
        db 00h,00h,00h,03h,0FCh,00h,00h,00h,01h,0F8h,00h,02h,20h,20h,40h,20h
        db 20h,20h,20h,60h,20h,20h,20h,20h,40h,20h,20h,20h,21h,0F8h,00h,00h
        db 08h,01h,0F8h,00h,00h,00h,00h,00h,00h,00h,00h,03h,6Ch,00h,00h,00h
        db 03h,6Ch,00h,04h,40h,40h,04h,40h,40h,48h,40h,60h,40h,40h,40h,40h
        db 04h,40h,40h,40h,13h,6Ch,00h,00h,00h,03h,6Ch,00h,00h,00h,08h,00h
        db 00h,00h,00h,03h,0FCh,00h,00h,00h,03h,0FCh,00h,04h,80h,81h,08h,80h
        db 80h,80h,80h,0E0h,80h,80h,80h,81h,08h,80h,80h,80h,13h,0FCh,00h,00h
        db 00h,03h,0FCh,00h,00h,00h,00h,00h,00h,00h,00h,00h,90h,00h,00h,00h
        db 02h,0F4h,00h,05h,01h,01h,11h,01h,01h,01h,01h,61h,01h,01h,01h,01h
        db 11h,01h,01h,01h,12h,0F4h,00h,00h,00h,00h,90h,00h,00h,00h,00h,00h
        db 00h,00h,00h,01h,68h,00h,00h,00h,02h,94h,00h,08h,02h,02h,22h,02h
        db 02h,02h,02h,62h,02h,02h,02h,02h,22h,02h,02h,02h,02h,94h,00h,00h
        db 00h,01h,68h,00h,00h,00h,00h,00h,00h,00h,00h,02h,94h,00h,00h,00h
        db 01h,00h,00h,00h,00h,04h,00h,04h,04h,04h,00h,64h,04h,00h,04h,04h
        db 00h,04h,04h,04h,01h,08h,00h,00h,00h,02h,04h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,60h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,20h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,60h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,01h,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0F8h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,03h,0FCh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0FCh,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h,00h,00h
        db 00h,00h,02h,0F4h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0F0h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,0F0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,60h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0F0h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,30h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,03h,8Eh,77h,24h,0E0h,0E3h,39h,0F9h,00h,0Eh,1Eh,0F2h,1Eh,70h,0F2h
        db 0C3h,18h,39h,0C7h,0E9h,0E4h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,48h,44h,34h,90h,87h,2Ch
        db 49h,06h,0Ah,10h,92h,12h,58h,93h,81h,08h,21h,24h,89h,26h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,02h,4Eh,77h,34h,90h,0E5h,38h,4Fh,06h,0Fh,0F1h,9Ah,33h,71h,99h
        db 0B9h,08h,39h,24h,8Bh,36h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,48h,44h,2Ch,90h,87h,0ACh
        db 49h,00h,1Ah,10h,92h,12h,58h,93h,81h,08h,21h,24h,89h,25h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,03h,8Eh,7Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0E5h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,40h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,40h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,41h,0F3h,0E3h,0E3h,0C7h
        db 81h,0E3h,0E3h,07h,9Fh,0Fh,0E7h,80h,7Bh,0F9h,87h,0DFh,0C1h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,41h,9Bh,63h,06h,4Ch,83h,23h,37h,8Ch,18h,03h,0Ch,0C0h
        db 0C8h,0C3h,0C6h,0C6h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,41h,9Bh,33h,06h,0Ch
        db 03h,03h,35h,8Ch,18h,03h,0Ch,60h,0C0h,0C2h,0C6h,66h,01h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,41h,9Bh,63h,0E7h,0CFh,83h,0E3h,3Ch,88h,1Fh,03h,08h,60h
        db 0F8h,0C6h,46h,0C6h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,41h,0F3h,0E3h,00h,0C1h
        db 80h,63h,0EFh,0CCh,18h,03h,0Ch,60h,18h,0C7h,0E7h,0C6h,01h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,41h,83h,63h,04h,0C9h,82h,63h,08h,0CCh,18h,03h,0Ch,0C0h
        db 98h,0C4h,66h,0C6h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,41h,83h,33h,0E7h,0CFh
        db 83h,0E3h,18h,47h,9Fh,03h,07h,80h,0F8h,0CCh,26h,66h,01h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,7Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ============================================================================
; 320x32 full-width round banners, native QX-11 planar format.
; ============================================================================

game_over_blue:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h,04h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,20h
        db 04h,40h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0F0h,01h,0FCh,03h,0F8h
        db 0Fh,0E1h,0FFh,0F8h,00h,03h,0F8h,3Fh,80h,7Eh,0FFh,0FCh,3Fh,0F8h,00h,00h
        db 00h,00h,00h,00h,00h,00h,02h,20h,04h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,70h,0Eh,01h,02h,04h,04h,10h,12h,00h,08h,00h,0Ch,07h,20h
        db 80h,83h,00h,04h,40h,06h,00h,00h,00h,00h,00h,00h,00h,00h,02h,20h
        db 04h,40h,00h,00h,00h,00h,00h,00h,00h,00h,80h,02h,02h,02h,04h,04h
        db 10h,12h,00h,08h,00h,30h,01h,90h,80h,83h,00h,04h,40h,01h,00h,00h
        db 00h,00h,00h,00h,00h,00h,02h,20h,04h,40h,00h,00h,00h,00h,00h,00h
        db 00h,01h,00h,02h,02h,03h,04h,06h,20h,1Ah,00h,0Ch,00h,60h,00h,50h
        db 40h,87h,00h,06h,40h,00h,80h,00h,00h,00h,00h,00h,00h,00h,02h,20h
        db 04h,40h,00h,00h,00h,00h,00h,00h,00h,02h,07h,0E3h,06h,01h,04h,02h
        db 20h,1Ah,0Fh,0FCh,00h,40h,0F0h,70h,41h,07h,07h,0FEh,41h,0E0h,80h,00h
        db 00h,00h,00h,00h,00h,00h,02h,20h,04h,40h,00h,00h,00h,00h,00h,00h
        db 00h,04h,0Fh,0FBh,04h,01h,84h,03h,60h,1Ah,0Fh,0FCh,00h,83h,0F8h,28h
        db 61h,07h,07h,0FEh,41h,0F0h,0C0h,00h,00h,00h,00h,00h,00h,00h,02h,20h
        db 04h,00h,00h,00h,00h,00h,00h,00h,00h,04h,1Eh,0Fh,04h,20h,84h,01h
        db 40h,1Ah,0Ch,00h,00h,83h,0C8h,38h,23h,0Fh,06h,00h,41h,90h,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,00h,00h
        db 00h,04h,3Ch,01h,08h,30h,84h,11h,0C4h,1Ah,0Fh,0F0h,00h,87h,04h,1Ch
        db 32h,0Fh,07h,0F8h,41h,0B0h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,00h,00h,00h,08h,39h,0FEh,08h,70h,0C4h,10h
        db 84h,1Ah,00h,08h,01h,07h,04h,1Ch,12h,1Dh,00h,04h,41h,0E0h,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,32h,01h,08h,70h,44h,10h,8Ch,1Ah,00h,08h,01h,06h,04h,1Ch
        db 14h,1Dh,00h,04h,40h,01h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,00h,00h,00h,08h,32h,01h,10h,78h,44h,18h
        db 0Ch,1Ah,00h,0Ch,01h,06h,04h,1Ah,1Ch,19h,00h,06h,40h,03h,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,32h,01h,90h,0F8h,64h,18h,1Ch,1Ah,0Fh,0FCh,01h,06h,04h,1Ah
        db 0Ch,39h,07h,0FEh,40h,01h,80h,00h,00h,00h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,00h,00h,00h,04h,31h,0C1h,0B0h,00h,24h,1Ch
        db 1Ch,1Ah,0Fh,0FCh,00h,86h,04h,1Ah,08h,39h,07h,0FEh,41h,0C1h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,00h,00h
        db 00h,04h,10h,41h,0A0h,00h,34h,1Ch,1Ch,1Ah,0Ch,00h,00h,82h,08h,39h
        db 08h,31h,06h,00h,41h,0E0h,80h,00h,00h,00h,00h,00h,00h,00h,00h,20h
        db 04h,00h,80h,00h,00h,00h,00h,00h,00h,04h,08h,41h,0A0h,00h,14h,1Ah
        db 3Ch,1Ah,0Ch,00h,00h,83h,18h,39h,00h,71h,06h,00h,41h,0B0h,40h,00h
        db 00h,00h,00h,00h,00h,01h,00h,20h,04h,00h,80h,00h,00h,00h,00h,00h
        db 00h,02h,07h,0C1h,0C1h,0FCh,14h,1Bh,0FCh,1Ah,0Fh,0F8h,00h,40h,0F0h,71h
        db 80h,71h,07h,0FCh,41h,90h,40h,00h,00h,00h,00h,00h,00h,01h,00h,20h
        db 04h,00h,80h,00h,00h,00h,00h,00h,00h,01h,00h,01h,0C1h,0FEh,1Ch,18h
        db 74h,1Ah,00h,08h,00h,60h,00h,70h,80h,0E1h,00h,04h,41h,98h,20h,00h
        db 00h,00h,00h,00h,00h,01h,00h,20h,04h,00h,80h,00h,00h,00h,00h,00h
        db 00h,00h,80h,03h,0C3h,82h,0Ch,18h,04h,1Ah,00h,08h,00h,30h,01h,0E0h
        db 80h,0E1h,00h,04h,41h,88h,20h,00h,00h,00h,00h,00h,00h,01h,00h,20h
        db 04h,00h,80h,00h,00h,00h,00h,00h,00h,00h,60h,0Fh,83h,82h,0Ch,18h
        db 04h,1Ah,00h,0Ch,00h,0Ch,07h,0E0h,40h,0C1h,00h,06h,41h,8Ch,10h,00h
        db 00h,00h,00h,00h,00h,01h,00h,20h,04h,00h,80h,00h,00h,00h,00h,00h
        db 00h,00h,1Fh,0FFh,0FFh,01h,0FFh,0F8h,07h,0F9h,0FFh,0FCh,00h,03h,0FFh,80h
        db 7Fh,0C0h,0FFh,0FEh,3Fh,87h,0F0h,00h,00h,00h,00h,00h,00h,01h,00h,20h
        db 04h,00h,80h,00h,00h,00h,00h,00h,00h,00h,07h,0FCh,1Fh,00h,7Ch,0F8h
        db 00h,0F8h,7Fh,0FCh,00h,00h,0FEh,00h,0Fh,0C0h,3Fh,0FEh,0Fh,80h,0F8h,00h
        db 00h,00h,00h,00h,00h,01h,00h,20h,07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

game_over_red:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 27h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E4h,24h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,24h
        db 24h,40h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0F0h,01h,0FCh,03h,0F8h
        db 0Fh,0E1h,0FFh,0F8h,00h,03h,0F8h,3Fh,80h,7Eh,0FFh,0FCh,3Fh,0F8h,00h,00h
        db 00h,00h,00h,00h,00h,00h,02h,24h,24h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,7Fh,0FEh,01h,0FEh,07h,0FCh,1Fh,0F3h,0FFh,0F8h,00h,0Fh,0FFh,3Fh
        db 80h,0FFh,0FFh,0FCh,7Fh,0FEh,00h,00h,00h,00h,00h,00h,00h,00h,02h,24h
        db 27h,0F8h,00h,00h,00h,00h,00h,00h,00h,00h,0FFh,0FEh,03h,0FEh,07h,0FCh
        db 1Fh,0F3h,0FFh,0F8h,00h,3Fh,0FFh,9Fh,80h,0FFh,0FFh,0FCh,7Fh,0FFh,00h,00h
        db 00h,00h,00h,00h,00h,00h,1Fh,0E4h,24h,40h,00h,00h,00h,00h,00h,00h
        db 00h,01h,0FFh,0FEh,03h,0FFh,07h,0FEh,3Fh,0FBh,0FFh,0FCh,00h,7Fh,0FFh,0DFh
        db 0C0h,0FFh,0FFh,0FEh,7Fh,0FFh,80h,00h,00h,00h,00h,00h,00h,00h,02h,24h
        db 24h,40h,00h,00h,00h,00h,00h,00h,00h,03h,0FFh,0FFh,07h,0FFh,07h,0FEh
        db 3Fh,0FBh,0FFh,0FCh,00h,7Fh,0FFh,0FFh,0C1h,0FFh,0FFh,0FEh,7Fh,0FFh,80h,00h
        db 00h,00h,00h,00h,00h,00h,02h,24h,24h,40h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0FFh,0FFh,07h,0FFh,87h,0FFh,7Fh,0FBh,0FFh,0FCh,00h,0FFh,0FFh,0EFh
        db 0E1h,0FFh,0FFh,0FEh,7Fh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h,02h,24h
        db 24h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0FEh,0Fh,07h,0FFh,87h,0FFh
        db 7Fh,0FBh,0FCh,00h,00h,0FFh,0CFh,0FFh,0E3h,0FFh,0FEh,00h,7Fh,9Fh,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,24h,24h,00h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0FCh,01h,0Fh,0FFh,87h,0FFh,0FFh,0FBh,0FFh,0F0h,00h,0FFh,07h,0FFh
        db 0F3h,0FFh,0FFh,0F8h,7Fh,0BFh,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,24h
        db 24h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0F9h,0FEh,0Fh,0FFh,0C7h,0FFh
        db 0FFh,0FBh,0FFh,0F8h,01h,0FFh,07h,0FFh,0F3h,0FDh,0FFh,0FCh,7Fh,0FFh,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,24h,24h,00h,00h,00h,00h,00h,00h,00h
        db 00h,0Fh,0F3h,0FFh,0Fh,0FFh,0C7h,0FFh,0FFh,0FBh,0FFh,0F8h,01h,0FEh,07h,0FFh
        db 0F7h,0FDh,0FFh,0FCh,7Fh,0FFh,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,24h
        db 24h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0F3h,0FFh,1Fh,0FFh,0C7h,0FFh
        db 0FFh,0FBh,0FFh,0FCh,01h,0FEh,07h,0FBh,0FFh,0F9h,0FFh,0FEh,7Fh,0FFh,0C0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,24h,24h,00h,00h,00h,00h,00h,00h,00h
        db 00h,0Fh,0F3h,0FFh,9Fh,0FFh,0E7h,0FFh,0FFh,0FBh,0FFh,0FCh,01h,0FEh,07h,0FBh
        db 0FFh,0F9h,0FFh,0FEh,7Fh,0FFh,80h,00h,00h,00h,00h,00h,00h,00h,00h,24h
        db 24h,00h,00h,00h,00h,00h,00h,00h,00h,07h,0F1h,0FFh,0BFh,0FFh,0E7h,0FFh
        db 0FFh,0FBh,0FFh,0FCh,00h,0FEh,07h,0FBh,0FFh,0F9h,0FFh,0FEh,7Fh,0FFh,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,24h,24h,00h,00h,00h,00h,00h,00h,00h
        db 00h,07h,0F0h,7Fh,0BFh,0FFh,0F7h,0FFh,0FFh,0FBh,0FCh,00h,00h,0FEh,0Fh,0F9h
        db 0FFh,0F1h,0FEh,00h,7Fh,0FFh,80h,00h,00h,00h,00h,00h,00h,00h,00h,24h
        db 24h,00h,80h,00h,00h,00h,00h,00h,00h,07h,0F8h,7Fh,0BFh,0FFh,0F7h,0FBh
        db 0FFh,0FBh,0FCh,00h,00h,0FFh,1Fh,0F9h,0FFh,0F1h,0FEh,00h,7Fh,0BFh,0C0h,00h
        db 00h,00h,00h,00h,00h,01h,00h,24h,24h,00h,80h,00h,00h,00h,00h,00h
        db 00h,03h,0FFh,0FFh,0FFh,0FFh,0F7h,0FBh,0FFh,0FBh,0FFh,0F8h,00h,7Fh,0FFh,0F1h
        db 0FFh,0F1h,0FFh,0FCh,7Fh,9Fh,0C0h,00h,00h,00h,00h,00h,00h,01h,00h,24h
        db 24h,00h,80h,00h,00h,00h,00h,00h,00h,01h,0FFh,0FFh,0FFh,0FFh,0FFh,0F8h
        db 77h,0FBh,0FFh,0F8h,00h,7Fh,0FFh,0F0h,0FFh,0E1h,0FFh,0FCh,7Fh,9Fh,0E0h,00h
        db 00h,00h,00h,00h,00h,01h,00h,24h,24h,07h,0F0h,00h,00h,00h,00h,00h
        db 00h,00h,0FFh,0FFh,0FFh,83h,0FFh,0F8h,07h,0FBh,0FFh,0F8h,00h,3Fh,0FFh,0E0h
        db 0FFh,0E1h,0FFh,0FCh,7Fh,8Fh,0E0h,00h,00h,00h,00h,00h,00h,0Fh,0E0h,24h
        db 24h,00h,80h,00h,00h,00h,00h,00h,00h,00h,7Fh,0FFh,0FFh,83h,0FFh,0F8h
        db 07h,0FBh,0FFh,0FCh,00h,0Fh,0FFh,0E0h,7Fh,0C1h,0FFh,0FEh,7Fh,8Fh,0F0h,00h
        db 00h,00h,00h,00h,00h,01h,00h,24h,24h,00h,80h,00h,00h,00h,00h,00h
        db 00h,00h,1Fh,0FFh,0FFh,01h,0FFh,0F8h,07h,0F9h,0FFh,0FCh,00h,03h,0FFh,80h
        db 7Fh,0C0h,0FFh,0FEh,3Fh,87h,0F0h,00h,00h,00h,00h,00h,00h,01h,00h,24h
        db 24h,00h,80h,00h,00h,00h,00h,00h,00h,00h,07h,0FCh,1Fh,00h,7Ch,0F8h
        db 00h,0F8h,7Fh,0FCh,00h,00h,0FEh,00h,0Fh,0C0h,3Fh,0FEh,0Fh,80h,0F8h,00h
        db 00h,00h,00h,00h,00h,01h,00h,24h,27h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E4h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

game_over_green:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0F0h,01h,0FCh,03h,0F8h
        db 0Fh,0E1h,0FFh,0F8h,00h,03h,0F8h,3Fh,80h,7Eh,0FFh,0FCh,3Fh,0F8h,00h,00h
        db 00h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,70h,0Eh,01h,02h,04h,04h,10h,12h,00h,08h,00h,0Ch,07h,20h
        db 80h,83h,00h,04h,40h,06h,00h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 23h,0F8h,00h,00h,00h,00h,00h,00h,00h,00h,80h,02h,02h,02h,04h,04h
        db 10h,12h,00h,08h,00h,30h,01h,90h,80h,83h,00h,04h,40h,01h,00h,00h
        db 00h,00h,00h,00h,00h,00h,1Fh,0C4h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,01h,00h,02h,02h,02h,04h,04h,20h,12h,00h,08h,00h,60h,00h,50h
        db 40h,85h,00h,04h,40h,00h,80h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,00h,00h,00h,02h,07h,0E2h,06h,01h,04h,02h
        db 20h,12h,0Fh,0F8h,00h,40h,0F0h,70h,41h,05h,07h,0FCh,41h,0E0h,80h,00h
        db 00h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,04h,08h,1Ah,04h,01h,04h,02h,60h,12h,08h,00h,00h,83h,18h,28h
        db 61h,05h,04h,00h,41h,30h,80h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,04h,10h,06h,04h,20h,84h,01h
        db 40h,12h,08h,00h,00h,82h,08h,28h,23h,09h,04h,00h,41h,10h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,04h,30h,00h,08h,30h,84h,11h,0C4h,12h,0Fh,0F0h,00h,84h,04h,1Ch
        db 22h,09h,07h,0F8h,41h,30h,80h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,08h,21h,0FEh,08h,70h,84h,10h
        db 84h,12h,00h,08h,01h,04h,04h,14h,12h,11h,00h,04h,41h,0E0h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,22h,01h,08h,50h,44h,10h,8Ch,12h,00h,08h,01h,04h,04h,14h
        db 14h,11h,00h,04h,40h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,08h,22h,01h,10h,48h,44h,18h
        db 0Ch,12h,00h,08h,01h,04h,04h,12h,14h,11h,00h,04h,40h,02h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,08h,22h,01h,10h,0F8h,44h,18h,1Ch,12h,0Fh,0F0h,01h,04h,04h,12h
        db 0Ch,21h,07h,0F8h,40h,01h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,04h,31h,0C1h,30h,00h,24h,14h
        db 14h,12h,08h,00h,00h,84h,04h,12h,08h,21h,04h,00h,41h,0C1h,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,04h,10h,41h,20h,00h,24h,14h,14h,12h,08h,00h,00h,82h,08h,21h
        db 08h,21h,04h,00h,41h,20h,80h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,04h,08h,41h,20h,00h,14h,12h
        db 24h,12h,08h,00h,00h,83h,18h,21h,00h,41h,04h,00h,41h,30h,40h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,00h,00h
        db 00h,02h,07h,0C1h,41h,0FCh,14h,13h,0E4h,12h,0Fh,0F8h,00h,40h,0F0h,61h
        db 80h,41h,07h,0FCh,41h,10h,40h,00h,00h,00h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,01h,00h,01h,41h,02h,14h,10h
        db 04h,12h,00h,08h,00h,60h,00h,40h,80h,81h,00h,04h,41h,18h,20h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,07h,0F0h,00h,00h,00h,00h,00h
        db 00h,00h,80h,03h,42h,02h,0Ch,10h,04h,12h,00h,08h,00h,30h,01h,80h
        db 80h,81h,00h,04h,41h,08h,20h,00h,00h,00h,00h,00h,00h,0Fh,0E0h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,00h,60h,0Eh,82h,02h,0Ch,10h
        db 04h,12h,00h,08h,00h,0Ch,07h,00h,40h,81h,00h,04h,41h,0Ch,10h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,00h,00h
        db 00h,00h,1Fh,0F0h,0FEh,01h,0FBh,0E0h,07h,0E1h,0FFh,0F8h,00h,03h,0F8h,00h
        db 7Fh,00h,0FFh,0FCh,3Fh,07h,0E0h,00h,00h,00h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

bonus_points_blue:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,01h,0FFh,0E0h,01h,0FCh,01h,0F8h,3Fh,0Fh,0C1h
        db 0F8h,0Fh,0F0h,00h,1Fh,0FEh,00h,1Fh,0C0h,1Fh,8Fh,0C1h,0FBh,0FFh,0FFh,87h
        db 0F8h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,02h,00h
        db 38h,06h,03h,82h,04h,20h,90h,42h,08h,30h,0Eh,00h,20h,03h,80h,60h
        db 38h,20h,90h,21h,06h,00h,00h,98h,07h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,02h,00h,0Ch,18h,00h,0C2h,04h,20h,90h,42h
        db 08h,60h,02h,00h,20h,00h,0C1h,80h,0Ch,20h,90h,21h,06h,00h,00h,0B0h
        db 01h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,02h,00h
        db 04h,30h,00h,22h,02h,20h,90h,42h,08h,0C0h,02h,00h,20h,00h,43h,00h
        db 02h,20h,90h,11h,06h,00h,00h,0E0h,01h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,02h,0Fh,04h,20h,78h,32h,03h,20h,90h,42h
        db 08h,83h,0E2h,00h,20h,0F0h,22h,07h,83h,20h,90h,19h,07h,0F8h,3Fh,0C1h
        db 0F1h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,02h,08h
        db 82h,41h,8Ch,12h,01h,20h,90h,42h,08h,84h,1Ah,00h,20h,88h,24h,18h
        db 0C1h,20h,90h,09h,04h,08h,20h,42h,0Dh,00h,00h,00h,00h,00h,02h,04h
        db 20h,00h,00h,00h,00h,00h,02h,08h,84h,41h,04h,12h,01h,0A0h,90h,42h
        db 08h,84h,06h,00h,20h,88h,24h,10h,41h,20h,90h,0Dh,04h,08h,20h,42h
        db 03h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,02h,0Fh
        db 04h,42h,02h,0Ah,00h,0A0h,90h,42h,08h,83h,0C0h,00h,20h,88h,24h,20h
        db 20h,0A0h,90h,05h,04h,08h,20h,41h,0E0h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,02h,00h,0Ch,82h,02h,0Ah,08h,60h,90h,42h
        db 08h,80h,78h,00h,20h,88h,28h,20h,20h,0A0h,90h,43h,04h,08h,20h,40h
        db 3Ch,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,02h,00h
        db 08h,82h,02h,0Ah,08h,60h,90h,42h,08h,40h,06h,00h,20h,0F0h,28h,20h
        db 20h,0A0h,90h,43h,04h,08h,20h,20h,03h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,02h,00h,04h,82h,02h,0Ah,0Ch,20h,90h,42h
        db 08h,60h,02h,00h,20h,00h,48h,20h,20h,0A0h,90h,61h,04h,08h,20h,30h
        db 01h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,02h,0Fh
        db 82h,82h,02h,0Ah,0Ch,20h,90h,42h,08h,1Ch,01h,00h,20h,00h,0C8h,20h
        db 20h,0A0h,90h,61h,04h,08h,20h,0Eh,00h,80h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,02h,08h,82h,42h,02h,0Ah,0Ah,00h,90h,42h
        db 08h,03h,0C1h,00h,20h,03h,84h,20h,20h,0A0h,90h,50h,04h,08h,20h,01h
        db 0E0h,80h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,02h,08h
        db 42h,41h,04h,12h,0Ah,00h,90h,42h,08h,0C0h,61h,00h,20h,0FEh,04h,10h
        db 41h,20h,90h,50h,04h,08h,20h,60h,30h,80h,00h,00h,00h,00h,00h,04h
        db 20h,00h,80h,00h,00h,00h,02h,08h,82h,41h,8Ch,12h,09h,00h,88h,62h
        db 08h,0B8h,61h,00h,20h,80h,04h,18h,0C1h,20h,90h,48h,04h,08h,20h,5Ch
        db 30h,80h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,02h,0Fh
        db 82h,20h,78h,32h,09h,00h,88h,3Ch,10h,8Fh,0C1h,00h,20h,80h,02h,07h
        db 83h,20h,90h,48h,04h,08h,20h,47h,0E0h,80h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,02h,00h,02h,30h,00h,22h,08h,80h,8Ch,00h
        db 10h,80h,03h,00h,20h,80h,03h,00h,02h,20h,90h,44h,04h,08h,20h,40h
        db 01h,80h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,02h,00h
        db 04h,18h,00h,0C2h,08h,0C0h,86h,00h,20h,80h,06h,00h,20h,80h,01h,80h
        db 0Ch,20h,90h,46h,04h,08h,20h,40h,03h,00h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,02h,00h,18h,06h,03h,82h,08h,40h,83h,80h
        db 0C0h,0E0h,0Ch,00h,20h,80h,00h,60h,38h,20h,90h,42h,04h,08h,20h,70h
        db 06h,00h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,01h,0FFh
        db 0E0h,01h,0FCh,01h,0F0h,3Fh,00h,0FFh,00h,1Fh,0F0h,00h,1Fh,80h,00h,1Fh
        db 0C0h,1Fh,8Fh,81h,0F8h,0Fh,0E0h,0Fh,0F8h,00h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

bonus_points_red:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h,04h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,20h
        db 04h,40h,00h,00h,00h,00h,01h,0FFh,0E0h,01h,0FCh,01h,0F8h,3Fh,0Fh,0C1h
        db 0F8h,0Fh,0F0h,00h,1Fh,0FEh,00h,1Fh,0C0h,1Fh,8Fh,0C1h,0FBh,0FFh,0FFh,87h
        db 0F8h,00h,00h,00h,00h,00h,02h,20h,04h,40h,00h,00h,00h,00h,03h,0FFh
        db 0F8h,07h,0FFh,83h,0FCh,3Fh,9Fh,0C3h,0F8h,3Fh,0FEh,00h,3Fh,0FFh,80h,7Fh
        db 0F8h,3Fh,9Fh,0E1h,0FFh,0FFh,0FFh,9Fh,0FFh,00h,00h,00h,00h,00h,02h,20h
        db 07h,0F8h,00h,00h,00h,00h,03h,0FFh,0FCh,1Fh,0FFh,0C3h,0FCh,3Fh,9Fh,0C3h
        db 0F8h,7Fh,0FEh,00h,3Fh,0FFh,0C1h,0FFh,0FCh,3Fh,9Fh,0E1h,0FFh,0FFh,0FFh,0BFh
        db 0FFh,00h,00h,00h,00h,00h,1Fh,0E0h,04h,40h,00h,00h,00h,00h,03h,0FFh
        db 0FCh,3Fh,0FFh,0E3h,0FEh,3Fh,0DFh,0E3h,0FCh,0FFh,0FEh,00h,3Fh,0FFh,0C3h,0FFh
        db 0FEh,3Fh,0DFh,0F1h,0FFh,0FFh,0FFh,0FFh,0FFh,00h,00h,00h,00h,00h,02h,20h
        db 04h,40h,00h,00h,00h,00h,03h,0FFh,0FEh,3Fh,0FFh,0F3h,0FFh,3Fh,0DFh,0E3h
        db 0FCh,0FFh,0FFh,00h,3Fh,0FFh,0E3h,0FFh,0FFh,3Fh,0DFh,0F9h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,80h,00h,00h,00h,00h,02h,20h,04h,40h,00h,00h,00h,00h,03h,0FFh
        db 0FEh,7Fh,0FFh,0F3h,0FFh,3Fh,0DFh,0E3h,0FCh,0FFh,0FFh,00h,3Fh,0FFh,0E7h,0FFh
        db 0FFh,3Fh,0DFh,0F9h,0FEh,7Fh,0FFh,0FFh,0FFh,80h,00h,00h,00h,00h,02h,20h
        db 04h,00h,00h,00h,00h,00h,03h,0FCh,0FEh,7Fh,0E7h,0FBh,0FFh,0BFh,0DFh,0E3h
        db 0FCh,0FFh,0Fh,00h,3Fh,0CFh,0F7h,0FEh,7Fh,0BFh,0DFh,0FDh,0FEh,0Fh,0F0h,7Fh
        db 87h,80h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,03h,0FFh
        db 0FFh,7Fh,83h,0FBh,0FFh,0BFh,0DFh,0E3h,0FCh,0FFh,0C1h,00h,3Fh,0CFh,0FFh,0F8h
        db 3Fh,0BFh,0DFh,0FDh,0FEh,0Fh,0F0h,7Fh,0E0h,80h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,03h,0FFh,0FEh,0FFh,83h,0FBh,0FFh,0FFh,0DFh,0E3h
        db 0FCh,0FFh,0F8h,00h,3Fh,0CFh,0FFh,0F8h,3Fh,0BFh,0DFh,0FFh,0FEh,0Fh,0F0h,7Fh
        db 0FCh,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,03h,0FFh
        db 0FEh,0FFh,03h,0FFh,0FFh,0FFh,0DFh,0E3h,0FCh,7Fh,0FEh,00h,3Fh,0FFh,0FFh,0F0h
        db 3Fh,0FFh,0DFh,0FFh,0FEh,0Fh,0F0h,3Fh,0FFh,00h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,03h,0FFh,0FEh,0FFh,03h,0FFh,0FFh,0FFh,0DFh,0E3h
        db 0FCh,7Fh,0FEh,00h,3Fh,0FFh,0FFh,0F0h,3Fh,0FFh,0DFh,0FFh,0FEh,0Fh,0F0h,3Fh
        db 0FFh,00h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,03h,0FFh
        db 0FEh,0FFh,03h,0FFh,0FFh,0FFh,0DFh,0E3h,0FCh,1Fh,0FFh,00h,3Fh,0FFh,0FFh,0F0h
        db 3Fh,0FFh,0DFh,0FFh,0FEh,0Fh,0F0h,0Fh,0FFh,80h,00h,00h,00h,00h,00h,20h
        db 04h,00h,00h,00h,00h,00h,03h,0FFh,0FEh,7Fh,03h,0FFh,0FFh,0FFh,0DFh,0E3h
        db 0FCh,07h,0FFh,00h,3Fh,0FFh,0E7h,0F0h,3Fh,0FFh,0DFh,0FFh,0FEh,0Fh,0F0h,03h
        db 0FFh,80h,00h,00h,00h,00h,00h,20h,04h,00h,00h,00h,00h,00h,03h,0FCh
        db 7Fh,7Fh,07h,0FFh,0FFh,0FFh,0DFh,0E3h,0FCh,0C0h,0FFh,80h,3Fh,0FFh,0C7h,0F0h
        db 7Fh,0FFh,0DFh,0FFh,0FEh,0Fh,0F0h,60h,7Fh,0C0h,00h,00h,00h,00h,00h,20h
        db 04h,00h,80h,00h,00h,00h,03h,0FCh,0FFh,7Fh,8Fh,0FFh,0FDh,0FFh,0CFh,0E3h
        db 0FCh,0F8h,7Fh,80h,3Fh,0FFh,07h,0F8h,0FFh,0FFh,0DFh,0EFh,0FEh,0Fh,0F0h,7Ch
        db 3Fh,0C0h,00h,00h,00h,01h,00h,20h,04h,00h,80h,00h,00h,00h,03h,0FFh
        db 0FFh,3Fh,0FFh,0FBh,0FDh,0FFh,0CFh,0FFh,0FCh,0FFh,0FFh,80h,3Fh,0C0h,03h,0FFh
        db 0FFh,0BFh,0DFh,0EFh,0FEh,0Fh,0F0h,7Fh,0FFh,0C0h,00h,00h,00h,01h,00h,20h
        db 04h,00h,80h,00h,00h,00h,03h,0FFh,0FFh,3Fh,0FFh,0FBh,0FCh,0FFh,0CFh,0FFh
        db 0FCh,0FFh,0FFh,80h,3Fh,0C0h,03h,0FFh,0FFh,0BFh,0DFh,0E7h,0FEh,0Fh,0F0h,7Fh
        db 0FFh,0C0h,00h,00h,00h,01h,00h,20h,04h,07h,0F0h,00h,00h,00h,03h,0FFh
        db 0FFh,1Fh,0FFh,0F3h,0FCh,0FFh,0C7h,0FFh,0F8h,0FFh,0FFh,80h,3Fh,0C0h,01h,0FFh
        db 0FFh,3Fh,0DFh,0E7h,0FEh,0Fh,0F0h,7Fh,0FFh,0C0h,00h,00h,00h,0Fh,0E0h,20h
        db 04h,00h,80h,00h,00h,00h,03h,0FFh,0FFh,07h,0FFh,0F3h,0FCh,7Fh,0C3h,0FFh
        db 0F8h,0FFh,0FFh,00h,3Fh,0C0h,00h,7Fh,0FFh,3Fh,0DFh,0E3h,0FEh,0Fh,0F0h,7Fh
        db 0FFh,80h,00h,00h,00h,01h,00h,20h,04h,00h,80h,00h,00h,00h,01h,0FFh
        db 0FEh,01h,0FFh,0C1h,0FCh,3Fh,0C0h,0FFh,0F0h,1Fh,0FEh,00h,1Fh,0C0h,00h,1Fh
        db 0FCh,1Fh,0CFh,0E1h,0FEh,0Fh,0F0h,0Fh,0FFh,00h,00h,00h,00h,01h,00h,20h
        db 04h,00h,80h,00h,00h,00h,00h,7Fh,0F8h,00h,7Fh,00h,7Ch,0Fh,0C0h,1Fh
        db 0C0h,07h,0FCh,00h,07h,0C0h,00h,07h,0F0h,07h,0C3h,0E0h,7Eh,01h,0F0h,03h
        db 0FEh,00h,00h,00h,00h,01h,00h,20h,07h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0E0h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

bonus_points_green:
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,40h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,01h,0FFh,0E0h,01h,0FCh,01h,0F8h,3Fh,0Fh,0C1h
        db 0F8h,0Fh,0F0h,00h,1Fh,0FEh,00h,1Fh,0C0h,1Fh,8Fh,0C1h,0FBh,0FFh,0FFh,87h
        db 0F8h,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,03h,0FFh
        db 0F8h,07h,0FFh,83h,0FCh,3Fh,9Fh,0C3h,0F8h,3Fh,0FEh,00h,3Fh,0FFh,80h,7Fh
        db 0F8h,3Fh,9Fh,0E1h,0FFh,0FFh,0FFh,9Fh,0FFh,00h,00h,00h,00h,00h,02h,04h
        db 23h,0F8h,00h,00h,00h,00h,03h,0FFh,0FCh,1Fh,0FFh,0C3h,0FCh,3Fh,9Fh,0C3h
        db 0F8h,7Fh,0FEh,00h,3Fh,0FFh,0C1h,0FFh,0FCh,3Fh,9Fh,0E1h,0FFh,0FFh,0FFh,0BFh
        db 0FFh,00h,00h,00h,00h,00h,1Fh,0C4h,20h,40h,00h,00h,00h,00h,03h,0FFh
        db 0FCh,3Fh,0FFh,0E3h,0FEh,3Fh,9Fh,0C3h,0F8h,0FFh,0FEh,00h,3Fh,0FFh,0C3h,0FFh
        db 0FEh,3Fh,9Fh,0F1h,0FFh,0FFh,0FFh,0FFh,0FFh,00h,00h,00h,00h,00h,02h,04h
        db 20h,40h,00h,00h,00h,00h,03h,0FFh,0FCh,3Fh,0FFh,0F3h,0FFh,3Fh,9Fh,0C3h
        db 0F8h,0FFh,0FEh,00h,3Fh,0FFh,0E3h,0FFh,0FFh,3Fh,9Fh,0F9h,0FFh,0FFh,0FFh,0FFh
        db 0FFh,00h,00h,00h,00h,00h,02h,04h,20h,40h,00h,00h,00h,00h,03h,0F8h
        db 0FEh,7Fh,8Fh,0F3h,0FFh,3Fh,9Fh,0C3h,0F8h,0FCh,1Eh,00h,3Fh,8Fh,0E7h,0F8h
        db 0FFh,3Fh,9Fh,0F9h,0FCh,0Fh,0E0h,7Eh,0Fh,00h,00h,00h,00h,00h,02h,04h
        db 20h,00h,00h,00h,00h,00h,03h,0F8h,0FCh,7Fh,07h,0F3h,0FFh,0BFh,9Fh,0C3h
        db 0F8h,0FCh,06h,00h,3Fh,8Fh,0E7h,0F0h,7Fh,3Fh,9Fh,0FDh,0FCh,0Fh,0E0h,7Eh
        db 03h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,03h,0FFh
        db 0FCh,7Eh,03h,0FBh,0FFh,0BFh,9Fh,0C3h,0F8h,0FFh,0C0h,00h,3Fh,8Fh,0E7h,0E0h
        db 3Fh,0BFh,9Fh,0FDh,0FCh,0Fh,0E0h,7Fh,0E0h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,03h,0FFh,0FCh,0FEh,03h,0FBh,0FFh,0FFh,9Fh,0C3h
        db 0F8h,0FFh,0F8h,00h,3Fh,8Fh,0EFh,0E0h,3Fh,0BFh,9Fh,0FFh,0FCh,0Fh,0E0h,7Fh
        db 0FCh,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,03h,0FFh
        db 0F8h,0FEh,03h,0FBh,0FFh,0FFh,9Fh,0C3h,0F8h,7Fh,0FEh,00h,3Fh,0FFh,0EFh,0E0h
        db 3Fh,0BFh,9Fh,0FFh,0FCh,0Fh,0E0h,3Fh,0FFh,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,03h,0FFh,0FCh,0FEh,03h,0FBh,0FFh,0FFh,9Fh,0C3h
        db 0F8h,7Fh,0FEh,00h,3Fh,0FFh,0CFh,0E0h,3Fh,0BFh,9Fh,0FFh,0FCh,0Fh,0E0h,3Fh
        db 0FFh,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,03h,0FFh
        db 0FEh,0FEh,03h,0FBh,0FFh,0FFh,9Fh,0C3h,0F8h,1Fh,0FFh,00h,3Fh,0FFh,0CFh,0E0h
        db 3Fh,0BFh,9Fh,0FFh,0FCh,0Fh,0E0h,0Fh,0FFh,80h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,03h,0F8h,0FEh,7Eh,03h,0FBh,0FBh,0FFh,9Fh,0C3h
        db 0F8h,03h,0FFh,00h,3Fh,0FFh,87h,0E0h,3Fh,0BFh,9Fh,0DFh,0FCh,0Fh,0E0h,01h
        db 0FFh,80h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,03h,0F8h
        db 7Eh,7Fh,07h,0F3h,0FBh,0FFh,9Fh,0C3h,0F8h,0C0h,7Fh,00h,3Fh,0FEh,07h,0F0h
        db 7Fh,3Fh,9Fh,0DFh,0FCh,0Fh,0E0h,60h,3Fh,80h,00h,00h,00h,00h,00h,04h
        db 20h,00h,80h,00h,00h,00h,03h,0F8h,0FEh,7Fh,8Fh,0F3h,0F9h,0FFh,8Fh,0E3h
        db 0F8h,0F8h,7Fh,00h,3Fh,80h,07h,0F8h,0FFh,3Fh,9Fh,0CFh,0FCh,0Fh,0E0h,7Ch
        db 3Fh,80h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,03h,0FFh
        db 0FEh,3Fh,0FFh,0F3h,0F9h,0FFh,8Fh,0FFh,0F0h,0FFh,0FFh,00h,3Fh,80h,03h,0FFh
        db 0FFh,3Fh,9Fh,0CFh,0FCh,0Fh,0E0h,7Fh,0FFh,80h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,03h,0FFh,0FEh,3Fh,0FFh,0E3h,0F8h,0FFh,8Fh,0FFh
        db 0F0h,0FFh,0FFh,00h,3Fh,80h,03h,0FFh,0FEh,3Fh,9Fh,0C7h,0FCh,0Fh,0E0h,7Fh
        db 0FFh,80h,00h,00h,00h,01h,00h,04h,20h,07h,0F0h,00h,00h,00h,03h,0FFh
        db 0FCh,1Fh,0FFh,0C3h,0F8h,0FFh,87h,0FFh,0E0h,0FFh,0FEh,00h,3Fh,80h,01h,0FFh
        db 0FCh,3Fh,9Fh,0C7h,0FCh,0Fh,0E0h,7Fh,0FFh,00h,00h,00h,00h,0Fh,0E0h,04h
        db 20h,00h,80h,00h,00h,00h,03h,0FFh,0F8h,07h,0FFh,83h,0F8h,7Fh,83h,0FFh
        db 0C0h,0FFh,0FCh,00h,3Fh,80h,00h,7Fh,0F8h,3Fh,9Fh,0C3h,0FCh,0Fh,0E0h,7Fh
        db 0FEh,00h,00h,00h,00h,01h,00h,04h,20h,00h,80h,00h,00h,00h,01h,0FFh
        db 0E0h,01h,0FCh,01h,0F0h,3Fh,00h,0FFh,00h,1Fh,0F0h,00h,1Fh,80h,00h,1Fh
        db 0C0h,1Fh,8Fh,81h,0F8h,0Fh,0E0h,0Fh,0F8h,00h,00h,00h,00h,01h,00h,04h
        db 20h,00h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,01h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 20h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,04h,20h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,04h
        db 3Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FCh,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

bunker_template:
        db 00h,03Ch,0FFh,0FFh,03Ch,00h
        db 01h,0FFh,0FFh,0FFh,0FFh,080h
        db 07h,0FFh,0FFh,0FFh,0FFh,0E0h
        db 0Fh,0FFh,0FFh,0FFh,0FFh,0F0h
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
        db 0FFh,0FFh,0F0h,00Fh,0FFh,0FFh
        db 0FFh,0FFh,0C0h,003h,0FFh,0FFh
        db 0FFh,0FFh,000h,000h,0FFh,0FFh
        db 0FFh,0FCh,000h,000h,03Fh,0FFh


; Four pre-shifted 32x12 UFO frames. Each frame is 5 bytes x 12 rows.
; Phases correspond to horizontal offsets 0, 2, 4 and 6 pixels.
ufo_blue_shifted:
        db 00h,3Fh,0FCh,00h,00h,00h,7Fh,0FEh,00h,00h,00h,0FFh,0FFh,00h,00h,01h,0FFh,0FFh,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,00h,00h,01h,00h
        db 09h,0FEh,7Fh,90h,00h,01h,0FEh,7Fh,80h,00h,01h,0FFh,0FFh,80h,00h,00h,0FFh,0FFh,00h,00h
        db 00h,0Fh,0FFh,00h,00h,00h,1Fh,0FFh,80h,00h,00h,3Fh,0FFh,0C0h,00h,00h,7Fh,0FFh,0E0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,20h,00h,00h,00h,40h
        db 02h,7Fh,9Fh,0E4h,00h,00h,7Fh,9Fh,0E0h,00h,00h,7Fh,0FFh,0E0h,00h,00h,3Fh,0FFh,0C0h,00h
        db 00h,03h,0FFh,0C0h,00h,00h,07h,0FFh,0E0h,00h,00h,0Fh,0FFh,0F0h,00h,00h,1Fh,0FFh,0F8h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,08h,00h,00h,00h,10h
        db 00h,9Fh,0E7h,0F9h,00h,00h,1Fh,0E7h,0F8h,00h,00h,1Fh,0FFh,0F8h,00h,00h,0Fh,0FFh,0F0h,00h
        db 00h,00h,0FFh,0F0h,00h,00h,01h,0FFh,0F8h,00h,00h,03h,0FFh,0FCh,00h,00h,07h,0FFh,0FEh,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,02h,00h,00h,00h,04h
        db 00h,27h,0F9h,0FEh,40h,00h,07h,0F9h,0FEh,00h,00h,07h,0FFh,0FEh,00h,00h,03h,0FFh,0FCh,00h

ufo_red_shifted:
        db 00h,3Fh,0FCh,00h,00h,00h,70h,0Eh,00h,00h,00h,0E0h,07h,00h,00h,01h,0C0h,03h,80h,00h
        db 0Fh,0FFh,0FFh,0F0h,00h,1Fh,0FFh,0FFh,0F8h,00h,7Fh,0FFh,0FFh,0FEh,00h,7Fh,0FFh,0FFh,0FEh,00h
        db 0Fh,0FFh,0FFh,0F0h,00h,07h,0FFh,0FFh,0E0h,00h,01h,0FFh,0FFh,80h,00h,00h,0FFh,0FFh,00h,00h
        db 00h,0Fh,0FFh,00h,00h,00h,1Ch,03h,80h,00h,00h,38h,01h,0C0h,00h,00h,70h,00h,0E0h,00h
        db 03h,0FFh,0FFh,0FCh,00h,07h,0FFh,0FFh,0FEh,00h,1Fh,0FFh,0FFh,0FFh,80h,1Fh,0FFh,0FFh,0FFh,80h
        db 03h,0FFh,0FFh,0FCh,00h,01h,0FFh,0FFh,0F8h,00h,00h,7Fh,0FFh,0E0h,00h,00h,3Fh,0FFh,0C0h,00h
        db 00h,03h,0FFh,0C0h,00h,00h,07h,00h,0E0h,00h,00h,0Eh,00h,70h,00h,00h,1Ch,00h,38h,00h
        db 00h,0FFh,0FFh,0FFh,00h,01h,0FFh,0FFh,0FFh,80h,07h,0FFh,0FFh,0FFh,0E0h,07h,0FFh,0FFh,0FFh,0E0h
        db 00h,0FFh,0FFh,0FFh,00h,00h,7Fh,0FFh,0FEh,00h,00h,1Fh,0FFh,0F8h,00h,00h,0Fh,0FFh,0F0h,00h
        db 00h,00h,0FFh,0F0h,00h,00h,01h,0C0h,38h,00h,00h,03h,80h,1Ch,00h,00h,07h,00h,0Eh,00h
        db 00h,3Fh,0FFh,0FFh,0C0h,00h,7Fh,0FFh,0FFh,0E0h,01h,0FFh,0FFh,0FFh,0F8h,01h,0FFh,0FFh,0FFh,0F8h
        db 00h,3Fh,0FFh,0FFh,0C0h,00h,1Fh,0FFh,0FFh,80h,00h,07h,0FFh,0FEh,00h,00h,03h,0FFh,0FCh,00h

ufo_green_shifted:
        db 00h,3Fh,0FCh,00h,00h,00h,7Fh,0FEh,00h,00h,00h,0FFh,0FFh,00h,00h,01h,0FFh,0FFh,80h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,3Fh,0FFh,0FFh,0FCh,00h,80h,00h,00h,01h,00h
        db 06h,31h,8Ch,60h,00h,06h,31h,8Ch,60h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,0Fh,0FFh,00h,00h,00h,1Fh,0FFh,80h,00h,00h,3Fh,0FFh,0C0h,00h,00h,7Fh,0FFh,0E0h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0Fh,0FFh,0FFh,0FFh,00h,20h,00h,00h,00h,40h
        db 01h,8Ch,63h,18h,00h,01h,8Ch,63h,18h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,03h,0FFh,0C0h,00h,00h,07h,0FFh,0E0h,00h,00h,0Fh,0FFh,0F0h,00h,00h,1Fh,0FFh,0F8h,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,03h,0FFh,0FFh,0FFh,0C0h,08h,00h,00h,00h,10h
        db 00h,63h,18h,0C6h,00h,00h,63h,18h,0C6h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
        db 00h,00h,0FFh,0F0h,00h,00h,01h,0FFh,0F8h,00h,00h,03h,0FFh,0FCh,00h,00h,07h,0FFh,0FEh,00h
        db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,0FFh,0FFh,0FFh,0F0h,02h,00h,00h,00h,04h
        db 00h,18h,0C6h,31h,80h,00h,18h,0C6h,31h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; 32x12 UFO bonus explosion: white center, yellow cloud and red fragments.
ufo_explosion_blue:
        db 081h,000h,000h,081h, 042h,024h,024h,042h, 024h,05Ah,05Ah,024h
        db 018h,07Eh,07Eh,018h, 03Ch,0FFh,0FFh,03Ch, 07Eh,0FFh,0FFh,07Eh
        db 03Ch,0FFh,0FFh,03Ch, 018h,07Eh,07Eh,018h, 024h,05Ah,05Ah,024h
        db 042h,024h,024h,042h, 081h,000h,000h,081h, 000h,081h,081h,000h
ufo_explosion_red:
        db 081h,000h,000h,081h, 042h,024h,024h,042h, 024h,05Ah,05Ah,024h
        db 018h,07Eh,07Eh,018h, 03Ch,0FFh,0FFh,03Ch, 07Eh,0FFh,0FFh,07Eh
        db 03Ch,0FFh,0FFh,03Ch, 018h,07Eh,07Eh,018h, 024h,05Ah,05Ah,024h
        db 042h,024h,024h,042h, 081h,000h,000h,081h, 000h,081h,081h,000h
ufo_explosion_green:
        db 000h,000h,000h,000h, 000h,024h,024h,000h, 024h,05Ah,05Ah,024h
        db 018h,07Eh,07Eh,018h, 03Ch,0FFh,0FFh,03Ch, 07Eh,0FFh,0FFh,07Eh
        db 03Ch,0FFh,0FFh,03Ch, 018h,07Eh,07Eh,018h, 024h,05Ah,05Ah,024h
        db 000h,024h,024h,000h, 000h,000h,000h,000h, 000h,081h,081h,000h

; 10x14 doubled score digits, 28 bytes per digit.
digit_font_10x14:
        db 03Fh,000h,03Fh,000h,0C0h,0C0h,0C0h,0C0h,0C3h,0C0h,0C3h,0C0h,0CCh,0C0h,0CCh,0C0h,0F0h,0C0h,0F0h,0C0h,0C0h,0C0h,0C0h,0C0h,03Fh,000h,03Fh,000h
        db 00Ch,000h,00Ch,000h,03Ch,000h,03Ch,000h,0CCh,000h,0CCh,000h,00Ch,000h,00Ch,000h,00Ch,000h,00Ch,000h,00Ch,000h,00Ch,000h,0FFh,0C0h,0FFh,0C0h
        db 03Fh,000h,03Fh,000h,0C0h,0C0h,0C0h,0C0h,000h,0C0h,000h,0C0h,00Fh,000h,00Fh,000h,030h,000h,030h,000h,0C0h,000h,0C0h,000h,0FFh,0C0h,0FFh,0C0h
        db 0FFh,000h,0FFh,000h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,03Fh,000h,03Fh,000h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,0FFh,000h,0FFh,000h
        db 003h,000h,003h,000h,00Fh,000h,00Fh,000h,033h,000h,033h,000h,0C3h,000h,0C3h,000h,0FFh,0C0h,0FFh,0C0h,003h,000h,003h,000h,003h,000h,003h,000h
        db 0FFh,0C0h,0FFh,0C0h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0FFh,000h,0FFh,000h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,0FFh,000h,0FFh,000h
        db 03Fh,000h,03Fh,000h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0FFh,000h,0FFh,000h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,03Fh,000h,03Fh,000h
        db 0FFh,0C0h,0FFh,0C0h,000h,0C0h,000h,0C0h,003h,000h,003h,000h,00Ch,000h,00Ch,000h,030h,000h,030h,000h,030h,000h,030h,000h,030h,000h,030h,000h
        db 03Fh,000h,03Fh,000h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,03Fh,000h,03Fh,000h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,03Fh,000h,03Fh,000h
        db 03Fh,000h,03Fh,000h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,0C0h,03Fh,0C0h,03Fh,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,000h,0C0h,03Fh,000h,03Fh,000h

; 5x7 digits retained for compact UI elements.
digit_font_5x7:
        db 070h,088h,098h,0A8h,0C8h,088h,070h ; 0
        db 020h,060h,0A0h,020h,020h,020h,0F8h ; 1
        db 070h,088h,008h,030h,040h,080h,0F8h ; 2
        db 0F0h,008h,008h,070h,008h,008h,0F0h ; 3
        db 010h,030h,050h,090h,0F8h,010h,010h ; 4
        db 0F8h,080h,080h,0F0h,008h,008h,0F0h ; 5
        db 070h,080h,080h,0F0h,088h,088h,070h ; 6
        db 0F8h,008h,010h,020h,040h,040h,040h ; 7
        db 070h,088h,088h,070h,088h,088h,070h ; 8
        db 070h,088h,088h,078h,008h,008h,070h ; 9

life_icon:
        db 018h,03Ch,07Eh,0FFh,066h

; Three-plane Galaga-inspired player ship, 24x14 pixels.
ship_blue:
        db 000h,018h,000h, 000h,03Ch,000h, 000h,07Eh,000h
        db 000h,0FFh,000h, 018h,0FFh,018h, 03Ch,0FFh,03Ch
        db 07Eh,0FFh,07Eh, 0FFh,0FFh,0FFh, 0FFh,0FFh,0FFh
        db 07Eh,0FFh,07Eh, 03Ch,0FFh,03Ch, 018h,07Eh,018h
        db 000h,066h,000h, 000h,042h,000h
        db 000h, 024h, 000h, 000h, 042h, 000h

ship_red:
        db 000h,018h,000h, 000h,018h,000h, 000h,03Ch,000h
        db 000h,03Ch,000h, 018h,03Ch,018h, 03Ch,018h,03Ch
        db 07Eh,018h,07Eh, 0FFh,018h,0FFh, 0E7h,03Ch,0E7h
        db 066h,018h,066h, 024h,018h,024h, 018h,000h,018h
        db 000h,000h,000h, 000h,000h,000h
        db 000h, 024h, 000h, 000h, 042h, 000h

ship_green:
        db 000h,018h,000h, 000h,03Ch,000h, 000h,07Eh,000h
        db 000h,0FFh,000h, 018h,0FFh,018h, 03Ch,0FFh,03Ch
        db 07Eh,0FFh,07Eh, 0FFh,0FFh,0FFh, 0FFh,0FFh,0FFh
        db 07Eh,0FFh,07Eh, 03Ch,0FFh,03Ch, 018h,07Eh,018h
        db 000h,066h,000h, 000h,042h,000h

; Large 40x20 player explosion: white core, yellow cloud, red/magenta fragments.
player_explosion_blue:
        db 000h,004h,000h,020h,000h
        db 000h,000h,080h,004h,000h
        db 000h,000h,000h,000h,080h
        db 000h,040h,002h,000h,000h
        db 000h,000h,000h,000h,000h
        db 020h,000h,000h,000h,000h
        db 004h,000h,000h,000h,000h
        db 000h,000h,014h,000h,020h
        db 000h,001h,02Eh,000h,004h
        db 000h,000h,03Ch,000h,000h
        db 008h,000h,07Eh,000h,000h
        db 001h,000h,056h,000h,000h
        db 000h,000h,008h,000h,008h
        db 000h,000h,000h,000h,000h
        db 010h,000h,000h,000h,000h
        db 002h,000h,000h,000h,080h
        db 000h,040h,000h,000h,010h
        db 000h,008h,000h,040h,000h
        db 000h,001h,000h,008h,000h
        db 000h,000h,020h,000h,000h
player_explosion_red:
        db 080h,004h,008h,020h,001h
        db 000h,000h,080h,004h,000h
        db 000h,000h,018h,000h,080h
        db 000h,043h,06Fh,040h,000h
        db 000h,00Bh,0FFh,0ECh,000h
        db 020h,07Fh,0FFh,0FCh,000h
        db 005h,0FFh,0FFh,0FFh,000h
        db 002h,0FFh,0FFh,0FFh,0A0h
        db 001h,0FFh,0FFh,0FFh,0C4h
        db 001h,0FFh,0FFh,0FFh,080h
        db 08Bh,0FFh,0FFh,0FFh,0C1h
        db 003h,0FFh,0FFh,0FFh,0C0h
        db 001h,0FFh,0FFh,0FFh,008h
        db 000h,0FFh,0FFh,0FFh,080h
        db 010h,06Fh,0FFh,0FDh,000h
        db 002h,00Bh,0FFh,0ECh,080h
        db 000h,04Ch,03Fh,080h,010h
        db 000h,008h,021h,040h,000h
        db 000h,001h,000h,008h,000h
        db 080h,000h,028h,000h,001h
player_explosion_green:
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,007h,080h,000h
        db 000h,00Eh,03Dh,0C0h,000h
        db 000h,005h,0FFh,0A0h,000h
        db 000h,017h,0FFh,0E0h,000h
        db 000h,007h,0FFh,0E0h,000h
        db 000h,03Fh,0FFh,0E8h,000h
        db 000h,01Fh,0FFh,0E8h,000h
        db 000h,007h,0FFh,0C0h,000h
        db 000h,000h,01Fh,080h,000h
        db 000h,000h,048h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h
        db 000h,000h,000h,000h,000h

; Final 40x22 seven-color alien explosion.
alien_explosion_blue:
        db 00h,00h,00h,00h,00h
        db 00h,00h,38h,00h,00h
        db 00h,00h,38h,00h,1Ch
        db 38h,00h,00h,0Eh,1Ch
        db 38h,00h,00h,0Eh,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,3Ch,00h,00h
        db 00h,00h,0FFh,00h,00h
        db 00h,01h,0FFh,80h,38h
        db 00h,01h,0FFh,80h,38h
        db 0E0h,01h,0FFh,80h,00h
        db 0E0h,00h,0FFh,00h,00h
        db 00h,00h,3Ch,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,03h,80h,00h
        db 00h,00h,03h,80h,00h

alien_explosion_red:
        db 00h,00h,00h,00h,00h
        db 00h,00h,38h,00h,00h
        db 00h,00h,38h,00h,00h
        db 38h,00h,00h,10h,00h
        db 38h,00h,0FFh,00h,00h
        db 00h,07h,0FFh,0E4h,00h
        db 02h,1Fh,0FFh,0F8h,00h
        db 00h,3Fh,0FFh,0FDh,00h
        db 0Eh,0FFh,0FFh,0FEh,00h
        db 0Eh,0FFh,0FFh,0FFh,40h
        db 00h,0FFh,0FFh,0FFh,38h
        db 00h,0FFh,0FFh,0FFh,38h
        db 00h,0FFh,0FFh,0FFh,00h
        db 04h,0FFh,0FFh,0FFh,00h
        db 00h,7Fh,0FFh,0FEh,00h
        db 01h,3Fh,0FFh,0FCh,00h
        db 00h,1Fh,0FFh,0F8h,80h
        db 00h,47h,0FFh,0E0h,00h
        db 00h,00h,0FFh,00h,20h
        db 07h,10h,00h,10h,00h
        db 07h,00h,03h,80h,0E0h
        db 00h,00h,03h,80h,0E0h

alien_explosion_green:
        db 00h,00h,00h,00h,00h
        db 00h,00h,38h,00h,00h
        db 00h,1Ch,38h,00h,1Ch
        db 00h,1Ch,00h,00h,1Ch
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,0FFh,00h,00h
        db 00h,03h,0FFh,0C0h,00h
        db 0Eh,07h,0FFh,0E0h,00h
        db 0Eh,0Fh,0FFh,0F0h,00h
        db 00h,1Fh,0FFh,0F8h,38h
        db 00h,1Fh,0FFh,0F8h,38h
        db 00h,1Fh,0FFh,0F8h,00h
        db 00h,0Fh,0FFh,0F0h,00h
        db 00h,07h,0FFh,0E0h,00h
        db 00h,03h,0FFh,0C0h,03h
        db 00h,00h,0FFh,00h,03h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,00h
        db 00h,00h,00h,00h,0E0h
        db 00h,00h,00h,00h,0E0h

; GOLD 20x13 true-color alien sprite frames.
squid_f1_blue:
        db 00h,00h,00h
        db 00h,0FFh,00h
        db 01h,0FFh,80h
        db 01h,0FFh,0C0h
        db 01h,0FFh,0A0h
        db 07h,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 0Fh,0FFh,0F0h
        db 07h,0FFh,0E0h
        db 01h,0FFh,80h
        db 00h,42h,00h
        db 00h,42h,00h
squid_f1_red:
        db 00h,00h,00h
        db 08h,0FFh,10h
        db 05h,0FFh,0A0h
        db 05h,0FFh,0E0h
        db 03h,0FFh,0E0h
        db 07h,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 0Fh,0FFh,0F0h
        db 07h,0FFh,0E0h
        db 03h,0FFh,0C0h
        db 04h,42h,20h
        db 08h,42h,10h
squid_f1_green:
        db 00h,00h,00h
        db 08h,00h,10h
        db 04h,00h,20h
        db 04h,00h,20h
        db 02h,00h,40h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 02h,24h,40h
        db 04h,42h,20h
        db 08h,42h,10h

squid_f2_blue:
        db 00h,00h,00h
        db 00h,0FFh,00h
        db 01h,0FFh,80h
        db 01h,0FFh,0C0h
        db 01h,0FFh,0A0h
        db 07h,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 0Fh,0FFh,0F0h
        db 07h,0FFh,0E0h
        db 01h,0FFh,80h
        db 00h,0C3h,00h
        db 03h,00h,0C0h
squid_f2_red:
        db 00h,00h,00h
        db 08h,0FFh,10h
        db 05h,0FFh,0A0h
        db 05h,0FFh,0E0h
        db 03h,0FFh,0E0h
        db 07h,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 0Fh,0FFh,0F0h
        db 07h,0FFh,0E0h
        db 03h,0FFh,0C0h
        db 01h,0C3h,80h
        db 03h,81h,0C0h
squid_f2_green:
        db 00h,00h,00h
        db 08h,00h,10h
        db 04h,00h,20h
        db 04h,00h,20h
        db 02h,00h,40h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 02h,24h,40h
        db 01h,0C3h,80h
        db 03h,81h,0C0h

crab_f1_blue:
        db 00h,00h,00h
        db 10h,00h,08h
        db 08h,00h,10h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 1Fh,0FFh,0F8h
        db 3Fh,0FFh,0FCh
        db 3Fh,0FFh,0FCh
        db 3Fh,0FFh,0FCh
        db 07h,0FFh,0E0h
        db 04h,24h,20h
        db 04h,42h,20h
        db 08h,42h,10h
crab_f1_red:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 02h,00h,40h
        db 04h,00h,20h
        db 04h,00h,20h
        db 08h,00h,10h
crab_f1_green:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 03h,0FFh,0C0h
        db 07h,0FFh,0E0h
        db 1Fh,0FFh,0F8h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 07h,0DBh,0E0h
        db 04h,00h,20h
        db 04h,00h,20h
        db 08h,00h,10h

crab_f2_blue:
        db 00h,00h,00h
        db 10h,00h,08h
        db 08h,00h,10h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 1Fh,0FFh,0F8h
        db 3Fh,0FFh,0FCh
        db 3Fh,0FFh,0FCh
        db 3Fh,0FFh,0FCh
        db 07h,0FFh,0E0h
        db 01h,0C3h,80h
        db 03h,00h,0C0h
        db 00h,81h,00h
crab_f2_red:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 02h,00h,40h
        db 01h,00h,80h
        db 00h,00h,00h
        db 00h,81h,00h
crab_f2_green:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 03h,0FFh,0C0h
        db 07h,0FFh,0E0h
        db 1Fh,0FFh,0F8h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 07h,0FFh,0E0h
        db 07h,0DBh,0E0h
        db 01h,00h,80h
        db 00h,00h,00h
        db 00h,81h,00h

octopus_f1_blue:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,3Ch,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
octopus_f1_red:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 20h,3Ch,04h
        db 00h,00h,00h
        db 04h,42h,20h
        db 04h,42h,20h
        db 08h,84h,40h
        db 08h,84h,40h
octopus_f1_green:
        db 00h,00h,00h
        db 00h,0FFh,00h
        db 03h,0FFh,0C0h
        db 0Fh,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 1Fh,0FFh,0F8h
        db 2Fh,0FFh,0F4h
        db 0Fh,0FFh,0F0h
        db 0Bh,0BDh,0D0h
        db 00h,0BDh,00h
        db 00h,00h,00h
        db 00h,00h,00h

octopus_f2_blue:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,3Ch,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
octopus_f2_red:
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,00h,00h
        db 00h,0C3h,00h
        db 00h,0C3h,00h
        db 00h,00h,00h
        db 20h,3Ch,04h
        db 00h,00h,00h
        db 02h,22h,20h
        db 02h,22h,20h
        db 01h,14h,40h
        db 01h,14h,40h
octopus_f2_green:
        db 00h,00h,00h
        db 00h,0FFh,00h
        db 03h,0FFh,0C0h
        db 0Fh,0FFh,0F0h
        db 0Fh,0FFh,0F0h
        db 1Fh,0FFh,0F8h
        db 1Fh,0FFh,0F8h
        db 2Fh,0FFh,0F4h
        db 0Fh,0FFh,0F0h
        db 0Dh,0DDh,0D0h
        db 00h,0DDh,00h
        db 00h,00h,00h
        db 00h,00h,00h

