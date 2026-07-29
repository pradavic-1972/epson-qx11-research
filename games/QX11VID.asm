; ============================================================================
; QX11SCI.DRV - Universal SCI0 video driver for Epson QX-11
; Derived from the PC1.DRV source supplied by the user.
;
; Target:
;   Epson QX-11 / QC-11, 8088 compatible CPU
;   QX native 640x200 planar color mode (verified 0100h row pitch)
;
; Confirmed QX mode-2 plane mapping:
;   8000h = Blue
;   8008h = Red
;   9000h = Green
;
; SCI framebuffer:
;   320x200, packed 4-bit pixels, two pixels per byte, 160 bytes/row
;
; Conversion:
;   Four SCI pixels (two source bytes) become one QX byte in 0each plane.
;   0Each SCI pixel is doubled horizontally:
;       pixel 0 -> bits 7,6 (0C0h)
;       pixel 1 -> bits 5,4 (30h)
;       pixel 2 -> bits 3,2 (0Ch)
;       pixel 3 -> bits 1,0 (03h)
;
; SCI color bits:
;   bit 0 = Blue
;   bit 1 = Green
;   bit 2 = Red
;   bit 3 = Intensity
;
; Intensity approximation:
;   One pixel of 0each doubled pair is forced white for colors 8-15.
;
; BUILD:
;   nasm -f bin -o QX11SCI.DRV QX11SCI.ASM
;
; NOTE:
;   This version builds one scanline worth of Blue/Red/Green bytes in
;   temporary buffers, then copies 0each whole buffer to VRAM. This avoids
;   changing ES for every generated QX byte. The pixel converter uses
;   precomputed 256-byte lookup tables, row copies use MOVSW where possible,
;   and cursor redraw is limited to rectangles that overlap the cursor.
; ============================================================================

[bits 16]
[cpu 8086]
[org 0]

SRC_BPR         equ 0A0h        ; 160 bytes per SCI source row
QX_BPR          equ 0100h       ; verified working-driver row pitch
QX_VISIBLE_BPR  equ 0050h       ; 80 visible bytes per row
QX_ROWS         equ 200

VIDEO_MONO      equ 0
VIDEO_COLOR     equ 1
BDA_VIDEO_MODE  equ 0049h
MONO_BPR        equ 0200h       ; next SCI source row / next pair of physical rows
MONO_SECOND_ROW equ 0100h       ; second physical line for same SCI source row
MONO_ROWS       equ 400

QX_BLUE_SEG     equ 08000h
QX_RED_SEG      equ 08008h
QX_GREEN_SEG    equ 09000h
MONO_BOTTOM_SEG equ 09000h       ; working 640x400 driver second 200-row bank

; QX-11 GAVDP display-origin registers (memory mapped through segment 8000h)
GAVDP_HORIGIN   equ 0C462h
GAVDP_VORIGIN   equ 0C663h
SHAKE_AMOUNT    equ 02h
SHAKE_REPEAT_X8 equ 1       ; expand SCI shake count to 8x more phases

; ============================================================================
; SCI DRIVER HEADER
; ============================================================================

entry:
        db      0E9h
        dw      dispatch - entry - 3

signature:
        db      00h,21h,43h,65h,87h,00h

driver_name:
        db      4,"qx11"

description:
        db      27,"Epson QX-11 Color/Mono SCI0"

call_tab:
        dw      get_color_depth         ; BP =  0
        dw      init_video_mode         ; BP =  2
        dw      restore_mode            ; BP =  4
        dw      update_rect             ; BP =  6
        dw      show_cursor             ; BP =  8
        dw      hide_cursor             ; BP = 10
        dw      move_cursor             ; BP = 12
        dw      load_cursor             ; BP = 14
        dw      shake_screen            ; BP = 16
        dw      scroll_rect             ; BP = 18

video_type     db      VIDEO_COLOR
cursor_counter  dw      0
cursor_x        dw      0
cursor_y        dw      0

; update_rect working variables. Driver calls are not expected to be reentrant.
rect_top        dw      0
rect_left       dw      0
rect_bottom     dw      0
rect_right      dw      0
fb_segment      dw      0
left_qx_byte    dw      0
width_qx_bytes  dw      0
rows_left       dw      0
src_row_offset  dw      0
dst_row_offset  dw      0

; One generated QX scanline per plane (maximum visible width = 80 bytes)
blue_row        times QX_VISIBLE_BPR db 0
red_row         times QX_VISIBLE_BPR db 0
green_row       times QX_VISIBLE_BPR db 0
mono_top_row    times QX_VISIBLE_BPR db 0
mono_bottom_row times QX_VISIBLE_BPR db 0

; SCI software cursor: 4-byte header + 16 AND words + 16 XOR words.
cursor_shape    times 68 db 0
pair_masks      db 0C0h,030h,00Ch,003h

; Table-driven SCI-byte to QX-plane conversion. 0Each source byte contains two
; SCI pixels. *_hi places them in destination bits 7..4; *_lo places them in
; bits 3..0. Intensity is already folded into every plane table.
blue_hi:
        db 00h,30h,00h,30h,00h,30h,00h,30h,10h,30h,10h,30h,10h,30h,10h,30h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 00h,30h,00h,30h,00h,30h,00h,30h,10h,30h,10h,30h,10h,30h,10h,30h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 00h,30h,00h,30h,00h,30h,00h,30h,10h,30h,10h,30h,10h,30h,10h,30h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 00h,30h,00h,30h,00h,30h,00h,30h,10h,30h,10h,30h,10h,30h,10h,30h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 40h,70h,40h,70h,40h,70h,40h,70h,50h,70h,50h,70h,50h,70h,50h,70h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 40h,70h,40h,70h,40h,70h,40h,70h,50h,70h,50h,70h,50h,70h,50h,70h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 40h,70h,40h,70h,40h,70h,40h,70h,50h,70h,50h,70h,50h,70h,50h,70h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
        db 40h,70h,40h,70h,40h,70h,40h,70h,50h,70h,50h,70h,50h,70h,50h,70h
        db 0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0C0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h,0D0h,0F0h
blue_lo:
        db 00h,03h,00h,03h,00h,03h,00h,03h,01h,03h,01h,03h,01h,03h,01h,03h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 00h,03h,00h,03h,00h,03h,00h,03h,01h,03h,01h,03h,01h,03h,01h,03h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 00h,03h,00h,03h,00h,03h,00h,03h,01h,03h,01h,03h,01h,03h,01h,03h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 00h,03h,00h,03h,00h,03h,00h,03h,01h,03h,01h,03h,01h,03h,01h,03h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 04h,07h,04h,07h,04h,07h,04h,07h,05h,07h,05h,07h,05h,07h,05h,07h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 04h,07h,04h,07h,04h,07h,04h,07h,05h,07h,05h,07h,05h,07h,05h,07h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 04h,07h,04h,07h,04h,07h,04h,07h,05h,07h,05h,07h,05h,07h,05h,07h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
        db 04h,07h,04h,07h,04h,07h,04h,07h,05h,07h,05h,07h,05h,07h,05h,07h
        db 0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Ch,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh,0Dh,0Fh
red_hi:
        db 00h,00h,00h,00h,30h,30h,30h,30h,10h,10h,10h,10h,30h,30h,30h,30h
        db 00h,00h,00h,00h,30h,30h,30h,30h,10h,10h,10h,10h,30h,30h,30h,30h
        db 00h,00h,00h,00h,30h,30h,30h,30h,10h,10h,10h,10h,30h,30h,30h,30h
        db 00h,00h,00h,00h,30h,30h,30h,30h,10h,10h,10h,10h,30h,30h,30h,30h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 40h,40h,40h,40h,70h,70h,70h,70h,50h,50h,50h,50h,70h,70h,70h,70h
        db 40h,40h,40h,40h,70h,70h,70h,70h,50h,50h,50h,50h,70h,70h,70h,70h
        db 40h,40h,40h,40h,70h,70h,70h,70h,50h,50h,50h,50h,70h,70h,70h,70h
        db 40h,40h,40h,40h,70h,70h,70h,70h,50h,50h,50h,50h,70h,70h,70h,70h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
        db 0C0h,0C0h,0C0h,0C0h,0F0h,0F0h,0F0h,0F0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h,0F0h,0F0h
red_lo:
        db 00h,00h,00h,00h,03h,03h,03h,03h,01h,01h,01h,01h,03h,03h,03h,03h
        db 00h,00h,00h,00h,03h,03h,03h,03h,01h,01h,01h,01h,03h,03h,03h,03h
        db 00h,00h,00h,00h,03h,03h,03h,03h,01h,01h,01h,01h,03h,03h,03h,03h
        db 00h,00h,00h,00h,03h,03h,03h,03h,01h,01h,01h,01h,03h,03h,03h,03h
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 04h,04h,04h,04h,07h,07h,07h,07h,05h,05h,05h,05h,07h,07h,07h,07h
        db 04h,04h,04h,04h,07h,07h,07h,07h,05h,05h,05h,05h,07h,07h,07h,07h
        db 04h,04h,04h,04h,07h,07h,07h,07h,05h,05h,05h,05h,07h,07h,07h,07h
        db 04h,04h,04h,04h,07h,07h,07h,07h,05h,05h,05h,05h,07h,07h,07h,07h
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
        db 0Ch,0Ch,0Ch,0Ch,0Fh,0Fh,0Fh,0Fh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh,0Fh,0Fh
green_hi:
        db 00h,00h,30h,30h,00h,00h,30h,30h,10h,10h,30h,30h,10h,10h,30h,30h
        db 00h,00h,30h,30h,00h,00h,30h,30h,10h,10h,30h,30h,10h,10h,30h,30h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 00h,00h,30h,30h,00h,00h,30h,30h,10h,10h,30h,30h,10h,10h,30h,30h
        db 00h,00h,30h,30h,00h,00h,30h,30h,10h,10h,30h,30h,10h,10h,30h,30h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 40h,40h,70h,70h,40h,40h,70h,70h,50h,50h,70h,70h,50h,50h,70h,70h
        db 40h,40h,70h,70h,40h,40h,70h,70h,50h,50h,70h,70h,50h,50h,70h,70h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 40h,40h,70h,70h,40h,40h,70h,70h,50h,50h,70h,70h,50h,50h,70h,70h
        db 40h,40h,70h,70h,40h,40h,70h,70h,50h,50h,70h,70h,50h,50h,70h,70h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
        db 0C0h,0C0h,0F0h,0F0h,0C0h,0C0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h,0D0h,0D0h,0F0h,0F0h
green_lo:
        db 00h,00h,03h,03h,00h,00h,03h,03h,01h,01h,03h,03h,01h,01h,03h,03h
        db 00h,00h,03h,03h,00h,00h,03h,03h,01h,01h,03h,03h,01h,01h,03h,03h
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 00h,00h,03h,03h,00h,00h,03h,03h,01h,01h,03h,03h,01h,01h,03h,03h
        db 00h,00h,03h,03h,00h,00h,03h,03h,01h,01h,03h,03h,01h,01h,03h,03h
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 04h,04h,07h,07h,04h,04h,07h,07h,05h,05h,07h,07h,05h,05h,07h,07h
        db 04h,04h,07h,07h,04h,04h,07h,07h,05h,05h,07h,07h,05h,05h,07h,07h
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 04h,04h,07h,07h,04h,04h,07h,07h,05h,05h,07h,07h,05h,05h,07h,07h
        db 04h,04h,07h,07h,04h,04h,07h,07h,05h,05h,07h,07h,05h,05h,07h,07h
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh
        db 0Ch,0Ch,0Fh,0Fh,0Ch,0Ch,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh,0Dh,0Dh,0Fh,0Fh


; 2x2 ordered-dither lookup tables for monochrome mode.
; Each packed SCI byte contributes four output bits: two physical pixels for
; each of its two SCI pixels. HI tables target bits 7..4, LO bits 3..0.
mono_top_hi:
        db 00h,20h,20h,20h,20h,20h,20h,30h,20h,20h,30h,30h,20h,30h,30h,30h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
        db 80h,0A0h,0A0h,0A0h,0A0h,0A0h,0A0h,0B0h,0A0h,0A0h,0B0h,0B0h,0A0h,0B0h,0B0h,0B0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
        db 0C0h,0E0h,0E0h,0E0h,0E0h,0E0h,0E0h,0F0h,0E0h,0E0h,0F0h,0F0h,0E0h,0F0h,0F0h,0F0h
mono_bottom_hi:
        db 00h,00h,10h,10h,00h,10h,10h,10h,00h,10h,10h,10h,10h,10h,30h,30h
        db 00h,00h,10h,10h,00h,10h,10h,10h,00h,10h,10h,10h,10h,10h,30h,30h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 00h,00h,10h,10h,00h,10h,10h,10h,00h,10h,10h,10h,10h,10h,30h,30h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 00h,00h,10h,10h,00h,10h,10h,10h,00h,10h,10h,10h,10h,10h,30h,30h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 40h,40h,50h,50h,40h,50h,50h,50h,40h,50h,50h,50h,50h,50h,70h,70h
        db 0C0h,0C0h,0D0h,0D0h,0C0h,0D0h,0D0h,0D0h,0C0h,0D0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h
        db 0C0h,0C0h,0D0h,0D0h,0C0h,0D0h,0D0h,0D0h,0C0h,0D0h,0D0h,0D0h,0D0h,0D0h,0F0h,0F0h
mono_top_lo:
        db 00h,02h,02h,02h,02h,02h,02h,03h,02h,02h,03h,03h,02h,03h,03h,03h
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
        db 08h,0Ah,0Ah,0Ah,0Ah,0Ah,0Ah,0Bh,0Ah,0Ah,0Bh,0Bh,0Ah,0Bh,0Bh,0Bh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
        db 0Ch,0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Eh,0Eh,0Fh,0Fh,0Eh,0Fh,0Fh,0Fh
mono_bottom_lo:
        db 00h,00h,01h,01h,00h,01h,01h,01h,00h,01h,01h,01h,01h,01h,03h,03h
        db 00h,00h,01h,01h,00h,01h,01h,01h,00h,01h,01h,01h,01h,01h,03h,03h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 00h,00h,01h,01h,00h,01h,01h,01h,00h,01h,01h,01h,01h,01h,03h,03h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 00h,00h,01h,01h,00h,01h,01h,01h,00h,01h,01h,01h,01h,01h,03h,03h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 04h,04h,05h,05h,04h,05h,05h,05h,04h,05h,05h,05h,05h,05h,07h,07h
        db 0Ch,0Ch,0Dh,0Dh,0Ch,0Dh,0Dh,0Dh,0Ch,0Dh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh
        db 0Ch,0Ch,0Dh,0Dh,0Ch,0Dh,0Dh,0Dh,0Ch,0Dh,0Dh,0Dh,0Dh,0Dh,0Fh,0Fh

; Saved QX bytes beneath cursor. A 16-pixel SCI cursor becomes 32 QX pixels
; and can span at most five QX bytes when X is not four-pixel aligned.
cursor_saved       db 0
cursor_redraw_after_update db 0
cursor_save_width  dw 0
cursor_save_rows   dw 0
cursor_save_xbyte  dw 0
cursor_save_y      dw 0
cursor_bg_blue     times 80 db 0
cursor_bg_red      times 80 db 0
cursor_bg_green    times 80 db 0
cursor_bg_mono     times 160 db 0

; ============================================================================
; DISPATCH
; ============================================================================

dispatch:
        push    es
        push    ds
        push    cs
        pop     ds
        call    [cs:call_tab+bp]
        pop     ds
        pop     es
        retf

; ============================================================================
; VIDEO MODE FUNCTIONS
; ============================================================================

get_color_depth:
        ; Match the known-good Hercules-derived QX driver exactly.
        ; SCI expects this driver class/value, not the literal number of colors.
        mov     ax,2
        ret

; Requests BIOS mode 07h. On the QX-11 color configuration, BIOS selects the
; native 640x200 color mode used by the proven Hercules-derived driver.
; Returns AX = previous BIOS mode number, matching the SCI driver convention.
init_video_mode:
        mov     ah,0Fh
        int     10h
        push    ax

        mov     ax,0007h
        int     10h

        ; Match the known-good driver initialization exactly.
        ; INT 10h/AH=01h, CX=2000h hides the text cursor and is part of
        ; the verified mode-2 setup sequence.
        mov     ah,01h
        mov     cx,2000h
        int     10h

        call    detect_qx_video
        call    clear_screen

        pop     ax
        xor     ah,ah
        ret

detect_qx_video:
        push    ax
        push    es
        mov     ax,0040h
        mov     es,ax
        cmp     byte [es:BDA_VIDEO_MODE],07h
        je      .mono
        mov     byte [cs:video_type],VIDEO_COLOR
        jmp     .done
.mono:
        mov     byte [cs:video_type],VIDEO_MONO
.done:
        pop     es
        pop     ax
        ret

restore_mode:
        xor     ah,ah
        int     10h
        ret

; Clear only the 80 visible bytes of 0each 256-byte row in 0each plane.
; The verified working driver uses DI = Y*0100h + Xbyte.  Clearing a large
; contiguous block would overwrite neighboring row/plane areas.
clear_screen:
        cmp     byte [cs:video_type],VIDEO_MONO
        je      clear_screen_mono
        jmp     clear_screen_color

clear_screen_color:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es

        cld
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

clear_screen_mono:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        push    es
        cld
        xor     bx,bx                  ; local source row within bank, 0..99
        mov     dx,QX_BLUE_SEG
.bank:
        mov     es,dx
        xor     bx,bx
.row:
        mov     ax,bx
        shl     ax,1
        mov     ah,al
        xor     al,al                  ; AX = local_y * 0200h
        mov     di,ax
        xor     ax,ax
        mov     cx,QX_VISIBLE_BPR/2
        rep     stosw
        ; rebuild pair base because STOSW advanced DI
        mov     ax,bx
        shl     ax,1
        mov     ah,al
        xor     al,al
        mov     di,ax
        add     di,MONO_SECOND_ROW
        xor     ax,ax
        mov     cx,QX_VISIBLE_BPR/2
        rep     stosw
        inc     bx
        cmp     bx,100
        jb      .row
        cmp     dx,QX_BLUE_SEG
        jne     .done
        mov     dx,MONO_BOTTOM_SEG
        jmp     .bank
.done:
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; BX = plane segment
clear_plane:
        mov     es,bx
        xor     di,di
        mov     dx,QX_ROWS
        xor     ax,ax
.row:
        mov     cx,QX_VISIBLE_BPR/2
        rep     stosw
        add     di,QX_BPR-QX_VISIBLE_BPR
        dec     dx
        jnz     .row
        ret

; ============================================================================
; UPDATE_RECT
; ============================================================================
; Parameters:
;   AX = top Y
;   BX = left X
;   CX = bottom Y
;   DX = right X
;   SI = SCI framebuffer segment
;
; The horizontal rectangle is expanded to a four-SCI-pixel boundary because
; four source pixels become exactly one byte in 0each QX plane.
; ============================================================================

update_rect:
        cmp     byte [cs:video_type],VIDEO_MONO
        je      update_rect_mono
        jmp     update_rect_color

update_rect_color:
        ; DS = CS on entry from dispatch, so save parameters before changing DS.
        mov     [rect_top],ax
        mov     [rect_left],bx
        mov     [rect_bottom],cx
        mov     [rect_right],dx
        mov     [fb_segment],si

        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        cld

        ; A visible software cursor must be removed before SCI redraws VRAM.
        ; Otherwise the saved background becomes stale and hide/move can erase
        ; menus or dialogs drawn beneath the cursor. The visibility counter is
        ; intentionally left unchanged.
        mov     byte [cs:cursor_redraw_after_update],0
        cmp     word [cs:cursor_counter],0
        jle     .cursor_removed
        cmp     byte [cs:cursor_saved],0
        je      .cursor_removed

        ; Remove/redraw the cursor only when this dirty rectangle intersects
        ; the 16x16 cursor rectangle in SCI coordinates.
        mov     ax,[cs:rect_right]
        cmp     ax,[cs:cursor_x]
        jb      .cursor_removed
        mov     ax,[cs:cursor_x]
        add     ax,15
        cmp     [cs:rect_left],ax
        ja      .cursor_removed
        mov     ax,[cs:rect_bottom]
        cmp     ax,[cs:cursor_y]
        jb      .cursor_removed
        mov     ax,[cs:cursor_y]
        add     ax,15
        cmp     [cs:rect_top],ax
        ja      .cursor_removed

        call    cursor_restore_background
        mov     byte [cs:cursor_redraw_after_update],1
.cursor_removed:

        ; left_qx_byte = floor(left / 4)
        mov     ax,[cs:rect_left]
        shr     ax,1
        shr     ax,1
        mov     [cs:left_qx_byte],ax

        ; right byte = ceil(right / 4), preserving the working PC1 semantics.
        mov     dx,[cs:rect_right]
        add     dx,3
        shr     dx,1
        shr     dx,1

        ; width in QX bytes
        sub     dx,ax
        mov     [cs:width_qx_bytes],dx
        or      dx,dx
        jz      .done

        ; rows_left = bottom - top + 1
        mov     cx,[cs:rect_bottom]
        sub     cx,[cs:rect_top]
        inc     cx
        jz      .done
        mov     [cs:rows_left],cx

        ; Source offset = top * 160 + (left_qx_byte * 2).
        ; Avoid slow 8088 MUL: 160 = 128 + 32.
        mov     ax,[cs:rect_top]
        mov     dx,ax
        shl     ax,1               ; *2
        shl     ax,1               ; *4
        shl     ax,1               ; *8
        shl     ax,1               ; *16
        shl     ax,1               ; *32
        shl     dx,1               ; *2
        shl     dx,1               ; *4
        shl     dx,1               ; *8
        shl     dx,1               ; *16
        shl     dx,1               ; *32
        shl     dx,1               ; *64
        shl     dx,1               ; *128
        add     ax,dx
        mov     bx,[cs:left_qx_byte]
        add     bx,bx
        add     ax,bx
        mov     [cs:src_row_offset],ax

        ; Destination = Y*0100h + QX byte X. Y is 0..199, so form Y*256
        ; directly by placing Y in AH.
        mov     ax,[cs:rect_top]
        mov     ah,al
        xor     al,al
        add     ax,[cs:left_qx_byte]
        mov     [cs:dst_row_offset],ax

        ; DS becomes the SCI framebuffer segment.
        mov     ax,[cs:fb_segment]
        mov     ds,ax

.y_loop:
        mov     si,[cs:src_row_offset]
        mov     cx,[cs:width_qx_bytes]
        xor     bp,bp              ; buffer index within blue/red/green rows

.x_loop:
        ; Two SCI bytes contain four pixels. Tables directly create the upper
        ; and lower halves of the QX byte for all three planes, including the
        ; pseudo-intensity white-pixel pattern.
        lodsw
        mov     di,ax              ; preserve both packed source bytes

        xor     bh,bh
        mov     bl,al
        mov     dl,[cs:blue_hi+bx]
        mov     dh,[cs:red_hi+bx]
        mov     al,[cs:green_hi+bx]

        mov     bx,di
        mov     bl,bh              ; index = second source byte
        xor     bh,bh
        or      dl,[cs:blue_lo+bx]
        or      dh,[cs:red_lo+bx]
        or      al,[cs:green_lo+bx]

        mov     [cs:blue_row+bp],dl
        mov     [cs:red_row+bp],dh
        mov     [cs:green_row+bp],al

        inc     bp
        dec     cx
        jz      .x_done
        jmp     .x_loop
.x_done:

        ; Copy buffered row to the three QX planes.
        ; DS currently points to the SCI framebuffer; temporarily switch DS to
        ; CS so REP MOVSB reads from the row buffers.
        push    ds
        push    cs
        pop     ds

        mov     di,[cs:dst_row_offset]
        mov     si,blue_row
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        mov     cx,[cs:width_qx_bytes]
        rep     movsb

        mov     di,[cs:dst_row_offset]
        mov     si,red_row
        mov     ax,QX_RED_SEG
        mov     es,ax
        mov     cx,[cs:width_qx_bytes]
        rep     movsb

        mov     di,[cs:dst_row_offset]
        mov     si,green_row
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        mov     cx,[cs:width_qx_bytes]
        rep     movsb

        pop     ds

        add     word [cs:src_row_offset],SRC_BPR
        add     word [cs:dst_row_offset],QX_BPR ; next row: +0100h
        dec     word [cs:rows_left]
        jnz     .y_loop

.done:
        ; If update_rect removed a visible cursor, capture the newly rendered
        ; background and draw the cursor again without changing nesting state.
        cmp     byte [cs:cursor_redraw_after_update],0
        je      .no_cursor_redraw
        mov     byte [cs:cursor_redraw_after_update],0
        call    cursor_save_background
        call    cursor_draw
.no_cursor_redraw:
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

; ============================================================================
; UPDATE_RECT_MONO - 320x200 SCI color framebuffer to 640x400 monochrome
; Ordered 2x2 dithering: every SCI pixel becomes a 2x2 monochrome cell.
; QX physical row pair for source Y is at Y*0200h and Y*0200h+0100h.
; ============================================================================
update_rect_mono:
        mov     [rect_top],ax
        mov     [rect_left],bx
        mov     [rect_bottom],cx
        mov     [rect_right],dx
        mov     [fb_segment],si

        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        cld

        mov     byte [cs:cursor_redraw_after_update],0
        cmp     word [cs:cursor_counter],0
        jle     .cursor_removed
        cmp     byte [cs:cursor_saved],0
        je      .cursor_removed
        mov     ax,[cs:rect_right]
        cmp     ax,[cs:cursor_x]
        jb      .cursor_removed
        mov     ax,[cs:cursor_x]
        add     ax,15
        cmp     [cs:rect_left],ax
        ja      .cursor_removed
        mov     ax,[cs:rect_bottom]
        cmp     ax,[cs:cursor_y]
        jb      .cursor_removed
        mov     ax,[cs:cursor_y]
        add     ax,15
        cmp     [cs:rect_top],ax
        ja      .cursor_removed
        call    cursor_restore_background
        mov     byte [cs:cursor_redraw_after_update],1
.cursor_removed:

        mov     ax,[cs:rect_left]
        shr     ax,1
        shr     ax,1
        mov     [cs:left_qx_byte],ax
        mov     dx,[cs:rect_right]
        add     dx,3
        shr     dx,1
        shr     dx,1
        sub     dx,ax
        mov     [cs:width_qx_bytes],dx
        or      dx,dx
        jz      .done

        mov     cx,[cs:rect_bottom]
        sub     cx,[cs:rect_top]
        inc     cx
        jz      .done
        mov     [cs:rows_left],cx

        ; source = top*160 + left_byte*2
        mov     ax,[cs:rect_top]
        mov     dx,ax
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     dx,1
        shl     dx,1
        shl     dx,1
        shl     dx,1
        shl     dx,1
        shl     dx,1
        shl     dx,1
        add     ax,dx
        mov     bx,[cs:left_qx_byte]
        add     bx,bx
        add     ax,bx
        mov     [cs:src_row_offset],ax

        mov     ax,[cs:fb_segment]
        mov     ds,ax
.y_loop:
        mov     si,[cs:src_row_offset]
        mov     cx,[cs:width_qx_bytes]
        xor     bp,bp
.x_loop:
        lodsw
        mov     di,ax
        xor     bh,bh
        mov     bl,al
        mov     dl,[cs:mono_top_hi+bx]
        mov     dh,[cs:mono_bottom_hi+bx]
        mov     bx,di
        mov     bl,bh
        xor     bh,bh
        or      dl,[cs:mono_top_lo+bx]
        or      dh,[cs:mono_bottom_lo+bx]
        mov     [cs:mono_top_row+bp],dl
        mov     [cs:mono_bottom_row+bp],dh
        inc     bp
        loop    .x_loop

        push    ds
        push    cs
        pop     ds

        ; Exact geometry used by the working 640x400 binary:
        ; SCI Y 0..99   -> ES=8000h, local_y=Y
        ; SCI Y 100..199-> ES=9000h, local_y=Y-100
        ; pair base = local_y*0200h + Xbyte
        mov     ax,[cs:rect_top]
        mov     bx,[cs:left_qx_byte]
        call    mono_pair_address

        push    di
        mov     si,mono_top_row
        mov     cx,[cs:width_qx_bytes]
        rep     movsb
        pop     di
        add     di,MONO_SECOND_ROW
        mov     si,mono_bottom_row
        mov     cx,[cs:width_qx_bytes]
        rep     movsb
        pop     ds

        add     word [cs:src_row_offset],SRC_BPR
        inc     word [cs:rect_top]
        dec     word [cs:rows_left]
        jnz     .y_loop
.done:
        cmp     byte [cs:cursor_redraw_after_update],0
        je      .no_cursor_redraw
        mov     byte [cs:cursor_redraw_after_update],0
        call    cursor_save_background
        call    cursor_draw
.no_cursor_redraw:
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

; ============================================================================
; SOFTWARE CURSOR
; ============================================================================
; SCI cursor format copied by load_cursor:
;   2 header words, 16 AND-mask words, 16 XOR-mask words.
; The cursor is 16x16 in SCI coordinates. 0Each cursor pixel is doubled
; horizontally to match the QX 640x200 display. The background bytes from all
; three color planes are saved before drawing and restored when hidden/moved.

show_cursor:
        inc     word [cursor_counter]
        mov     ax,[cursor_counter]
        cmp     ax,1
        jne     .done
        pushf
        cli
        call    cursor_save_background
        call    cursor_draw
        popf
.done:
        mov     ax,[cursor_counter]
        ret

hide_cursor:
        cmp     word [cursor_counter],0
        je      .done
        dec     word [cursor_counter]
        cmp     word [cursor_counter],0
        jne     .done
        pushf
        cli
        call    cursor_restore_background
        popf
.done:
        mov     ax,[cursor_counter]
        ret

move_cursor:
        ; SCI may report the same position repeatedly. Avoid a full three-plane
        ; restore/save/redraw when nothing moved.
        cmp     ax,[cs:cursor_x]
        jne     .position_changed
        cmp     bx,[cs:cursor_y]
        je      .done
.position_changed:
        push    ax
        push    bx
        pushf
        cli
        cmp     word [cs:cursor_counter],0
        jle     .store_position
        call    cursor_restore_background
.store_position:
        popf
        pop     bx
        pop     ax
        mov     [cs:cursor_x],ax
        mov     [cs:cursor_y],bx
        cmp     word [cs:cursor_counter],0
        jle     .done
        pushf
        cli
        call    cursor_save_background
        call    cursor_draw
        popf
.done:
        ret

load_cursor:
        ; AX:BX points to 68-byte SCI cursor definition. If visible, restore the
        ; old cursor first, replace the shape, then redraw with the new shape.
        push    ds
        push    si
        push    di
        push    cx
        push    es
        pushf
        cli

        cmp     word [cs:cursor_counter],0
        jle     .copy_shape
        call    cursor_restore_background

.copy_shape:
        mov     ds,ax
        mov     si,bx
        push    cs
        pop     es
        mov     di,cursor_shape
        mov     cx,68
        cld
        rep     movsb

        cmp     word [cs:cursor_counter],0
        jle     .copied
        call    cursor_save_background
        call    cursor_draw
.copied:
        popf
        pop     es
        pop     cx
        pop     di
        pop     si
        pop     ds
        mov     ax,[cs:cursor_counter]
        ret

; Save the rectangular QX-byte area covered by the cursor.
cursor_save_background:
        cmp     byte [cs:video_type],VIDEO_MONO
        je      cursor_save_background_mono
        jmp     cursor_save_background_color

cursor_save_background_color:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es

        ; start byte = X / 4
        mov     ax,[cs:cursor_x]
        cmp     ax,320
        jae     .nothing
        mov     bx,ax
        shr     bx,1
        shr     bx,1
        mov     [cs:cursor_save_xbyte],bx

        ; end byte = ceil(min(X+16,320)/4)
        add     ax,16
        cmp     ax,320
        jbe     .end_x_ok
        mov     ax,320
.end_x_ok:
        add     ax,3
        shr     ax,1
        shr     ax,1
        sub     ax,bx
        mov     [cs:cursor_save_width],ax
        or      ax,ax
        jz      .nothing

        ; visible rows = min(16,200-Y)
        mov     ax,[cs:cursor_y]
        cmp     ax,200
        jae     .nothing
        mov     [cs:cursor_save_y],ax
        mov     dx,200
        sub     dx,ax
        cmp     dx,16
        jbe     .rows_ok
        mov     dx,16
.rows_ok:
        mov     [cs:cursor_save_rows],dx

        ; DI = Y*100h + start byte
        mov     ah,al
        xor     al,al
        add     ax,bx
        mov     di,ax

        mov     ax,QX_BLUE_SEG
        mov     si,cursor_bg_blue
        call    cursor_copy_from_plane
        mov     ax,QX_RED_SEG
        mov     si,cursor_bg_red
        call    cursor_copy_from_plane
        mov     ax,QX_GREEN_SEG
        mov     si,cursor_bg_green
        call    cursor_copy_from_plane

        mov     byte [cs:cursor_saved],1
        jmp     .done
.nothing:
        mov     byte [cs:cursor_saved],0
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

; AX = plane segment, SI = CS buffer, DI = first QX byte.
cursor_copy_from_plane:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        mov     es,ax
        mov     dx,[cs:cursor_save_rows]
.row:
        mov     cx,[cs:cursor_save_width]
.byte:
        mov     al,[es:di]
        mov     [cs:si],al
        inc     si
        inc     di
        loop    .byte
        sub     di,[cs:cursor_save_width]
        add     di,QX_BPR
        dec     dx
        jnz     .row
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; Restore all saved bytes to the three planes.
cursor_restore_background:
        cmp     byte [cs:video_type],VIDEO_MONO
        je      cursor_restore_background_mono
        jmp     cursor_restore_background_color

cursor_restore_background_color:
        cmp     byte [cs:cursor_saved],0
        je      .done
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es

        mov     ax,[cs:cursor_save_y]
        mov     ah,al
        xor     al,al
        add     ax,[cs:cursor_save_xbyte]
        mov     di,ax

        mov     ax,QX_BLUE_SEG
        mov     si,cursor_bg_blue
        call    cursor_copy_to_plane
        mov     ax,QX_RED_SEG
        mov     si,cursor_bg_red
        call    cursor_copy_to_plane
        mov     ax,QX_GREEN_SEG
        mov     si,cursor_bg_green
        call    cursor_copy_to_plane

        mov     byte [cs:cursor_saved],0
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

; AX = plane segment, SI = CS buffer, DI = first QX byte.
cursor_copy_to_plane:
        push    ax
        push    cx
        push    dx
        push    di
        mov     es,ax
        mov     dx,[cs:cursor_save_rows]
.row:
        mov     cx,[cs:cursor_save_width]
.byte:
        mov     al,[cs:si]
        mov     [es:di],al
        inc     si
        inc     di
        loop    .byte
        sub     di,[cs:cursor_save_width]
        add     di,QX_BPR
        dec     dx
        jnz     .row
        pop     di
        pop     dx
        pop     cx
        pop     ax
        ret

; Draw SCI AND/XOR cursor into all three QX color planes.
cursor_draw:
        cmp     byte [cs:video_type],VIDEO_MONO
        je      cursor_draw_mono
        jmp     cursor_draw_color

cursor_draw_color:
        cmp     byte [cs:cursor_saved],0
        je      .done
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds

        xor     bp,bp                  ; cursor row 0..15
.row_loop:
        cmp     bp,[cursor_save_rows]
        jae     .draw_done

        mov     si,bp
        shl     si,1
        mov     bx,[cursor_shape+4+si]   ; AND word
        mov     dx,[cursor_shape+36+si]  ; XOR word
        xor     si,si                    ; cursor column 0..15

.col_loop:
        cmp     si,16
        jae     .next_row
        mov     ax,[cursor_x]
        add     ax,si
        cmp     ax,320
        jae     .shift_masks

        ; DI = (cursor_y+row)*100h + (X/4)
        mov     cx,ax
        shr     cx,1
        shr     cx,1
        mov     ax,[cursor_y]
        add     ax,bp
        mov     ah,al
        xor     al,al
        add     ax,cx
        mov     di,ax

        ; AL = doubled-pixel bit mask C0,30,0C,03.
        mov     ax,[cursor_x]
        add     ax,si
        and     ax,3
        mov     cx,ax
        push    bx
        mov     bx,cx
        mov     al,[pair_masks+bx]
        pop     bx

        ; Standard SCI cursor operation per plane:
        ; screen = (screen AND ANDmask) XOR XORmask.
        test    bx,8000h
        jnz     .and_preserve
        call    cursor_clear_pair
.and_preserve:
        test    dx,8000h
        jz      .shift_masks
        call    cursor_xor_pair

.shift_masks:
        shl     bx,1
        shl     dx,1
        inc     si
        jmp     .col_loop

.next_row:
        inc     bp
        jmp     .row_loop

.draw_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

; AL = pair mask, DI = QX byte offset. Clear pair in every plane.
cursor_clear_pair:
        push    ax
        push    bx
        push    es
        mov     bl,al
        not     bl
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        and     [es:di],bl
        mov     ax,QX_RED_SEG
        mov     es,ax
        and     [es:di],bl
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        and     [es:di],bl
        pop     es
        pop     bx
        pop     ax
        ret

; AL = pair mask, DI = QX byte offset. XOR pair in every plane.
cursor_xor_pair:
        push    ax
        push    bx
        push    es
        mov     bl,al
        mov     ax,QX_BLUE_SEG
        mov     es,ax
        xor     [es:di],bl
        mov     ax,QX_RED_SEG
        mov     es,ax
        xor     [es:di],bl
        mov     ax,QX_GREEN_SEG
        mov     es,ax
        xor     [es:di],bl
        pop     es
        pop     bx
        pop     ax
        ret

; ============================================================================
; MONOCHROME CURSOR SUPPORT
; ============================================================================
cursor_save_background_mono:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es

        mov     ax,[cs:cursor_x]
        cmp     ax,320
        jae     .nothing
        mov     bx,ax
        shr     bx,1
        shr     bx,1
        mov     [cs:cursor_save_xbyte],bx
        add     ax,16
        cmp     ax,320
        jbe     .xok
        mov     ax,320
.xok:
        add     ax,3
        shr     ax,1
        shr     ax,1
        sub     ax,bx
        mov     [cs:cursor_save_width],ax
        or      ax,ax
        jz      .nothing

        mov     ax,[cs:cursor_y]
        cmp     ax,200
        jae     .nothing
        mov     [cs:cursor_save_y],ax
        mov     dx,200
        sub     dx,ax
        cmp     dx,16
        jbe     .rowsok
        mov     dx,16
.rowsok:
        mov     [cs:cursor_save_rows],dx ; SCI rows, each saves two physical rows
        mov     si,cursor_bg_mono
        xor     bp,bp
.row:
        mov     ax,[cs:cursor_save_y]
        add     ax,bp
        mov     bx,[cs:cursor_save_xbyte]
        call    mono_pair_address
        push    di
        mov     cx,[cs:cursor_save_width]
.topbyte:
        mov     al,[es:di]
        mov     [cs:si],al
        inc     si
        inc     di
        loop    .topbyte
        pop     di
        add     di,MONO_SECOND_ROW
        mov     cx,[cs:cursor_save_width]
.botbyte:
        mov     al,[es:di]
        mov     [cs:si],al
        inc     si
        inc     di
        loop    .botbyte
        inc     bp
        cmp     bp,[cs:cursor_save_rows]
        jb      .row
        mov     byte [cs:cursor_saved],1
        jmp     .done
.nothing:
        mov     byte [cs:cursor_saved],0
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

cursor_restore_background_mono:
        cmp     byte [cs:cursor_saved],0
        je      .done
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        mov     si,cursor_bg_mono
        xor     bp,bp
.row:
        mov     ax,[cs:cursor_save_y]
        add     ax,bp
        mov     bx,[cs:cursor_save_xbyte]
        call    mono_pair_address
        push    di
        mov     cx,[cs:cursor_save_width]
.topbyte:
        mov     al,[cs:si]
        mov     [es:di],al
        inc     si
        inc     di
        loop    .topbyte
        pop     di
        add     di,MONO_SECOND_ROW
        mov     cx,[cs:cursor_save_width]
.botbyte:
        mov     al,[cs:si]
        mov     [es:di],al
        inc     si
        inc     di
        loop    .botbyte
        inc     bp
        cmp     bp,[cs:cursor_save_rows]
        jb      .row
        mov     byte [cs:cursor_saved],0
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

cursor_draw_mono:
        cmp     byte [cs:cursor_saved],0
        je      .done
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        xor     bp,bp
.row_loop:
        cmp     bp,[cs:cursor_save_rows]
        jae     .draw_done
        mov     si,bp
        shl     si,1
        mov     bx,[cs:cursor_shape+4+si]
        mov     dx,[cs:cursor_shape+36+si]
        push    bx
        mov     ax,[cs:cursor_y]
        add     ax,bp
        mov     bx,[cs:cursor_save_xbyte]
        call    mono_pair_address
        pop     bx
        xor     si,si
.col_loop:
        cmp     si,16
        jae     .next_row
        mov     ax,[cs:cursor_x]
        add     ax,si
        cmp     ax,320
        jae     .shift
        mov     cx,ax
        shr     cx,1
        shr     cx,1
        sub     cx,[cs:cursor_save_xbyte]
        push    di
        add     di,cx
        mov     ax,[cs:cursor_x]
        add     ax,si
        and     ax,3
        mov     cx,ax
        push    bx
        mov     bx,cx
        mov     al,[cs:pair_masks+bx]
        pop     bx
        mov     cl,al
        not     cl
        test    bx,8000h
        jnz     .preserve
        and     [es:di],cl
        and     [es:di+MONO_SECOND_ROW],cl
.preserve:
        test    dx,8000h
        jz      .restore_di
        xor     [es:di],al
        xor     [es:di+MONO_SECOND_ROW],al
.restore_di:
        pop     di
.shift:
        shl     bx,1
        shl     dx,1
        inc     si
        jmp     .col_loop
.next_row:
        inc     bp
        jmp     .row_loop
.draw_done:
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.done:
        ret

; AX = SCI source Y (0..199), BX = QX X byte.
; Returns ES:DI at the first physical row of the 2-row pair.
; This exactly matches the working native 640x400 binary driver.
mono_pair_address:
        push    ax
        push    dx
        cmp     ax,100
        jb      .top_bank
        sub     ax,100
        mov     dx,MONO_BOTTOM_SEG
        jmp     .make_offset
.top_bank:
        mov     dx,QX_BLUE_SEG
.make_offset:
        shl     ax,1
        mov     ah,al
        xor     al,al                  ; AX = local_y * 0200h
        add     ax,bx
        mov     di,ax
        mov     es,dx
        pop     dx
        pop     ax
        ret

; ============================================================================
; SHAKE_SCREEN - QX-11 GAVDP display-origin shake
; ============================================================================
; SCI parameters (same convention used by the reference driver):
;   AX:BX = address of a changing timer-tick byte/word
;   CX    = number of shake phases
;   DL    = direction mask (zero means no shake)
;
; Mode 2 normally uses horizontal and vertical origins of 00h. The routine
; alternates between origin 00h and a small offset, waits for the next supplied
; timer tick, and always restores both origins to zero before returning.
; Because the GAVDP registers are effectively write-only, no readback is used.
shake_screen:
        test    dl,dl
        jnz     .shake_dir_ok
        jmp     .shake_done
.shake_dir_ok:
        or      cx,cx
        jnz     .shake_count_ok
        jmp     .shake_done
.shake_count_ok:

        push    ax
        push    bx
        push    cx
        push    dx
        push    es
        push    bp

        ; SCI often requests only a very small shake count. Expand it to eight
        ; times as many origin toggles so the effect lasts long enough to see.
        ; Three one-bit shifts are 8088-compatible and implement CX *= 8.
        shl     cx,1
        shl     cx,1
        shl     cx,1

        mov     es,ax                   ; ES:BX -> SCI timer tick
        mov     ax,QX_BLUE_SEG          ; memory-mapped GAVDP register segment
        mov     bp,ax
        xor     dh,dh                   ; phase: 0 = normal, 1 = shifted

.shake_loop:
        mov     ax,bp
        push    es
        mov     es,ax

        xor     al,al
        test    dh,1
        jz      .write_origins
        mov     al,SHAKE_AMOUNT

.write_origins:
        ; Apply both axes for a compact diagonal/up-down shake. Small values
        ; avoid the half-screen effects associated with high horizontal bits.
        mov     [es:GAVDP_VORIGIN],al
        mov     [es:GAVDP_HORIGIN],al
        pop     es

        xor     dh,1

        ; Synchronize 0each phase to the timer location supplied by SCI.
        mov     al,[es:bx]
.wait_tick:
        cmp     al,[es:bx]
        je      .wait_tick

        loop    .shake_loop

        ; Always restore the normal mode-2 origins.
        push    es
        mov     ax,bp
        mov     es,ax
        xor     al,al
        mov     [es:GAVDP_VORIGIN],al
        mov     [es:GAVDP_HORIGIN],al
        pop     es

        pop     bp
        pop     es
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.shake_done:
        ret

; SCI scroll delegates to rectangle redraw.
; Parameters: DI = framebuffer segment, rectangle registers as update_rect.
scroll_rect:
        mov     si,di
        jmp     update_rect

; End of driver
