bits 16
cpu 8086
org 100h

; Epson QX-11 640x400 monochrome chessboard with interactive movement.
;
; Controls:
;   Arrow keys move the selection frame
;   Enter selects one of the current player's pieces and shows legal moves
;   Arrow keys move the frame to a marked destination
;   Enter completes a legal move; an opponent at the destination is captured
;   A destination occupied by the current player's own piece is rejected
;   Enter on the selected source square cancels the pending move
;   Esc opens the centered PAUSE / RESTART / QUIT menu
;   H requests and displays a written move hint during White's turn
;
; White moves first and remains human-controlled. Black is controlled by the
; Phase-6 local computer opponent: it tries a multi-ply opening library,
; completes a positional two-ply search, then attempts a third ply in which
; Black searches its strongest continuation after every White reply.
; Iterative deepening preserves the completed two-ply result if the RTC search
; deadline interrupts depth three. Tactical root moves (promotions, valuable
; captures, other captures, and checks) are ordered ahead of quiet moves.
; Alpha-beta cutoffs skip branches that cannot change the selected move.
; A five-second minimum RTC-driven thinking interval makes the
; computer turn visible while Black's chess clock continues to run. The
; upper-left margin beside the board shows either WHITE TURN or BLACK TURN,
; with CHECK below it whenever the side to move is currently attacked.
;
; This stage enforces legal movement for every piece, including blocked
; sliding paths, ordinary pawn movement/captures, and king safety. Candidate
; moves that leave the moving player's king attacked are excluded. After each
; move, every legal reply is searched. CHECKMATE is announced when the checked
; side has no reply; STALEMATE is announced when a safe side has no reply.
; Board input stops after either result, while Esc remains available.
; Files A-H and ranks 8-1 are labeled on all four sides of the board.
; The right margin displays the eight most recent half-moves. A 256-entry
; circular move history records source, destination, mover, capture, special
; flags, prior castling/en-passant state, and the chosen promotion piece.
;
; All three special move rules are implemented:
;   Promotion waits for Q/R/B/N and supports underpromotion.
;   Castling tracks permanent rights and checks start/transit/destination.
;   En passant is available only immediately after a pawn double-step.
;
; Final normal-game build with target-centered king-attack detection.
;
; Phase-6 engine revision of the hardware-confirmed detailed-piece layout.
; Light board squares use an alternating AAh/55h dither instead of a solid
; fill. Piece rendering is opaque: a solid silhouette mask removes the board
; texture beneath each piece before the selected detailed artwork is painted.
; Leaf evaluation combines material with compact piece-square tables. A
; bounded two-ply capture quiescence pass stabilizes third-ply tactical leaves,
; and reversal of Black's preceding move receives an anti-repetition penalty.
; Phase 6 II keeps the Phase-6 chess engine unchanged and revises the user
; interface: a centered large ESC menu offers PAUSE, RESTART, and QUIT; H is a
; direct hint key; the suggested move is written beside the board and marked
; with a stronger double frame; startup includes a title/credit screen and an
; original short PSG tune; and exit restores BIOS video mode 07h before DOS.
;
; Build:
;   nasm -f bin QX11_CHESS_COMPUTER_PHASE6II.ASM -o QXAI6II.COM
;
; The display is treated as one continuous 640x400 monochrome canvas:
;
;   global Y=0..199   -> 8000h, column offset +0000h..+00C7h
;   global Y=200..399 -> 8000h, column offset +0100h..+01C7h
;
; The 384x288 board crosses the hardware split: 192 board scanlines are in
; the upper half and 96 are in the lower half, an exact 2/3 to 1/3 division.
; The proven column-major mapping remains unchanged. The permanent compact
; lower clock artwork is stored in one 16000-byte bitmap whose first 100
; scanlines are intentionally blank for the lower third of the board.
; Cursor, move markers, status, history, clock hands, and the active clock
; underline remain reversible overlays. Pieces use masked opaque painting;
; erasing a piece restores the exact dark or AAh/55h board background.
;
; The HD146818P RTC is accessed through the QX-11 index/data ports 10h/11h.
; Register A is programmed for the known 2 Hz periodic rate (RS=0Fh), PIE is
; enabled in Register B, and INT 7Ah queues one elapsed chess-clock second for
; every two periodic interrupts. The ISR never draws into VRAM: the foreground
; loop applies queued seconds to the player who owned the turn at interrupt
; time. The original vector and RTC register values are restored on exit.
;
; Sound effects program the SN76489AN directly through QX-11 port 14h.
; Tone channel 0 supplies move/check/flag tones and the noise channel supplies
; capture/illegal-move accents. Sound is never generated inside INT 7Ah.
;
; Board:
;   upper-left  = (128,8)
;   lower-right = (512,296)
;   8 columns, each 48 pixels wide
;   8 rows,    each 36 pixels tall
;
; Per-bank monochrome pixel mapping:
;   byte_column = X >> 3
;   address     = bank_base + (byte_column * 0200h) + local_Y
;   bit_mask    = 80h >> (X & 7)
;
; Native detailed-piece source format:
;   48 packed pixels wide x 32 pixels tall = 6 x 32 = 192 bytes
;   The visible artwork occupies the centered 40x32 region. Four transparent
;   pixels at each side keep the sprite byte-aligned with the 48-pixel square.
;   Every source scanline maps to one display scanline; there is no vertical
;   duplication, so all 32 rows carry independent detail.
;
;   bytes 000h-01Fh = X pixels  0..7,  Y=0..31
;   bytes 020h-03Fh = X pixels  8..15, Y=0..31
;   bytes 040h-05Fh = X pixels 16..23, Y=0..31
;   bytes 060h-07Fh = X pixels 24..31, Y=0..31
;   bytes 080h-09Fh = X pixels 32..39, Y=0..31
;   bytes 0A0h-0BFh = X pixels 40..47, Y=0..31
;
; Piece styles:
;   White side = outlined Staunton-style silhouettes
;   Black side = solid Staunton-style silhouettes
;
; Both styles are masked into the continuous 640x400 canvas. The full solid
; silhouette is the opacity mask: White keeps the outlined artwork with a
; uniform cleared interior, while Black keeps the solid artwork. No dither
; can show through either piece, including across the 200-line boundary.

BOARD_VRAM_SEG    equ 8000h
PANEL_VRAM_SEG    equ 8010h

BOARD_LEFT        equ 128
BOARD_RIGHT       equ 512
BOARD_TOP         equ 8
BOARD_BOTTOM      equ 296
CELL_WIDTH        equ 48
CELL_HEIGHT       equ 36
BOARD_CELLS       equ 8

PIECE_WIDTH_BYTES equ 6
PIECE_SOURCE_HEIGHT equ 32
PIECE_DISPLAY_HEIGHT equ 32

CHECK_INDICATOR_WIDTH_BYTES equ 4
CHECK_INDICATOR_HEIGHT      equ 8
TERMINAL_INDICATOR_WIDTH_BYTES equ 7
TERMINAL_INDICATOR_HEIGHT      equ 8

MOVE_HISTORY_CAPACITY          equ 256
MOVE_HISTORY_RECORD_SIZE       equ 8
MOVE_HISTORY_VISIBLE_LINES     equ 8

MOVE_FLAG_CAPTURE              equ 01h
MOVE_FLAG_PAWN_DOUBLE          equ 02h
MOVE_FLAG_CASTLE               equ 04h
MOVE_FLAG_EN_PASSANT           equ 08h
MOVE_FLAG_PROMOTION            equ 10h

CASTLE_WHITE_KINGSIDE          equ 01h
CASTLE_WHITE_QUEENSIDE         equ 02h
CASTLE_BLACK_KINGSIDE          equ 04h
CASTLE_BLACK_QUEENSIDE         equ 08h
CASTLE_ALL_RIGHTS              equ 0Fh
NO_EN_PASSANT                  equ 0FFh

SMALL_DRAW_PAINT               equ 0
SMALL_DRAW_XOR                 equ 1

MOVE_LIST_X                    equ 540
MOVE_LIST_TITLE_Y              equ 24
MOVE_LIST_FIRST_Y              equ 42
MOVE_LIST_LINE_STEP            equ 10

PROMOTION_PROMPT_X             equ 540
PROMOTION_TITLE_Y              equ 142
PROMOTION_CHOICES_Y            equ 154

; Upper-bank game status, immediately to the left of the board.
TURN_INDICATOR_X      equ 24
TURN_INDICATOR_Y      equ 24

; The 32x8 CHECK label is drawn below it at X=40,Y=40.
; X=40 -> byte column 5 -> 5 * 0200h = 0A00h; Y=40 -> 0028h.
CHECK_INDICATOR_OFFSET equ 0A28h

; The 56x8 CHECKMATE/STALEMATE label is drawn at X=24,Y=40.
TERMINAL_INDICATOR_OFFSET equ 0628h

; Traditional dual chess clock in the lower 640x200 bank. Each player has a
; separate dial and time state. The permanent case, plungers, faces, labels,
; and twelve hour marks are painted once. Hands and the active-side underline
; are XOR-drawn so the foreground RTC service can update only the running clock.
CHESS_CLOCK_LEFT          equ 34
CHESS_CLOCK_RIGHT         equ 358
CHESS_CLOCK_TOP           equ 116
CHESS_CLOCK_BOTTOM        equ 195
CHESS_CLOCK_DIVIDER_X     equ 196
WHITE_CLOCK_CENTER_X      equ 116
BLACK_CLOCK_CENTER_X      equ 276
CLOCK_CENTER_Y            equ 156
CLOCK_FACE_RADIUS         equ 28
CLOCK_TICK_COUNT    equ 12

; Square (0,0) begins at X=128,Y=8.
; The packed 48x32 sprite begins at X=128,Y=10. Its four blank pixels on
; either side center the visible 40x32 artwork at X=132..171.
;
; ES=8000h supplies the continuous column-major 640x400 canvas.
; X=128 -> byte column 16 -> 16 * 0200h = 2000h.
PIECE_FIRST_X_OFFSET equ 2000h
PIECE_FIRST_Y        equ BOARD_TOP + 2

; Moving one board column advances 48 pixels:
;   48 / 8 = 6 VRAM byte-columns
;   6 * 0200h = 0C00h.
PIECE_CELL_X_STEP equ 0C00h

; Native VRAM contains 80 vertical byte-columns. Each column has
; 200 visible bytes followed by unused space up to the 0200h stride.
VRAM_COLUMN_COUNT  equ 80
VRAM_COLUMN_HEIGHT equ 200
VRAM_COLUMN_STRIDE equ 0200h
VRAM_COLUMN_SKIP   equ VRAM_COLUMN_STRIDE - VRAM_COLUMN_HEIGHT

EMPTY   equ 0
PAWN    equ 1
KNIGHT  equ 2
BISHOP  equ 3
ROOK    equ 4
QUEEN   equ 5
KING    equ 6
BLACK   equ 80h

SELECT_SOURCE equ 0
SELECT_DEST   equ 1

GAME_PLAYING   equ 0
GAME_CHECKMATE equ 1
GAME_STALEMATE equ 2
GAME_TIME_FORFEIT equ 3

SCAN_UP       equ 48h
SCAN_DOWN     equ 50h
SCAN_LEFT     equ 4Bh
SCAN_RIGHT    equ 4Dh

RTC_INDEX_PORT       equ 10h
RTC_DATA_PORT        equ 11h
RTC_REGISTER_A       equ 0Ah
RTC_REGISTER_B       equ 0Bh
RTC_REGISTER_C       equ 0Ch
RTC_RATE_2HZ         equ 0Fh
RTC_PIE              equ 40h
RTC_PERIODIC_FLAG    equ 40h
RTC_TICKS_PER_SECOND equ 2
COMPUTER_THINK_DELAY_SECONDS equ 5
COMPUTER_SEARCH_LIMIT_SECONDS equ 15

MENU_ACTION_NONE      equ 0
MENU_ACTION_RESTART   equ 1
MENU_ACTION_QUIT      equ 2
MENU_ACTION_PAUSE     equ 3
MENU_ITEM_COUNT       equ 3

; Phase 6 II centered large menu. All coordinates remain in the upper bank.
MENU_BOX_LEFT         equ 190
MENU_BOX_RIGHT        equ 450
MENU_BOX_TOP          equ 44
MENU_BOX_BOTTOM       equ 188
MENU_TITLE_X          equ 266
MENU_TITLE_Y          equ 57
MENU_FIRST_Y          equ 92
MENU_LINE_STEP        equ 30
MENU_PAUSE_X          equ 290
MENU_RESTART_X        equ 278
MENU_QUIT_X           equ 296
MENU_HIGHLIGHT_BYTE_FIRST equ 31       ; X=248
MENU_HIGHLIGHT_COLUMNS    equ 18       ; 144 pixels, through X=391
MENU_HIGHLIGHT_TOP        equ MENU_FIRST_Y - 5
MENU_HIGHLIGHT_HEIGHT     equ 22

; Opaque menu save area: X=184..455, Y=40..191, byte aligned.
MENU_SAVE_BYTE_FIRST   equ 22
MENU_SAVE_COLUMNS      equ 36
MENU_SAVE_TOP          equ 36
MENU_SAVE_HEIGHT       equ 160
MENU_SAVE_FIRST_OFFSET equ (MENU_SAVE_BYTE_FIRST * VRAM_COLUMN_STRIDE) + MENU_SAVE_TOP

PSG_DATA_PORT         equ 14h


start:
    cld

    ; BIOS mode 07h selects the QX-11's configured high-resolution mode.
    ; On a monochrome configuration this is the native 640x400 display.
    mov  ax, 0007h
    int  10h
    push cx
    mov ax,0100h
    mov ch,20
    mov cl,07
    int 10h
    pop cx

    ; Do this after INT 10h because the BIOS is not assumed to preserve DS.
    ; A DOS .COM normally starts with CS=DS, but make it explicit because the
    ; position array, pointer tables, and bitmaps are read through DS.
    push cs
    pop  ds

    ; Match the original Epson PRE.EXE display-controller setup exactly.
    call InitializeGAVDPFromPRE

    call ShowPhase6IISplash
    call RestartGame
    call InstallRTCClock

.wait_for_key:
    ; The RTC handler queues work but never touches VRAM. Polling the keyboard
    ; lets the foreground refresh the clock even when no key is pressed.
    call ServiceClockUpdates
    call ServiceHintBlink

    cmp  byte [GamePaused], 0
    jne  .poll_keyboard

    ; White is the human side and Black is always computer-controlled.
    ; Run the complete Black turn before polling BIOS input. This makes human
    ; board input structurally unavailable while the computer owns the turn.
    cmp  byte [GameState], GAME_PLAYING
    jne  .poll_keyboard
    test byte [CurrentTurn], BLACK
    jz   .poll_keyboard
    call RunComputerTurn
    jmp  .wait_for_key

.poll_keyboard:
    mov  ah, 01h
    int  16h
    jz   .wait_for_key

    xor  ax, ax
    int  16h

    cmp  byte [HintActive], 0
    je   .hint_cleared
    ; Any key dismisses the visible hint without also acting on the board.
    call DismissHint
    jmp  .wait_for_key
.hint_cleared:

    cmp  byte [GamePaused], 0
    je   .not_paused
    cmp  al, 0Dh
    je   .resume_paused_game
    cmp  al, 1Bh
    jne  .wait_for_key
    jmp  .open_menu

.resume_paused_game:
    call LeavePausedState
    jmp  .wait_for_key

.not_paused:

    cmp  al, 'H'
    je   .direct_hint
    cmp  al, 'h'
    jne  .not_hint_key
.direct_hint:
    call RequestHumanHint
    jmp  .wait_for_key
.not_hint_key:

    cmp  al, 1Bh             ; Esc
    jne  .not_escape
    jmp  .open_menu

.open_menu:
    call RunEscapeMenu
    cmp  al, MENU_ACTION_RESTART
    je   .menu_restart
    cmp  al, MENU_ACTION_QUIT
    je   .exit
    cmp  al, MENU_ACTION_PAUSE
    je   .menu_pause
    cmp  byte [GamePaused], 0
    jne  .wait_for_key
    mov  byte [ClockPaused], 0
    jmp  .wait_for_key

.menu_restart:
    call RestartGame
    jmp  .wait_for_key

.menu_pause:
    cmp  byte [GamePaused], 0
    je   .start_pause
    call LeavePausedState
    jmp  .wait_for_key
.start_pause:
    call EnterPausedState
    jmp  .wait_for_key

.not_escape:
    ; CHECKMATE, STALEMATE, and TIME FORFEIT freeze the completed position.
    ; Esc remains active so the player can always return to DOS.
    cmp  byte [GameState], GAME_PLAYING
    je   .game_active
    jmp  .wait_for_key

.game_active:
    cmp  al, 0Dh             ; Enter
    jne  .not_enter
    jmp  .enter_pressed

.not_enter:
    cmp  ah, SCAN_UP
    je   .cursor_up
    cmp  ah, SCAN_DOWN
    je   .cursor_down
    cmp  ah, SCAN_LEFT
    je   .cursor_left
    cmp  ah, SCAN_RIGHT
    jne  .wait_for_key

.cursor_right:
    cmp  byte [CursorColumn], 7
    je   .wait_for_key
    call EraseCursorFrame
    inc  byte [CursorColumn]
    call DrawCursorFrame
    jmp  .wait_for_key

.cursor_left:
    cmp  byte [CursorColumn], 0
    je   .wait_for_key
    call EraseCursorFrame
    dec  byte [CursorColumn]
    call DrawCursorFrame
    jmp  .wait_for_key

.cursor_down:
    cmp  byte [CursorRow], 7
    je   .wait_for_key
    call EraseCursorFrame
    inc  byte [CursorRow]
    call DrawCursorFrame
    jmp  .wait_for_key

.cursor_up:
    cmp  byte [CursorRow], 0
    je   .wait_for_key
    call EraseCursorFrame
    dec  byte [CursorRow]
    call DrawCursorFrame
    jmp  .wait_for_key

.enter_pressed:
    call HandleEnterSelection
    jmp  .wait_for_key

.exit:
    call SilenceAllSound
    call UninstallRTCClock
    ; Reinitialize and clear the configured QX-11 high-resolution display
    ; before returning to DOS.
    mov  ax, 0007h
    int  10h
    mov  ax, 4C00h
    int  21h


; ------------------------------------------------------------------
; RestartGame
;
; Rebuilds the complete initial position and screen without leaving DOS or
; reinstalling the RTC vector. ClockPaused is asserted before any state or
; VRAM changes, and ISR-owned pending counters are cleared atomically.
; ------------------------------------------------------------------
RestartGame:
    pushf
    push ax
    push cx
    push si
    push di
    push es

    mov  byte [ClockPaused], 1
    call SilenceAllSound

    pushf
    cli
    mov  byte [RTCSubsecondTicks], 0
    mov  byte [WhiteSecondsPending], 0
    mov  byte [BlackSecondsPending], 0
    mov  byte [ComputerThinkBlinkPending], 0
    mov  byte [HintBlinkPending], 0
    popf

    push ds
    pop  es
    cld
    mov  si, InitialBoardPosition
    mov  di, BoardPosition
    mov  cx, 64
    rep  movsb

    xor  ax, ax
    mov  di, MoveHistory
    mov  cx, MOVE_HISTORY_CAPACITY * MOVE_HISTORY_RECORD_SIZE
    rep  stosb
    mov  di, MoveMask
    mov  cx, 8
    rep  stosb

    mov  byte [CursorColumn], 4
    mov  byte [CursorRow], 6
    mov  byte [SavedHumanCursorColumn], 4
    mov  byte [SavedHumanCursorRow], 6
    mov  byte [SelectionState], SELECT_SOURCE
    mov  byte [CurrentTurn], 0
    mov  byte [CheckIndicatorVisible], 0
    mov  byte [GameState], GAME_PLAYING
    mov  byte [PositionInCheck], 0
    mov  byte [SourceColumn], 0
    mov  byte [SourceRow], 0
    mov  byte [SelectedPiece], EMPTY
    mov  byte [CapturedPiece], EMPTY
    mov  byte [ComputerMoveActive], 0
    mov  byte [ComputerThinkingVisible], 0
    mov  byte [ComputerThinkSecondsElapsed], 0
    mov  byte [ComputerSearchTimedOut], 0
    mov  byte [ComputerCompletedDepth], 0
    mov  byte [CastlingRights], CASTLE_ALL_RIGHTS
    mov  byte [EnPassantSquare], NO_EN_PASSANT
    mov  byte [PendingMoveFlags], 0
    mov  byte [CommittedMoveFlags], 0
    mov  byte [PreviousCastlingRights], CASTLE_ALL_RIGHTS
    mov  byte [PreviousEnPassantSquare], NO_EN_PASSANT
    mov  byte [PromotionPiece], EMPTY
    mov  byte [HistoryNext], 0
    mov  word [HistoryCount], 0
    mov  byte [WhiteClockHour], 0
    mov  byte [WhiteClockMinute], 10
    mov  byte [WhiteClockSecond], 0
    mov  byte [BlackClockHour], 0
    mov  byte [BlackClockMinute], 10
    mov  byte [BlackClockSecond], 0
    mov  byte [WhiteFlagSoundPlayed], 0
    mov  byte [BlackFlagSoundPlayed], 0
    mov  byte [TimeWinner], 0
    mov  byte [ClockApplyCount], 0
    mov  byte [ClockBlackApplyCount], 0
    mov  byte [GamePaused], 0
    mov  byte [PausedTextVisible], 0
    mov  byte [MenuSelection], 0
    mov  byte [HintActive], 0
    mov  byte [HintVisible], 0
    mov  byte [HintTextVisible], 0
    mov  byte [HintCursorHidden], 0
    mov  byte [HintBestMoveFound], 0
    mov  byte [SmallDrawMode], SMALL_DRAW_PAINT
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG

    call ClearScreenWithBIOS
    call LoadLowerStaticBitmap
    call DrawChessboard
    call DrawBoardCoordinates
    call DrawUpperStaticText
    call DrawMoveHistoryHeader
    call DrawClockHandsXor
    call DrawClockActiveIndicatorXor
    call DrawAllPieces
    call DrawTurnIndicatorXor
    call EvaluateGameState
    call DrawCursorFrame

    pushf
    cli
    mov  byte [RTCSubsecondTicks], 0
    mov  byte [WhiteSecondsPending], 0
    mov  byte [BlackSecondsPending], 0
    popf
    mov  byte [ClockPaused], 0

    pop  es
    pop  di
    pop  si
    pop  cx
    pop  ax
    popf
    ret


; ------------------------------------------------------------------
; ESC menu and pause handling
; ------------------------------------------------------------------
RunEscapeMenu:
    push bx
    push cx
    push dx
    push si

    mov  byte [ClockPaused], 1
    mov  byte [MenuSelection], 0
    call SaveMenuBackground
    call ClearMenuArea
    call DrawEscapeMenuPaint
    call DrawMenuHighlightXor

.wait_key:
    xor  ax, ax
    int  16h
    cmp  al, 1Bh
    je   .no_action
    cmp  al, 0Dh
    je   .choose
    cmp  ah, SCAN_UP
    je   .up
    cmp  ah, SCAN_DOWN
    jne  .wait_key

.down:
    call DrawMenuHighlightXor
    inc  byte [MenuSelection]
    cmp  byte [MenuSelection], MENU_ITEM_COUNT
    jb   .down_ready
    mov  byte [MenuSelection], 0
.down_ready:
    call DrawMenuHighlightXor
    jmp  .wait_key

.up:
    call DrawMenuHighlightXor
    cmp  byte [MenuSelection], 0
    jne  .decrement
    mov  byte [MenuSelection], MENU_ITEM_COUNT
.decrement:
    dec  byte [MenuSelection]
    call DrawMenuHighlightXor
    jmp  .wait_key

.choose:
    mov  al, [MenuSelection]
    cmp  al, 0
    je   .pause
    cmp  al, 1
    je   .restart
    mov  dl, MENU_ACTION_QUIT
    jmp  .finish

.pause:
    mov  dl, MENU_ACTION_PAUSE
    jmp  .finish
.restart:
    mov  dl, MENU_ACTION_RESTART
    jmp  .finish
.no_action:
    mov  dl, MENU_ACTION_NONE

.finish:
    call DrawMenuHighlightXor
    call RestoreMenuBackground
    mov  al, dl
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Save and restore the exact upper-bank bytes covered by the modal dialog.
SaveMenuBackground:
    pushf
    cld
    push ax
    push bx
    push cx
    push si
    push di
    push es

    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  si, MENU_SAVE_FIRST_OFFSET
    mov  di, MenuBackgroundBuffer
    mov  bx, MENU_SAVE_COLUMNS
.next_column:
    mov  cx, MENU_SAVE_HEIGHT
.next_byte:
    mov  al, [es:si]
    mov  [di], al
    inc  si
    inc  di
    loop .next_byte
    add  si, VRAM_COLUMN_STRIDE - MENU_SAVE_HEIGHT
    dec  bx
    jnz  .next_column

    pop  es
    pop  di
    pop  si
    pop  cx
    pop  bx
    pop  ax
    popf
    ret


ClearMenuArea:
    pushf
    cld
    push ax
    push bx
    push cx
    push di
    push es

    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  di, MENU_SAVE_FIRST_OFFSET
    xor  ax, ax
    mov  bx, MENU_SAVE_COLUMNS
.next_column:
    mov  cx, MENU_SAVE_HEIGHT
.next_byte:
    mov  byte [es:di], 0
    inc  di
    loop .next_byte
    add  di, VRAM_COLUMN_STRIDE - MENU_SAVE_HEIGHT
    dec  bx
    jnz  .next_column

    pop  es
    pop  di
    pop  cx
    pop  bx
    pop  ax
    popf
    ret


RestoreMenuBackground:
    pushf
    cld
    push ax
    push bx
    push cx
    push si
    push di
    push es

    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  si, MenuBackgroundBuffer
    mov  di, MENU_SAVE_FIRST_OFFSET
    mov  bx, MENU_SAVE_COLUMNS
.next_column:
    mov  cx, MENU_SAVE_HEIGHT
.next_byte:
    mov  al, [si]
    mov  [es:di], al
    inc  si
    inc  di
    loop .next_byte
    add  di, VRAM_COLUMN_STRIDE - MENU_SAVE_HEIGHT
    dec  bx
    jnz  .next_column

    pop  es
    pop  di
    pop  si
    pop  cx
    pop  bx
    pop  ax
    popf
    ret


DrawEscapeMenuPaint:
    push ax
    push cx
    push dx
    push si
    push di

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG

    mov  cx, MENU_BOX_LEFT
    mov  dx, MENU_BOX_TOP
    mov  si, MENU_BOX_RIGHT
    mov  di, MENU_BOX_BOTTOM
    call DrawGlobalRectanglePaint
    add  cx, 3
    add  dx, 3
    sub  si, 3
    sub  di, 3
    call DrawGlobalRectanglePaint

    mov  cx, MENU_TITLE_X
    mov  dx, MENU_TITLE_Y
    mov  si, EscapeMenuTitle
    call DrawLargeStringPaint

    mov  cx, MENU_PAUSE_X
    mov  dx, MENU_FIRST_Y
    mov  si, MenuPauseText
    call DrawLargeStringPaint

    mov  cx, MENU_RESTART_X
    add  dx, MENU_LINE_STEP
    mov  si, MenuRestartText
    call DrawLargeStringPaint

    mov  cx, MENU_QUIT_X
    add  dx, MENU_LINE_STEP
    mov  si, MenuQuitText
    call DrawLargeStringPaint

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; Invert a byte-aligned bar behind the selected option. The lettering reverses
; to white on black, providing a clear full-row highlight.
DrawMenuHighlightXor:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    xor  ax, ax
    mov  al, [MenuSelection]
    mov  bl, MENU_LINE_STEP
    mul  bl
    add  ax, MENU_HIGHLIGHT_TOP
    mov  di, ax
    add  di, MENU_HIGHLIGHT_BYTE_FIRST * VRAM_COLUMN_STRIDE

    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  bx, MENU_HIGHLIGHT_COLUMNS
.next_column:
    mov  cx, MENU_HIGHLIGHT_HEIGHT
.next_byte:
    xor  byte [es:di], 0FFh
    inc  di
    loop .next_byte
    add  di, VRAM_COLUMN_STRIDE - MENU_HIGHLIGHT_HEIGHT
    dec  bx
    jnz  .next_column

    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: CX=left, DX=top, SI=right, DI=bottom (inclusive global coordinates).
DrawGlobalRectanglePaint:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [cs:GlobalRectLeftScratch], cx
    mov  bx, cx
.horizontal:
    mov  cx, bx
    call PaintPixelBlue
    mov  ax, dx
    mov  dx, di
    call PaintPixelBlue
    mov  dx, ax
    inc  bx
    cmp  bx, si
    jbe  .horizontal

    inc  dx
    dec  di
.vertical:
    cmp  dx, di
    ja   .done
    mov  cx, [cs:GlobalRectLeftScratch]
    call PaintPixelBlue
    mov  cx, si
    call PaintPixelBlue
    inc  dx
    jmp  .vertical

.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: CX=left, DX=top, SI=right, DI=bottom (inclusive global coordinates).
; Calling twice restores the original pixels.
DrawGlobalRectangleXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [cs:GlobalRectLeftScratch], cx
    mov  bx, cx
.horizontal:
    mov  cx, bx
    call XorPixelBlue
    mov  ax, dx
    mov  dx, di
    call XorPixelBlue
    mov  dx, ax
    inc  bx
    cmp  bx, si
    jbe  .horizontal

    inc  dx
    dec  di
.vertical:
    cmp  dx, di
    ja   .done
    mov  cx, [cs:GlobalRectLeftScratch]
    call XorPixelBlue
    mov  cx, si
    call XorPixelBlue
    inc  dx
    jmp  .vertical

.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


EnterPausedState:
    mov  byte [ClockPaused], 1
    cmp  byte [GamePaused], 0
    jne  .done
    mov  byte [GamePaused], 1
    call DrawPausedTextXor
    mov  byte [PausedTextVisible], 1
.done:
    ret


LeavePausedState:
    cmp  byte [PausedTextVisible], 0
    je   .text_removed
    call DrawPausedTextXor
    mov  byte [PausedTextVisible], 0
.text_removed:
    mov  byte [GamePaused], 0
    mov  byte [ClockPaused], 0
    ret


DrawPausedTextXor:
    push ax
    push cx
    push dx
    push si
    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, 24
    mov  dx, 56
    mov  si, GamePausedText
    call DrawSmallStringXor
    pop  ax
    mov  [SmallDrawSegment], ax
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; Human hint
;
; The hint engine minimizes Black's score after Black's strongest immediate
; legal reply. Search runs while ClockPaused is asserted. The board, turn,
; castling rights, en-passant square, cursor, and selection are restored.
; ------------------------------------------------------------------
RequestHumanHint:
    push ax

    cmp  byte [GameState], GAME_PLAYING
    jne  .unavailable
    test byte [CurrentTurn], BLACK
    jnz  .unavailable

    mov  byte [ClockPaused], 1
    call CancelPendingSelection
    call EraseCursorFrame
    mov  byte [HintCursorHidden], 1
    call DrawFindingHintXor
    call FindBestHumanHint
    mov  byte [HintSearchSucceeded], 0
    jc   .search_finished
    mov  byte [HintSearchSucceeded], 1
.search_finished:
    call DrawFindingHintXor
    cmp  byte [HintSearchSucceeded], 0
    je   .no_hint

    mov  byte [HintBlinkPending], 0
    call FormatHintMoveText
    call DrawHintMoveTextXor
    mov  byte [HintTextVisible], 1
    call DrawHintFramesXor
    mov  byte [HintVisible], 1
    mov  byte [HintActive], 1
    jmp  .resume_clock

.no_hint:
    call DrawCursorFrame
    mov  byte [HintCursorHidden], 0
.unavailable:
    call PlayIllegalMoveSound

.resume_clock:
    cmp  byte [GamePaused], 0
    jne  .done
    mov  byte [ClockPaused], 0
.done:
    pop  ax
    ret


CancelPendingSelection:
    cmp  byte [SelectionState], SELECT_DEST
    jne  .done
    call DrawMoveMarkersXor
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    call DrawSourceMarkerXor
    call ClearMoveMask
    mov  byte [SelectionState], SELECT_SOURCE
.done:
    ret


FindBestHumanHint:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [SourceColumn]
    mov  [HintSavedSourceColumn], al
    mov  al, [SourceRow]
    mov  [HintSavedSourceRow], al
    mov  al, [SelectedPiece]
    mov  [HintSavedSelectedPiece], al
    mov  byte [HintBestMoveFound], 0
    mov  word [HintBestScore], 7FFFh
    mov  word [HintRootNodes], 0
    mov  word [HintReplyNodes], 0
    xor  si, si

.next_source:
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_destination:
    call ValidateMove
    jc   .advance_destination
    inc  word [HintRootNodes]
    call EvaluateHumanHintCandidate
    cmp  byte [HintBestMoveFound], 0
    je   .save_candidate
    cmp  ax, [HintBestScore]
    jge  .advance_destination

.save_candidate:
    mov  [HintBestScore], ax
    mov  byte [HintBestMoveFound], 1
    mov  ax, si
    mov  [HintSourceIndex], al
    mov  al, bh
    mov  cl, 3
    shl  al, cl
    add  al, bl
    mov  [HintDestinationIndex], al

.advance_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination
.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source

    mov  al, [HintSavedSourceColumn]
    mov  [SourceColumn], al
    mov  al, [HintSavedSourceRow]
    mov  [SourceRow], al
    mov  al, [HintSavedSelectedPiece]
    mov  [SelectedPiece], al
    cmp  byte [HintBestMoveFound], 0
    je   .not_found
    clc
    jmp  .restore
.not_found:
    stc
.restore:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


EvaluateHumanHintCandidate:
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [CurrentTurn]
    mov  [HintSavedTurn], al
    mov  al, [CastlingRights]
    mov  [HintSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [HintSavedEnPassantSquare], al
    mov  al, [SourceColumn]
    mov  [HintRootSourceColumn], al
    mov  al, [SourceRow]
    mov  [HintRootSourceRow], al
    mov  al, [SelectedPiece]
    mov  [HintRootSelectedPiece], al
    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [HintBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    mov  byte [HintReplyFound], 0
    mov  word [HintWorstScore], 8000h
    xor  si, si

.next_reply_source:
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_reply_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_reply_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_reply_destination:
    call ValidateMove
    jc   .advance_reply_destination
    inc  word [HintReplyNodes]
    call EvaluateValidatedMovePositionBlack
    cmp  byte [HintReplyFound], 0
    je   .save_reply
    cmp  ax, [HintWorstScore]
    jle  .advance_reply_destination
.save_reply:
    mov  [HintWorstScore], ax
    mov  byte [HintReplyFound], 1
.advance_reply_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_reply_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_reply_destination
.advance_reply_source:
    inc  si
    cmp  si, 64
    jb   .next_reply_source

    cmp  byte [HintReplyFound], 0
    jne  .score_ready
    call IsCurrentKingInCheck
    jnc  .stalemate
    mov  word [HintWorstScore], -30000
    jmp  .score_ready
.stalemate:
    mov  word [HintWorstScore], 0

.score_ready:
    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [HintBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board
    mov  al, [HintSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [HintSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [HintSavedTurn]
    mov  [CurrentTurn], al
    mov  al, [HintRootSourceColumn]
    mov  [SourceColumn], al
    mov  al, [HintRootSourceRow]
    mov  [SourceRow], al
    mov  al, [HintRootSelectedPiece]
    mov  [SelectedPiece], al
    mov  ax, [HintWorstScore]

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


DrawFindingHintXor:
    push ax
    push cx
    push dx
    push si
    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, 18
    mov  dx, 56
    mov  si, FindingHintText
    call DrawSmallStringXor
    pop  ax
    mov  [SmallDrawSegment], ax
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


FormatHintMoveText:
    push ax
    push bx
    push cx

    xor  ax, ax
    mov  al, [HintSourceIndex]
    mov  bl, al
    and  bl, 07h
    add  bl, 'A'
    mov  [HintMoveText + 5], bl
    mov  cl, 3
    shr  ax, cl
    mov  bl, '8'
    sub  bl, al
    mov  [HintMoveText + 6], bl

    xor  ax, ax
    mov  al, [HintDestinationIndex]
    mov  bl, al
    and  bl, 07h
    add  bl, 'A'
    mov  [HintMoveText + 11], bl
    mov  cl, 3
    shr  ax, cl
    mov  bl, '8'
    sub  bl, al
    mov  [HintMoveText + 12], bl

    pop  cx
    pop  bx
    pop  ax
    ret


DrawHintMoveTextXor:
    push ax
    push cx
    push dx
    push si
    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, 18
    mov  dx, 56
    mov  si, HintMoveText
    call DrawSmallStringXor
    pop  ax
    mov  [SmallDrawSegment], ax
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


DrawHintFramesXor:
    push ax
    push bx
    push cx

    xor  ax, ax
    mov  al, [HintSourceIndex]
    mov  bl, al
    and  bl, 07h
    mov  cl, 3
    shr  ax, cl
    mov  bh, al
    call DrawHintSquareFrameXor

    xor  ax, ax
    mov  al, [HintDestinationIndex]
    mov  bl, al
    and  bl, 07h
    mov  cl, 3
    shr  ax, cl
    mov  bh, al
    call DrawHintSquareFrameXor

    pop  cx
    pop  bx
    pop  ax
    ret


; Strong double frame positioned at the outer edge of the selected square.
DrawHintSquareFrameXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    cmp  bl, 7
    ja   .done
    cmp  bh, 7
    ja   .done

    mov  si, BOARD_LEFT + 1
    xor  cx, cx
    mov  cl, bl
    jcxz .left_ready
.add_column:
    add  si, CELL_WIDTH
    loop .add_column
.left_ready:
    mov  di, BOARD_TOP + 1
    xor  cx, cx
    mov  cl, bh
    jcxz .top_ready
.add_row:
    add  di, CELL_HEIGHT
    loop .add_row
.top_ready:
    mov  cx, si
    mov  dx, di
    add  si, CELL_WIDTH - 3
    add  di, CELL_HEIGHT - 3
    call DrawGlobalRectangleXor

    inc  cx
    inc  dx
    dec  si
    dec  di
    call DrawGlobalRectangleXor

.done:
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


ServiceHintBlink:
    push ax
    cmp  byte [HintActive], 0
    je   .done
    pushf
    cli
    mov  al, [HintBlinkPending]
    mov  byte [HintBlinkPending], 0
    popf
    test al, 1
    jz   .done
    call DrawHintFramesXor
    xor  byte [HintVisible], 1
.done:
    pop  ax
    ret


DismissHint:
    cmp  byte [HintActive], 0
    je   .done
    cmp  byte [HintVisible], 0
    je   .frames_removed
    call DrawHintFramesXor
.frames_removed:
    cmp  byte [HintTextVisible], 0
    je   .text_removed
    call DrawHintMoveTextXor
.text_removed:
    mov  byte [HintActive], 0
    mov  byte [HintVisible], 0
    mov  byte [HintTextVisible], 0
    mov  byte [HintBlinkPending], 0
    cmp  byte [HintCursorHidden], 0
    je   .done
    call DrawCursorFrame
    mov  byte [HintCursorHidden], 0
.done:
    ret


; ------------------------------------------------------------------
; RunComputerTurn -- Phase-3 local opponent
;
; Black owns the clock throughout this routine. The visible human cursor is
; erased and its coordinates are preserved. COMPUTER THINKING remains visible
; for at least five RTC-accounted seconds. Move selection starts immediately:
; it first consults a four-entry opening table. If the recorded White first
; move is not present, every legal Black move is temporarily made and every
; legal White reply is examined. Black keeps the best worst-case material
; result. Equal scores keep the first legal move for deterministic behavior.
; If calculation finishes before five seconds, the remaining time is spent
; blinking the message. If calculation takes longer, the move is committed as
; soon as the completed search returns.
;
; The selected move is committed by HandleEnterSelection, exactly like a
; human move, but ComputerMoveActive suppresses source/destination overlays
; that were never drawn. History, castling/en-passant state, capture handling,
; sounds, check classification, clocks, and turn transfer therefore remain on
; the already-tested common path.
; ------------------------------------------------------------------
RunComputerTurn:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp  byte [GameState], GAME_PLAYING
    jne  .done
    test byte [CurrentTurn], BLACK
    jz   .done

    mov  al, [CursorColumn]
    mov  [SavedHumanCursorColumn], al
    mov  al, [CursorRow]
    mov  [SavedHumanCursorRow], al
    call EraseCursorFrame
    call DrawComputerThinkingXor
    mov  byte [ComputerThinkingVisible], 1

    mov  byte [ComputerMoveActive], 1
    mov  byte [ComputerThinkSecondsElapsed], 0
    mov  byte [ComputerThinkBlinkPending], 0
    call SelectComputerMove
    jc   .no_move
    cmp  byte [GameState], GAME_PLAYING
    jne  .move_finished

    ; Search begins immediately. Preserve a five-second minimum presentation
    ; time only when calculation completed sooner.
    call WaitComputerThinkingDelay
    cmp  byte [GameState], GAME_PLAYING
    jne  .move_finished

    mov  byte [SelectionState], SELECT_DEST
    call HandleEnterSelection

    ; A validated computer move must return the turn to White. If defensive
    ; commit checks ever reject it, reclassify the unchanged Black position.
    test byte [CurrentTurn], BLACK
    jz   .move_finished
    call EvaluateGameState
    jmp  .move_finished

.no_move:
    ; AdvanceTurn already classifies normal no-reply positions before this
    ; routine is entered. Keep this independent check for corrupted/custom
    ; test positions and future direct callers.
    call EvaluateGameState

.move_finished:
    mov  byte [ComputerMoveActive], 0
    cmp  byte [ComputerThinkingVisible], 0
    je   .thinking_hidden
    call DrawComputerThinkingXor
    mov  byte [ComputerThinkingVisible], 0
.thinking_hidden:
    mov  al, [SavedHumanCursorColumn]
    mov  [CursorColumn], al
    mov  al, [SavedHumanCursorRow]
    mov  [CursorRow], al
    call DrawCursorFrame

.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; WaitComputerThinkingDelay
;
; The INT 7Ah handler increments ComputerThinkSecondsElapsed once per RTC
; second while Black's automatic turn is active. The foreground services the
; queued chess-clock seconds during the wait, so the dial visibly counts down.
; Direct/unit-test callers do not install the RTC and therefore skip the delay.
; ------------------------------------------------------------------
WaitComputerThinkingDelay:
    push ax

    cmp  byte [RTCInstalled], 0
    je   .done

.wait:
    call ServiceClockUpdates
    cmp  byte [GameState], GAME_PLAYING
    jne  .done
    call ServiceComputerThinkingBlink
    mov  al, [ComputerThinkSecondsElapsed]
    cmp  al, COMPUTER_THINK_DELAY_SECONDS
    jb   .wait

.done:
    pop  ax
    ret


; ------------------------------------------------------------------
; ServiceComputerThinkingBlink
;
; INT 7Ah queues one blink event for each 2 Hz periodic interrupt while the
; computer owns the turn. An odd number of queued events toggles the XOR text;
; an even number leaves it unchanged. All VRAM access remains in foreground
; context.
; ------------------------------------------------------------------
ServiceComputerThinkingBlink:
    push ax

    pushf
    cli
    mov  al, [ComputerThinkBlinkPending]
    mov  byte [ComputerThinkBlinkPending], 0
    popf

    test al, 1
    jz   .done
    call DrawComputerThinkingXor
    xor  byte [ComputerThinkingVisible], 1

.done:
    pop  ax
    ret


; ------------------------------------------------------------------
; SelectComputerMove
;
; Output:
;   Carry clear = SourceColumn/SourceRow/SelectedPiece and the cursor
;                 destination describe a legal Black move; its MoveMask bit
;                 is set for the common commit path.
;   Carry set   = no legal move exists.
; ------------------------------------------------------------------
SelectComputerMove:
    call TryOpeningMove
    jnc  .selected
    mov  word [ComputerQuiescenceLeaves], 0
    mov  word [ComputerRepetitionPenalties], 0
    call FindBestTwoPlyComputerMove
    jc   .selected

    ; Iterative deepening guarantee: the complete depth-two answer is now
    ; retained in ComputerSourceIndex/ComputerDestinationIndex. Depth three
    ; writes only its private Phase4Best* state until the whole pass finishes.
    mov  byte [ComputerCompletedDepth], 2
    mov  byte [ComputerSearchTimedOut], 0
    call FindBestThreePlyComputerMove
.selected:
    ret


; Phase-6 multi-ply opening library. Each fixed 21-byte record contains:
;   byte 0      = exact history length in half-moves (1,3,5,7,9)
;   bytes 1..18 = up to nine source/destination pairs, padded with FFh
;   bytes 19..20= Black's reply source/destination
; Board indices use the program's a8..h1 row-major order. Exact history
; matching naturally recognizes transpositions only when their move order has
; a dedicated record. Every selected reply is still passed through the full
; legal-move validator before it can be committed.
OPENING_BOOK_COUNT       equ 41
OPENING_BOOK_RECORD_SIZE equ 21
OpeningTable:
    db 1,52,36,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,28 ; King's pawn
    db 3,52,36,12,28,62,45,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,1,18 ; King's pawn Nf3
    db 3,52,36,12,28,61,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,1,18 ; Bishop's Opening
    db 3,52,36,12,28,51,43,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Philidor setup
    db 3,52,36,12,28,57,42,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Vienna
    db 3,52,36,12,28,53,37,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,28,37 ; King's Gambit
    db 5,52,36,12,28,62,45,1,18,61,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Italian
    db 5,52,36,12,28,62,45,1,18,61,25,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,8,16 ; Ruy Lopez
    db 5,52,36,12,28,62,45,1,18,51,35,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,28,35 ; Scotch
    db 5,52,36,12,28,61,34,1,18,62,45,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Bishop line
    db 7,52,36,12,28,62,45,1,18,61,34,6,21,51,43,0FFh,0FFh,0FFh,0FFh,5,26 ; Italian d3
    db 7,52,36,12,28,62,45,1,18,61,25,8,16,25,32,0FFh,0FFh,0FFh,0FFh,6,21 ; Ruy Ba4
    db 7,52,36,12,28,62,45,1,18,51,35,28,35,45,35,0FFh,0FFh,0FFh,0FFh,6,21 ; Scotch Nxd4
    db 9,52,36,12,28,62,45,1,18,61,34,6,21,51,43,5,26,60,62,11,19 ; Italian castle
    db 9,52,36,12,28,62,45,1,18,61,25,8,16,25,32,6,21,60,62,5,12 ; Ruy castle
    db 1,51,35,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; Queen's pawn
    db 3,51,35,11,27,50,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,20 ; Queen's Gambit
    db 3,51,35,11,27,62,45,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Queen's pawn Nf3
    db 3,51,35,11,27,58,37,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; London
    db 3,51,35,11,27,52,44,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Colle setup
    db 5,51,35,11,27,50,34,12,20,57,42,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; QGD Nc3
    db 5,51,35,11,27,50,34,12,20,62,45,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; QGD Nf3
    db 5,51,35,11,27,62,45,6,21,50,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,20 ; QGD transposition
    db 7,51,35,11,27,50,34,12,20,57,42,6,21,58,30,0FFh,0FFh,0FFh,0FFh,5,12 ; QGD Bg5
    db 9,51,35,11,27,50,34,12,20,57,42,6,21,58,30,5,12,52,44,4,6 ; QGD castle
    db 1,50,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,28 ; English
    db 3,50,34,12,28,57,42,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; English Nc3
    db 3,50,34,12,28,54,46,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,1,18 ; English g3
    db 5,50,34,12,28,57,42,6,21,54,46,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; English main line
    db 5,50,34,12,28,54,46,1,18,61,54,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,14,22 ; English fianchetto
    db 1,62,45,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,6,21 ; Reti
    db 3,62,45,6,21,54,46,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,14,22 ; Reti g3
    db 3,62,45,6,21,51,35,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; Reti d4
    db 3,62,45,6,21,50,34,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,20 ; Reti c4
    db 5,62,45,6,21,54,46,14,22,61,54,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,5,14 ; Reti Bg2
    db 7,62,45,6,21,54,46,14,22,61,54,5,14,60,62,0FFh,0FFh,0FFh,0FFh,4,6 ; Reti castle
    db 1,49,41,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,28 ; Larsen
    db 1,53,37,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; Bird
    db 1,54,46,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; King's fianchetto
    db 1,57,42,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,11,27 ; Van Geet
    db 1,48,40,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,12,28 ; Anderssen


TryOpeningMove:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov  ax, [HistoryCount]
    cmp  ah, 0
    jne  .not_found
    test al, 1
    jz   .not_found
    cmp  al, 9
    ja   .not_found

    mov  si, OpeningTable
    mov  bp, OPENING_BOOK_COUNT

.next_entry:
    mov  al, [HistoryCount]
    cmp  al, [si]
    jne  .advance_entry

    lea  bx, [si + 1]
    mov  di, MoveHistory
    xor  cx, cx
    mov  cl, [si]

.compare_history:
    mov  al, [di + 0]
    cmp  al, [bx + 0]
    jne  .advance_entry
    mov  al, [di + 1]
    cmp  al, [bx + 1]
    jne  .advance_entry
    add  di, MOVE_HISTORY_RECORD_SIZE
    add  bx, 2
    loop .compare_history

    mov  al, [si + 19]
    mov  [ComputerSourceIndex], al
    mov  al, [si + 20]
    mov  [ComputerDestinationIndex], al
    call PrepareComputerMoveFromIndices
    jnc  .restore

.advance_entry:
    add  si, OPENING_BOOK_RECORD_SIZE
    dec  bp
    jnz  .next_entry

.not_found:
    stc

.restore:
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Phase-5 completed two-ply search. Scan every Black source/destination accepted
; by ValidateMove. EvaluateComputerCandidateTwoPly temporarily makes each move,
; scans every legal White response, and returns the lowest full positional
; score that White can force. This is the safe completed result retained when
; the RTC deadline interrupts the deeper pass.
;
; A mate-in-one receives +30000; stalemate receives 0. ComputerBestScore is
; therefore signed. Equal scores retain the first move in board scan order.
; The legacy Phase-2 label remains as an alias for test/tool compatibility.
; ------------------------------------------------------------------
FindBestMaterialComputerMove:
FindBestTwoPlyComputerMove:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov  byte [ComputerBestMoveFound], 0
    mov  word [ComputerBestScore], 8000h
    mov  word [ComputerRootNodes], 0
    mov  word [ComputerReplyNodes], 0
    mov  word [ComputerAlphaCutoffs], 0
    xor  si, si

.next_source:
    call ServiceComputerSearchForeground
    cmp  byte [GameState], GAME_PLAYING
    jne  .search_aborted

    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source

    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al

    xor  bx, bx

.next_destination:
    call ValidateMove
    jc   .advance_destination

    inc  word [ComputerRootNodes]
    call EvaluateComputerCandidateTwoPly
    cmp  byte [GameState], GAME_PLAYING
    jne  .search_aborted
    cmp  byte [ComputerBestMoveFound], 0
    je   .save_candidate
    cmp  ax, [ComputerBestScore]
    jle  .advance_destination

.save_candidate:
    mov  word [ComputerBestScore], ax
    mov  byte [ComputerBestMoveFound], 1
    mov  ax, si
    mov  [ComputerSourceIndex], al
    mov  al, bh
    mov  cl, 3
    shl  al, cl
    add  al, bl
    mov  [ComputerDestinationIndex], al

.advance_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination

.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source

    cmp  byte [ComputerBestMoveFound], 0
    jne  .prepare_best
.search_aborted:
    stc
    jmp  .restore

.prepare_best:
    call PrepareComputerMoveFromIndices

.restore:
    pop  si
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; EvaluateComputerCandidateTwoPly
;
; Input:
;   SI = Black source index.
;   BL/BH = Black destination column/row.
;   ValidateMove has accepted the candidate and populated its scratch state.
;
; Output:
;   AX = signed candidate score from Black's perspective.
;
; The live board and special-rule state are restored byte-for-byte. Every White
; reply is temporarily applied and evaluated with material plus piece-square
; terms. During the reply scan the foreground clock/blink service keeps
; running; the ISR always charges Black while ComputerMoveActive is set.
; ------------------------------------------------------------------
EvaluateComputerCandidateTwoPly:
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [SourceColumn]
    mov  [SearchRootSourceColumn], al
    mov  al, [SourceRow]
    mov  [SearchRootSourceRow], al
    mov  al, [SelectedPiece]
    mov  [SearchRootSelectedPiece], al
    mov  [SearchRootSourceIndex], si
    mov  al, bl
    mov  [SearchRootDestinationColumn], al
    mov  al, bh
    mov  [SearchRootDestinationRow], al
    mov  al, bh
    mov  cl, 3
    shl  al, cl
    add  al, bl
    mov  [SearchRootDestinationIndex], al
    mov  al, [PendingMoveFlags]
    mov  [SearchRootMoveFlags], al
    mov  al, [DestinationPiece]
    mov  [SearchRootCapturedPiece], al
    mov  al, [CastleRookSourceColumn]
    mov  [SearchRootCastleSourceColumn], al
    mov  al, [CastleRookDestinationColumn]
    mov  [SearchRootCastleDestinationColumn], al

    call ScoreComputerCandidate
    mov  [SearchRootGain], ax
    call GetRootRepetitionPenalty
    mov  [SearchRootPenalty], ax

    mov  al, [CurrentTurn]
    mov  [SearchSavedCurrentTurn], al
    mov  al, [CastlingRights]
    mov  [SearchSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [SearchSavedEnPassantSquare], al

    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [SearchBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplySearchRootMove
    xor  byte [CurrentTurn], BLACK
    mov  byte [SearchReplyFound], 0
    mov  word [SearchBestWhiteScore], 7FFFh
    xor  si, si

.next_white_source:
    call ServiceComputerSearchForeground
    cmp  byte [GameState], GAME_PLAYING
    jne  .search_interrupted

    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_white_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_white_source

    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_white_destination:
    call ValidateMove
    jc   .advance_white_destination

    inc  word [ComputerReplyNodes]
    mov  byte [SearchReplyFound], 1
    call EvaluateValidatedMovePositionBlack
    sub  ax, [SearchRootPenalty]
    cmp  ax, [SearchBestWhiteScore]
    jge  .test_alpha_cutoff
    mov  [SearchBestWhiteScore], ax

.test_alpha_cutoff:
    cmp  byte [ComputerBestMoveFound], 0
    je   .advance_white_destination
    mov  dx, [SearchBestWhiteScore]
    cmp  dx, [ComputerBestScore]
    jg   .advance_white_destination
    inc  word [ComputerAlphaCutoffs]
    mov  [SearchCandidateScore], dx
    jmp  .restore_position

.advance_white_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_white_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_white_destination

.advance_white_source:
    inc  si
    cmp  si, 64
    jb   .next_white_source

    cmp  byte [SearchReplyFound], 0
    jne  .ordinary_score

    ; No White reply: distinguish mate from stalemate in the temporary board.
    call IsCurrentKingInCheck
    jc   .mate_score
    mov  word [SearchCandidateScore], 0
    jmp  .restore_position

.mate_score:
    mov  word [SearchCandidateScore], 30000
    jmp  .restore_position

.ordinary_score:
    mov  ax, [SearchBestWhiteScore]
    mov  [SearchCandidateScore], ax
    jmp  .restore_position

.search_interrupted:
    mov  word [SearchCandidateScore], 8000h

.restore_position:
    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [SearchBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board

    mov  al, [SearchSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [SearchSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [SearchSavedCurrentTurn]
    mov  [CurrentTurn], al
    mov  al, [SearchRootSourceColumn]
    mov  [SourceColumn], al
    mov  al, [SearchRootSourceRow]
    mov  [SourceRow], al
    mov  al, [SearchRootSelectedPiece]
    mov  [SelectedPiece], al

    mov  ax, [SearchCandidateScore]
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; ------------------------------------------------------------------
; FindBestThreePlyComputerMove -- Phase-4 iterative depth-three pass
;
; The completed Phase-3 answer remains in ComputerSourceIndex and
; ComputerDestinationIndex until this entire pass completes. Root moves are
; visited in three classes: promotions/valuable captures, other captures and
; checks, then quiet moves. Every root candidate searches White's minimizing
; reply and Black's maximizing continuation.
;
; Output:
;   Carry clear = a prepared move is available (depth three or fallback).
;   Carry set   = the game ended while searching.
; ------------------------------------------------------------------
FindBestThreePlyComputerMove:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  byte [Phase4BestMoveFound], 0
    mov  word [Phase4BestScore], 8000h
    mov  word [ComputerThirdPlyNodes], 0
    mov  word [ComputerPhase4Cutoffs], 0
    mov  byte [SearchRootOrderPass], 0

.next_order_pass:
    xor  si, si

.next_source:
    call ShouldAbortPhase4Search
    jc   .search_aborted

    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source

    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_destination:
    call ValidateMove
    jc   .advance_destination
    call GetCurrentMoveOrderClass
    cmp  al, [SearchRootOrderPass]
    jne  .advance_destination

    inc  word [ComputerRootNodes]
    call EvaluateComputerCandidateThreePly
    cmp  byte [ComputerSearchTimedOut], 0
    jne  .search_aborted
    cmp  byte [GameState], GAME_PLAYING
    jne  .search_aborted
    cmp  byte [Phase4BestMoveFound], 0
    je   .save_candidate
    cmp  ax, [Phase4BestScore]
    jle  .advance_destination

.save_candidate:
    mov  [Phase4BestScore], ax
    mov  byte [Phase4BestMoveFound], 1
    mov  ax, si
    mov  [Phase4BestSourceIndex], al
    mov  al, bh
    mov  cl, 3
    shl  al, cl
    add  al, bl
    mov  [Phase4BestDestinationIndex], al

.advance_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination

.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source

    inc  byte [SearchRootOrderPass]
    cmp  byte [SearchRootOrderPass], 3
    jb   .next_order_pass

    cmp  byte [Phase4BestMoveFound], 0
    je   .fallback
    mov  al, [Phase4BestSourceIndex]
    mov  [ComputerSourceIndex], al
    mov  al, [Phase4BestDestinationIndex]
    mov  [ComputerDestinationIndex], al
    mov  ax, [Phase4BestScore]
    mov  [ComputerBestScore], ax
    mov  byte [ComputerCompletedDepth], 3
    call PrepareComputerMoveFromIndices
    jmp  .restore

.search_aborted:
    cmp  byte [GameState], GAME_PLAYING
    jne  .no_move

.fallback:
    ; The Phase-3 indices were never overwritten. Recreate their validated
    ; interactive state because a partial depth-three pass used the scratch
    ; selection variables internally.
    call PrepareComputerMoveFromIndices
    jmp  .restore

.no_move:
    stc

.restore:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Service clocks/blinking and enforce the Phase-4 RTC deadline. Direct test
; callers do not install the RTC, so they complete the full search.
ShouldAbortPhase4Search:
    call ServiceComputerSearchForeground
    cmp  byte [GameState], GAME_PLAYING
    jne  .abort
    cmp  byte [RTCInstalled], 0
    je   .continue
    cmp  byte [ComputerThinkSecondsElapsed], COMPUTER_SEARCH_LIMIT_SECONDS
    jb   .continue
    mov  byte [ComputerSearchTimedOut], 1
.abort:
    stc
    ret
.continue:
    clc
    ret


; Return AL=0 for promotions/valuable captures, AL=1 for other captures or
; checks, and AL=2 for quiet non-checking moves. All ValidateMove scratch state
; remains intact.
GetCurrentMoveOrderClass:
    push bx
    push dx

    call ScoreComputerCandidate
    cmp  ax, 500
    jae  .valuable
    or   ax, ax
    jnz  .tactical
    call CandidateGivesCheck
    jc   .tactical
    mov  al, 2
    jmp  .done
.valuable:
    mov  al, 0
    jmp  .done
.tactical:
    mov  al, 1
.done:
    pop  dx
    pop  bx
    ret


; Temporarily make the current validated move and report whether it checks the
; opposing king. A private 64-byte backup makes classification reversible.
CandidateGivesCheck:
    push ax
    push cx
    push di

    mov  al, [CurrentTurn]
    mov  [SearchOrderSavedCurrentTurn], al
    mov  al, [CastlingRights]
    mov  [SearchOrderSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [SearchOrderSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [SearchOrderBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call IsCurrentKingInCheck
    mov  byte [SearchMoveGivesCheck], 0
    jnc  .restore_board_start
    mov  byte [SearchMoveGivesCheck], 1

.restore_board_start:
    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [SearchOrderBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board
    mov  al, [SearchOrderSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [SearchOrderSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [SearchOrderSavedCurrentTurn]
    mov  [CurrentTurn], al

    cmp  byte [SearchMoveGivesCheck], 0
    je   .no_check
    stc
    jmp  .done
.no_check:
    clc
.done:
    pop  di
    pop  cx
    pop  ax
    ret


; Evaluate one Black root candidate through White's best reply and Black's
; best continuation. AX returns the signed score from Black's perspective.
EvaluateComputerCandidateThreePly:
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [SourceColumn]
    mov  [SearchRootSourceColumn], al
    mov  al, [SourceRow]
    mov  [SearchRootSourceRow], al
    mov  al, [SelectedPiece]
    mov  [SearchRootSelectedPiece], al
    mov  [SearchRootSourceIndex], si
    mov  al, bl
    mov  [SearchRootDestinationColumn], al
    mov  al, bh
    mov  [SearchRootDestinationRow], al
    mov  al, bh
    mov  cl, 3
    shl  al, cl
    add  al, bl
    mov  [SearchRootDestinationIndex], al
    mov  al, [PendingMoveFlags]
    mov  [SearchRootMoveFlags], al
    mov  al, [DestinationPiece]
    mov  [SearchRootCapturedPiece], al
    mov  al, [CastleRookSourceColumn]
    mov  [SearchRootCastleSourceColumn], al
    mov  al, [CastleRookDestinationColumn]
    mov  [SearchRootCastleDestinationColumn], al
    call ScoreComputerCandidate
    mov  [SearchRootGain], ax
    call GetRootRepetitionPenalty
    mov  [SearchRootPenalty], ax

    mov  al, [CurrentTurn]
    mov  [SearchSavedCurrentTurn], al
    mov  al, [CastlingRights]
    mov  [SearchSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [SearchSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_root_board:
    mov  al, [BoardPosition + di]
    mov  [SearchBoardBackup + di], al
    inc  di
    loop .save_root_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    mov  byte [SearchReplyFound], 0
    mov  word [SearchBestWhiteScore], 7FFFh
    mov  byte [SearchWhiteOrderPass], 0

.next_white_order_pass:
    xor  si, si
.next_white_source:
    call ShouldAbortPhase4Search
    jc   .search_interrupted
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_white_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_white_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_white_destination:
    call ValidateMove
    jc   .advance_white_destination
    call GetCurrentMoveOrderClass
    cmp  al, [SearchWhiteOrderPass]
    jne  .advance_white_destination

.ordered_white_reply:
    inc  word [ComputerReplyNodes]
    mov  byte [SearchReplyFound], 1
    mov  al, [SourceColumn]
    mov  [SearchWhiteSourceColumn], al
    mov  al, [SourceRow]
    mov  [SearchWhiteSourceRow], al
    mov  al, [SelectedPiece]
    mov  [SearchWhiteSelectedPiece], al
    call ScoreComputerCandidate
    mov  [SearchWhiteGain], ax

    mov  al, [CastlingRights]
    mov  [SearchPlySavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [SearchPlySavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_white_board:
    mov  al, [BoardPosition + di]
    mov  [SearchPlyBoardBackup + di], al
    inc  di
    loop .save_white_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call EvaluateBestBlackContinuation
    mov  [SearchBestBlackGain], ax

    cmp  byte [ComputerSearchTimedOut], 0
    jne  .restore_white_interrupted
    cmp  byte [GameState], GAME_PLAYING
    jne  .restore_white_interrupted
    cmp  byte [SearchBlackContinuationFound], 0
    jne  .black_has_move
    call IsCurrentKingInCheck
    jc   .white_mates
    mov  word [SearchCurrentReplyScore], 0
    jmp  .reply_scored

.white_mates:
    mov  word [SearchCurrentReplyScore], -30000
    jmp  .reply_scored

.black_has_move:
    cmp  word [SearchBestBlackGain], 30000
    je   .black_mates
    mov  ax, [SearchBestBlackGain]
    sub  ax, [SearchRootPenalty]
    mov  [SearchCurrentReplyScore], ax
    jmp  .reply_scored

.black_mates:
    mov  word [SearchCurrentReplyScore], 30000

.reply_scored:
    call RestorePostRootPosition
    mov  ax, [SearchCurrentReplyScore]
    cmp  ax, [SearchBestWhiteScore]
    jge  .test_root_cutoff
    mov  [SearchBestWhiteScore], ax

.test_root_cutoff:
    cmp  byte [Phase4BestMoveFound], 0
    je   .continue_white_scan
    mov  ax, [SearchBestWhiteScore]
    cmp  ax, [Phase4BestScore]
    jg   .continue_white_scan
    inc  word [ComputerPhase4Cutoffs]
    mov  [SearchCandidateScore], ax
    jmp  .restore_root_position

.continue_white_scan:
    mov  al, [SearchWhiteSourceColumn]
    mov  [SourceColumn], al
    mov  al, [SearchWhiteSourceRow]
    mov  [SourceRow], al
    mov  al, [SearchWhiteSelectedPiece]
    mov  [SelectedPiece], al

.advance_white_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_white_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_white_destination

.advance_white_source:
    inc  si
    cmp  si, 64
    jb   .next_white_source
    inc  byte [SearchWhiteOrderPass]
    cmp  byte [SearchWhiteOrderPass], 3
    jb   .next_white_order_pass

    cmp  byte [SearchReplyFound], 0
    jne  .ordinary_score
    call IsCurrentKingInCheck
    jc   .root_mates
    mov  word [SearchCandidateScore], 0
    jmp  .restore_root_position
.root_mates:
    mov  word [SearchCandidateScore], 30000
    jmp  .restore_root_position
.ordinary_score:
    mov  ax, [SearchBestWhiteScore]
    mov  [SearchCandidateScore], ax
    jmp  .restore_root_position

.restore_white_interrupted:
    call RestorePostRootPosition
.search_interrupted:
    mov  word [SearchCandidateScore], 8000h

.restore_root_position:
    xor  di, di
    mov  cx, 64
.restore_root_board:
    mov  al, [SearchBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_root_board
    mov  al, [SearchSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [SearchSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [SearchSavedCurrentTurn]
    mov  [CurrentTurn], al
    mov  al, [SearchRootSourceColumn]
    mov  [SourceColumn], al
    mov  al, [SearchRootSourceRow]
    mov  [SourceRow], al
    mov  al, [SearchRootSelectedPiece]
    mov  [SelectedPiece], al
    mov  ax, [SearchCandidateScore]

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Restore the board and special state that existed immediately after the Black
; root move. CurrentTurn becomes White so reply enumeration can continue.
RestorePostRootPosition:
    push ax
    push cx
    push di
    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [SearchPlyBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board
    mov  al, [SearchPlySavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [SearchPlySavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  byte [CurrentTurn], 0
    pop  di
    pop  cx
    pop  ax
    ret


; Search Black's legal third-ply continuations. Captures/checks are ordered
; ahead of quiet moves. Each non-mating leaf is evaluated positionally and
; extended through a bounded White-capture/Black-recapture quiescence pass.
; AX returns the largest Black-perspective leaf score, or 30000 for mate.
EvaluateBestBlackContinuation:
    push bx
    push cx
    push dx
    push si
    push di

    mov  byte [SearchBlackContinuationFound], 0
    mov  word [SearchBestBlackGain], 8000h
    mov  byte [SearchBlackOrderPass], 0

.next_order_pass:
    xor  si, si
.next_source:
    call ShouldAbortPhase4Search
    jc   .done
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_destination:
    call ValidateMove
    jc   .advance_destination
    call GetCurrentMoveOrderClass
    cmp  al, [SearchBlackOrderPass]
    jne  .advance_destination

.ordered_move:
    mov  byte [SearchBlackContinuationFound], 1
    inc  word [ComputerThirdPlyNodes]
    call CurrentMoveIsMate
    jc   .mate_found
    call EvaluateValidatedMoveQuiescenceBlack
    cmp  byte [ComputerSearchTimedOut], 0
    jne  .done
    cmp  ax, [SearchBestBlackGain]
    jle  .test_beta_cutoff
    mov  [SearchBestBlackGain], ax

.test_beta_cutoff:
    mov  ax, [SearchBestBlackGain]
    cmp  ax, [SearchBestWhiteScore]
    jl   .advance_destination
    inc  word [ComputerPhase4Cutoffs]
    jmp  .done

.mate_found:
    mov  word [SearchBestBlackGain], 30000
    jmp  .done

.advance_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination
.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source
    inc  byte [SearchBlackOrderPass]
    cmp  byte [SearchBlackOrderPass], 3
    jb   .next_order_pass

.done:
    mov  ax, [SearchBestBlackGain]
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Return carry set only when the current validated Black continuation gives
; checkmate. The board and all rule state are restored exactly.
CurrentMoveIsMate:
    push ax
    push cx
    push di

    mov  al, [CurrentTurn]
    mov  [SearchOrderSavedCurrentTurn], al
    mov  al, [CastlingRights]
    mov  [SearchOrderSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [SearchOrderSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [SearchOrderBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    mov  byte [SearchMoveIsMate], 0
    call IsCurrentKingInCheck
    jnc  .restore
    call HasAnyLegalMove
    jnc  .restore
    mov  byte [SearchMoveIsMate], 1

.restore:
    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [SearchOrderBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board
    mov  al, [SearchOrderSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [SearchOrderSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [SearchOrderSavedCurrentTurn]
    mov  [CurrentTurn], al
    cmp  byte [SearchMoveIsMate], 0
    je   .not_mate
    stc
    jmp  .done
.not_mate:
    clc
.done:
    pop  di
    pop  cx
    pop  ax
    ret


; Temporarily apply the move most recently accepted by ValidateMove. This
; generic Phase-4 version works for either side and includes en passant,
; castling, automatic queen promotion, and the special-rule state required by
; the following ply. It performs no drawing, sound, history, or clock change.
ApplySearchRootMove:
ApplyValidatedSearchMove:
    push ax
    push bx
    push dx
    push si
    push di

    xor  ax, ax
    mov  al, [SourceRow]
    mov  si, ax
    shl  si, 1
    shl  si, 1
    shl  si, 1
    xor  ax, ax
    mov  al, [SourceColumn]
    add  si, ax
    mov  byte [BoardPosition + si], EMPTY
    xor  ax, ax
    mov  al, [CandidateRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  al, [SelectedPiece]
    mov  [BoardPosition + di], al

    test byte [PendingMoveFlags], MOVE_FLAG_EN_PASSANT
    jz   .not_en_passant
    xor  di, di
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  byte [BoardPosition + di], EMPTY

.not_en_passant:
    test byte [PendingMoveFlags], MOVE_FLAG_CASTLE
    jz   .not_castle
    xor  ax, ax
    mov  al, [SourceRow]
    mov  si, ax
    shl  si, 1
    shl  si, 1
    shl  si, 1
    xor  ax, ax
    mov  al, [CastleRookSourceColumn]
    add  si, ax

    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CastleRookDestinationColumn]
    add  di, ax
    mov  al, [BoardPosition + si]
    mov  byte [BoardPosition + si], EMPTY
    mov  [BoardPosition + di], al

.not_castle:
    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, PAWN
    jne  .promotion_done
    test byte [SelectedPiece], BLACK
    jz   .white_promotion
    cmp  byte [CandidateRow], 7
    jne  .promotion_done
    xor  ax, ax
    mov  al, [CandidateRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  byte [BoardPosition + di], BLACK + QUEEN
    jmp  .promotion_done

.white_promotion:
    cmp  byte [CandidateRow], 0
    jne  .promotion_done
    xor  ax, ax
    mov  al, [CandidateColumn]
    mov  di, ax
    mov  byte [BoardPosition + di], QUEEN

.promotion_done:
    mov  byte [EnPassantSquare], NO_EN_PASSANT
    test byte [PendingMoveFlags], MOVE_FLAG_PAWN_DOUBLE
    jz   .en_passant_state_done
    xor  ax, ax
    mov  al, [SourceRow]
    xor  bx, bx
    mov  bl, [CandidateRow]
    add  ax, bx
    shr  ax, 1
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    xor  bx, bx
    mov  bl, [SourceColumn]
    add  ax, bx
    mov  [EnPassantSquare], al

.en_passant_state_done:
    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, KING
    jne  .not_king
    test byte [SelectedPiece], BLACK
    jz   .white_king
    and  byte [CastlingRights], 0F3h
    jmp  .capture_right

.white_king:
    and  byte [CastlingRights], 0FCh
    jmp  .capture_right

.not_king:
    cmp  al, ROOK
    jne  .capture_right
    mov  al, [SourceRow]
    mov  ah, 0
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    add  al, [SourceColumn]
    call ClearCastlingRightForSquare

.capture_right:
    mov  al, [DestinationPiece]
    and  al, 07h
    cmp  al, ROOK
    jne  .done
    mov  al, [CandidateRow]
    mov  ah, 0
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    add  al, [CandidateColumn]
    call ClearCastlingRightForSquare

.done:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; Keep both clocks and the reversible status text live during a long search.
; CurrentTurn is temporarily forced to Black for UI state; the RTC ISR also
; independently routes all ComputerMoveActive time to Black.
ServiceComputerSearchForeground:
    push ax

    mov  al, [CurrentTurn]
    mov  [SearchServiceSavedTurn], al
    mov  byte [CurrentTurn], BLACK
    call ServiceClockUpdates
    call ServiceComputerThinkingBlink
    mov  al, [SearchServiceSavedTurn]
    mov  [CurrentTurn], al

    pop  ax
    ret


; ------------------------------------------------------------------
; ScoreComputerCandidate
;
; ValidateMove has already populated DestinationPiece and PendingMoveFlags.
;
; Output:
;   AX = non-negative immediate material gain for Black.
;
; Piece values are centipawn-style integers:
; Pawn=100, Knight=320, Bishop=330, Rook=500, Queen=900.
; Promotion adds Queen-Pawn = 800. An en-passant capture is worth one pawn
; even though its destination square is empty.
; ------------------------------------------------------------------
ScoreComputerCandidate:
    push bx

    xor  ax, ax
    test byte [PendingMoveFlags], MOVE_FLAG_EN_PASSANT
    jz   .ordinary_destination
    mov  ax, 100
    jmp  .promotion

.ordinary_destination:
    xor  bx, bx
    mov  bl, [DestinationPiece]
    and  bl, 07h
    shl  bx, 1
    mov  ax, [PieceMaterialValues + bx]

.promotion:
    mov  bl, [SelectedPiece]
    and  bl, 07h
    cmp  bl, PAWN
    jne  .done
    test byte [CurrentTurn], BLACK
    jz   .white_promotion
    cmp  byte [CandidateRow], 7
    jne  .done
    add  ax, 800
    jmp  .done

.white_promotion:
    cmp  byte [CandidateRow], 0
    jne  .done
    add  ax, 800

.done:
    pop  bx
    ret


; ------------------------------------------------------------------
; EvaluatePositionBlack
;
; Return a signed Black-perspective score for the current board. Material is
; combined with small signed piece-square tables. Black squares are mirrored
; vertically before the table lookup, so one table serves both colors.
; ------------------------------------------------------------------
EvaluatePositionBlack:
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    xor  dx, dx
    xor  si, si

.next_square:
    mov  al, [BoardPosition + si]
    xor  ah, ah
    mov  bp, ax
    and  al, 07h
    jz   .advance_square

    xor  bx, bx
    mov  bl, al
    shl  bx, 1
    mov  cx, [PieceMaterialValues + bx]
    mov  di, [PieceSquareTablePointers + bx]

    mov  bx, si
    test bp, BLACK
    jz   .table_index_ready
    xor  bl, 56

.table_index_ready:
    mov  al, [di + bx]
    cbw
    add  cx, ax
    test bp, BLACK
    jz   .white_piece
    add  dx, cx
    jmp  .advance_square

.white_piece:
    sub  dx, cx

.advance_square:
    inc  si
    cmp  si, 64
    jb   .next_square

    mov  ax, dx
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Temporarily apply the move most recently accepted by ValidateMove, return
; the resulting Black-perspective positional score, and restore all rule state.
EvaluateValidatedMovePositionBlack:
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [CurrentTurn]
    mov  [PositionProbeSavedTurn], al
    mov  al, [CastlingRights]
    mov  [PositionProbeSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [PositionProbeSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [PositionProbeBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call EvaluatePositionBlack
    mov  [PositionProbeScore], ax

    xor  di, di
    mov  cx, 64
.restore_board:
    mov  al, [PositionProbeBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board
    mov  al, [PositionProbeSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [PositionProbeSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [PositionProbeSavedTurn]
    mov  [CurrentTurn], al
    mov  ax, [PositionProbeScore]

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Return 75 when the current Black root candidate exactly reverses Black's
; preceding move. The history record two slots behind HistoryNext is Black's
; last move whenever it is Black to move. This breaks zero-score rook shuffles
; without making repetition illegal when it is tactically necessary.
GetRootRepetitionPenalty:
    push bx
    push di

    xor  ax, ax
    cmp  word [HistoryCount], 3
    jb   .done
    mov  bl, [HistoryNext]
    sub  bl, 2
    xor  bh, bh
    mov  di, bx
    shl  di, 1
    shl  di, 1
    shl  di, 1
    lea  di, [MoveHistory + di]
    test byte [di + 2], BLACK
    jz   .done
    mov  al, [di + 0]
    cmp  al, [SearchRootDestinationIndex]
    jne  .no_penalty
    mov  al, [di + 1]
    cmp  al, [SearchRootSourceIndex]
    jne  .no_penalty
    mov  ax, 75
    inc  word [ComputerRepetitionPenalties]
    jmp  .done

.no_penalty:
    xor  ax, ax
.done:
    pop  di
    pop  bx
    ret


; ------------------------------------------------------------------
; EvaluateValidatedMoveQuiescenceBlack
;
; Apply a validated Black third-ply move, then stabilize the leaf through all
; legal White captures/promotions and all legal Black capture replies. Either
; side may stand pat. This bounded two-ply capture extension avoids evaluating
; the principal search in the middle of a simple exchange while remaining
; practical on the 4.9 MHz 8088. AX is always from Black's perspective.
; ------------------------------------------------------------------
EvaluateValidatedMoveQuiescenceBlack:
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [CurrentTurn]
    mov  [QuiescenceBaseSavedTurn], al
    mov  al, [CastlingRights]
    mov  [QuiescenceBaseSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [QuiescenceBaseSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_base_board:
    mov  al, [BoardPosition + di]
    mov  [QuiescenceBaseBoardBackup + di], al
    inc  di
    loop .save_base_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call EvaluatePositionBlack
    mov  [QuiescenceBestWhiteScore], ax
    inc  word [ComputerQuiescenceLeaves]
    xor  si, si

.next_white_source:
    call ShouldAbortPhase4Search
    jc   .restore_base
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_white_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_white_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_white_destination:
    call ValidateMove
    jc   .advance_white_destination
    call ScoreComputerCandidate
    or   ax, ax
    jz   .advance_white_destination

    mov  al, [SourceColumn]
    mov  [QuiescenceWhiteSourceColumn], al
    mov  al, [SourceRow]
    mov  [QuiescenceWhiteSourceRow], al
    mov  al, [SelectedPiece]
    mov  [QuiescenceWhiteSelectedPiece], al
    mov  al, [CastlingRights]
    mov  [QuiescenceWhiteSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [QuiescenceWhiteSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_post_black_board:
    mov  al, [BoardPosition + di]
    mov  [QuiescenceWhiteBoardBackup + di], al
    inc  di
    loop .save_post_black_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call EvaluatePositionBlack
    mov  [QuiescenceBestBlackScore], ax
    inc  word [ComputerQuiescenceLeaves]
    call SearchBlackQuiescenceCaptures

    xor  di, di
    mov  cx, 64
.restore_post_black_board:
    mov  al, [QuiescenceWhiteBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_post_black_board
    mov  al, [QuiescenceWhiteSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [QuiescenceWhiteSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  byte [CurrentTurn], 0

    mov  ax, [QuiescenceBestBlackScore]
    cmp  ax, [QuiescenceBestWhiteScore]
    jge  .white_source_restored
    mov  [QuiescenceBestWhiteScore], ax

.white_source_restored:
    mov  al, [QuiescenceWhiteSourceColumn]
    mov  [SourceColumn], al
    mov  al, [QuiescenceWhiteSourceRow]
    mov  [SourceRow], al
    mov  al, [QuiescenceWhiteSelectedPiece]
    mov  [SelectedPiece], al

.advance_white_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_white_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_white_destination
.advance_white_source:
    inc  si
    cmp  si, 64
    jb   .next_white_source

.restore_base:
    xor  di, di
    mov  cx, 64
.restore_base_board:
    mov  al, [QuiescenceBaseBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_base_board
    mov  al, [QuiescenceBaseSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [QuiescenceBaseSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  al, [QuiescenceBaseSavedTurn]
    mov  [CurrentTurn], al
    mov  ax, [QuiescenceBestWhiteScore]

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret


; Search all legal Black captures/promotions from the current quiescence node.
; QuiescenceBestBlackScore already contains Black's stand-pat score.
SearchBlackQuiescenceCaptures:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor  si, si
.next_source:
    call ShouldAbortPhase4Search
    jc   .done
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source
    mov  [SelectedPiece], al
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al
    xor  bx, bx

.next_destination:
    call ValidateMove
    jc   .advance_destination
    call ScoreComputerCandidate
    or   ax, ax
    jz   .advance_destination

    mov  al, [SourceColumn]
    mov  [QuiescenceBlackSourceColumn], al
    mov  al, [SourceRow]
    mov  [QuiescenceBlackSourceRow], al
    mov  al, [SelectedPiece]
    mov  [QuiescenceBlackSelectedPiece], al
    mov  al, [CastlingRights]
    mov  [QuiescenceBlackSavedCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [QuiescenceBlackSavedEnPassantSquare], al
    xor  di, di
    mov  cx, 64
.save_board:
    mov  al, [BoardPosition + di]
    mov  [QuiescenceBlackBoardBackup + di], al
    inc  di
    loop .save_board

    call ApplyValidatedSearchMove
    xor  byte [CurrentTurn], BLACK
    call EvaluatePositionBlack
    cmp  ax, [QuiescenceBestBlackScore]
    jle  .restore_board
    mov  [QuiescenceBestBlackScore], ax

.restore_board:
    inc  word [ComputerQuiescenceLeaves]
    xor  di, di
    mov  cx, 64
.restore_board_loop:
    mov  al, [QuiescenceBlackBoardBackup + di]
    mov  [BoardPosition + di], al
    inc  di
    loop .restore_board_loop
    mov  al, [QuiescenceBlackSavedCastlingRights]
    mov  [CastlingRights], al
    mov  al, [QuiescenceBlackSavedEnPassantSquare]
    mov  [EnPassantSquare], al
    mov  byte [CurrentTurn], BLACK
    mov  al, [QuiescenceBlackSourceColumn]
    mov  [SourceColumn], al
    mov  al, [QuiescenceBlackSourceRow]
    mov  [SourceRow], al
    mov  al, [QuiescenceBlackSelectedPiece]
    mov  [SelectedPiece], al

.advance_destination:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination
.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source
.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Convert the two saved row-major square indices into the interactive move
; state, independently validate the move, and set exactly one MoveMask bit so
; HandleEnterSelection can use its normal defense-in-depth commit path.
PrepareComputerMoveFromIndices:
    push ax
    push bx
    push cx
    push dx
    push di

    xor  ax, ax
    mov  al, [ComputerSourceIndex]
    cmp  al, 63
    jbe  .source_in_range
    stc
    jmp  .restore

.source_in_range:
    mov  di, ax
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  cl, 3
    shr  ax, cl
    mov  [SourceRow], al

    mov  al, [BoardPosition + di]
    test al, 07h
    jnz  .source_occupied
    stc
    jmp  .restore

.source_occupied:
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jz   .source_owned
    stc
    jmp  .restore

.source_owned:
    mov  [SelectedPiece], al
    xor  ax, ax
    mov  al, [ComputerDestinationIndex]
    cmp  al, 63
    jbe  .destination_in_range
    stc
    jmp  .restore

.destination_in_range:
    mov  dl, al
    and  dl, 07h
    mov  [CursorColumn], dl
    mov  cl, 3
    shr  ax, cl
    mov  [CursorRow], al

    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call ValidateMove
    jnc  .legal
    stc
    jmp  .restore

.legal:
    call ClearMoveMask
    xor  ax, ax
    mov  al, [CursorRow]
    mov  di, ax
    mov  al, 1
    mov  cl, [CursorColumn]
    shl  al, cl
    or   [MoveMask + di], al
    clc

.restore:
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


DrawComputerThinkingXor:
    push ax
    push cx
    push dx
    push si

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, 12
    mov  dx, 56
    mov  si, ComputerThinkingText
    call DrawSmallStringXor
    pop  ax
    mov  [SmallDrawSegment], ax

    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; InstallRTCClock / UninstallRTCClock
;
; Installs INT 7Ah before enabling the HD146818P periodic interrupt. The
; original vector and complete Register A/B values are preserved. Register C
; is read to clear any pending RTC interrupt flags.
;
; Register A keeps its existing divider bits and receives RS=0Fh, the 2 Hz
; rate already observed in the QX-11 BIOS setup. Register B keeps every
; existing mode bit and adds PIE.
; ------------------------------------------------------------------
InstallRTCClock:
    push ax
    push bx
    push dx
    push ds
    push es

    cmp  byte [cs:RTCInstalled], 0
    jne  .done

    mov  ax, 357Ah
    int  21h
    mov  [cs:OldInt7AOffset], bx
    mov  [cs:OldInt7ASegment], es

    push cs
    pop  ds
    mov  dx, RTCInterruptHandler
    mov  ax, 257Ah
    int  21h

    pushf
    cli

    mov  al, RTC_REGISTER_A
    out  RTC_INDEX_PORT, al
    in   al, RTC_DATA_PORT
    mov  [SavedRTCRegisterA], al

    mov  al, RTC_REGISTER_B
    out  RTC_INDEX_PORT, al
    in   al, RTC_DATA_PORT
    mov  [SavedRTCRegisterB], al

    ; UIP is read-only. Preserve the divider selection but install RS=0Fh.
    mov  al, [SavedRTCRegisterA]
    and  al, 70h
    or   al, RTC_RATE_2HZ
    mov  ah, al
    mov  al, RTC_REGISTER_A
    out  RTC_INDEX_PORT, al
    mov  al, ah
    out  RTC_DATA_PORT, al

    ; Clear stale PF/AF/UF/IRQF flags before PIE can assert the IRQ output.
    mov  al, RTC_REGISTER_C
    out  RTC_INDEX_PORT, al
    in   al, RTC_DATA_PORT

    mov  ah, [SavedRTCRegisterB]
    or   ah, RTC_PIE
    mov  al, RTC_REGISTER_B
    out  RTC_INDEX_PORT, al
    mov  al, ah
    out  RTC_DATA_PORT, al

    mov  byte [RTCSubsecondTicks], 0
    mov  byte [WhiteSecondsPending], 0
    mov  byte [BlackSecondsPending], 0
    mov  byte [RTCInstalled], 1
    popf

.done:
    pop  es
    pop  ds
    pop  dx
    pop  bx
    pop  ax
    ret


UninstallRTCClock:
    push ax
    push dx
    push ds

    cmp  byte [cs:RTCInstalled], 0
    je   .done

    ; Stop this program's periodic source before returning INT 7Ah to DOS.
    pushf
    cli

    mov  al, RTC_REGISTER_B
    out  RTC_INDEX_PORT, al
    mov  al, [cs:SavedRTCRegisterB]
    out  RTC_DATA_PORT, al

    mov  al, RTC_REGISTER_A
    out  RTC_INDEX_PORT, al
    mov  al, [cs:SavedRTCRegisterA]
    and  al, 7Fh
    out  RTC_DATA_PORT, al

    mov  al, RTC_REGISTER_C
    out  RTC_INDEX_PORT, al
    in   al, RTC_DATA_PORT
    popf

    mov  dx, [cs:OldInt7AOffset]
    mov  ax, [cs:OldInt7ASegment]
    mov  ds, ax
    mov  ax, 257Ah
    int  21h

    mov  byte [cs:RTCInstalled], 0

.done:
    pop  ds
    pop  dx
    pop  ax
    ret


; ------------------------------------------------------------------
; RTCInterruptHandler -- QX-11 INT 7Ah
;
; Reading HD146818P Register C clears IRQF/PF and releases the RTC IRQ output.
; At the programmed 2 Hz rate, two PF events become one elapsed second.
; Pending seconds are attributed here, before CurrentTurn can change.
;
; No VRAM or line-renderer state is touched. The original INT 7Ah handler is
; tail-chained afterward so any QX-11 gate-array acknowledgement it performs
; remains intact.
; ------------------------------------------------------------------
RTCInterruptHandler:
    push ax
    push ds

    push cs
    pop  ds

    mov  al, RTC_REGISTER_C
    out  RTC_INDEX_PORT, al
    in   al, RTC_DATA_PORT
    test al, RTC_PERIODIC_FLAG
    jz   .chain

    ; Queue the visual blink at the native 2 Hz rate. The foreground routine
    ; performs the reversible VRAM update.
    cmp  byte [ComputerMoveActive], 0
    je   .count_time
    cmp  byte [ComputerThinkBlinkPending], 0FFh
    je   .count_time
    inc  byte [ComputerThinkBlinkPending]

.count_time:
    cmp  byte [HintActive], 0
    je   .pause_check
    cmp  byte [HintBlinkPending], 0FFh
    je   .pause_check
    inc  byte [HintBlinkPending]

.pause_check:
    cmp  byte [ClockPaused], 0
    jne  .chain
    inc  byte [RTCSubsecondTicks]
    cmp  byte [RTCSubsecondTicks], RTC_TICKS_PER_SECOND
    jb   .chain
    mov  byte [RTCSubsecondTicks], 0

    cmp  byte [GameState], GAME_PLAYING
    jne  .chain

    ; Phase 3 temporarily sets CurrentTurn to White while validating replies.
    ; The real clock owner is still Black for the complete automatic turn.
    cmp  byte [ComputerMoveActive], 0
    jne  .black
    test byte [CurrentTurn], BLACK
    jnz  .black
    cmp  byte [WhiteSecondsPending], 0FFh
    je   .chain
    inc  byte [WhiteSecondsPending]
    jmp  .chain

.black:
    cmp  byte [BlackSecondsPending], 0FFh
    je   .count_computer_thinking
    inc  byte [BlackSecondsPending]

.count_computer_thinking:
    cmp  byte [ComputerMoveActive], 0
    je   .chain
    cmp  byte [ComputerThinkSecondsElapsed], 0FFh
    je   .chain
    inc  byte [ComputerThinkSecondsElapsed]

.chain:
    pop  ds
    pop  ax

    cmp  word [cs:OldInt7ASegment], 0
    jne  .tail_chain
    cmp  word [cs:OldInt7AOffset], 0
    je   .iret

.tail_chain:
    push word [cs:OldInt7ASegment]
    push word [cs:OldInt7AOffset]
    retf

.iret:
    iret


; ------------------------------------------------------------------
; DrawCursorFrame / EraseCursorFrame
;
; XOR is reversible, so drawing and erasing use the same operation.
; Preserves all registers.
; ------------------------------------------------------------------
DrawCursorFrame:
EraseCursorFrame:
    push bx

    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call DrawSelectionFrameXor

    pop  bx
    ret


; ------------------------------------------------------------------
; HandleEnterSelection
;
; SELECT_SOURCE:
;   Reject an empty square or an opponent's piece. Otherwise remember
;   its coordinates and piece code, then enter SELECT_DEST mode.
;
; SELECT_DEST:
;   Accept only a destination marked in MoveMask by ValidateMove.
;   If an opponent occupies the destination, restore its masked background.
;   Then erase the moving piece at its source, replace both entries in
;   BoardPosition, and draw the moving piece at its destination.
;   Selecting the source square again cancels the pending move.
;
; After a successful move, CurrentTurn changes between White and Black.
; Move markers are erased before any piece or BoardPosition entry is changed.
; Preserves all registers.
; ------------------------------------------------------------------
HandleEnterSelection:
    push ax
    push bx
    push dx
    push si
    push di

    cmp  byte [SelectionState], SELECT_DEST
    je   .finish_move

    ; Convert cursor row/column to BoardPosition[row * 8 + column].
    call GetCursorBoardIndex
    mov  al, [BoardPosition + di]
    test al, 07h
    jnz  .source_occupied

    call PlayIllegalMoveSound
    ; Keep this 8088-safe.  A direct conditional jump to .done is too far
    ; for the 8088's signed 8-bit Jcc encoding.  Without "cpu 8086", NASM
    ; can silently emit a 386 near-Jcc (0F 84), which crashes on an 8088.
    jmp  .done               ; An empty source square cannot be selected.

.source_occupied:
    ; A piece belongs to the current player when its BLACK bit matches
    ; CurrentTurn. Reject opponent pieces without changing selection state.
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jz   .source_owned
    call PlayIllegalMoveSound
    jmp  .done

.source_owned:
    mov  [SelectedPiece], al
    mov  al, [CursorColumn]
    mov  [SourceColumn], al
    mov  al, [CursorRow]
    mov  [SourceRow], al
    mov  byte [SelectionState], SELECT_DEST

    ; Leave a small reversible marker around the selected source.
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    call DrawSourceMarkerXor
    call GenerateMoveMask
    call DrawMoveMarkersXor
    jmp  .done

.finish_move:
    ; Enter on the original square cancels the pending move.
    mov  al, [CursorColumn]
    cmp  al, [SourceColumn]
    jne  .different_square
    mov  al, [CursorRow]
    cmp  al, [SourceRow]
    jne  .different_square

    ; Remove all reversible markers and cancel the pending move.
    call DrawMoveMarkersXor
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    call DrawSourceMarkerXor
    call ClearMoveMask
    mov  byte [SelectionState], SELECT_SOURCE
    jmp  .done

.different_square:
    ; A destination can be entered only when ValidateMove placed it in
    ; MoveMask. An unmarked square leaves the source selected.
    call IsCursorMoveMarked
    jnc  .marked_destination
    call PlayIllegalMoveSound
    jmp  .done

.marked_destination:
    ; Re-run the complete rule test before committing. MoveMask was generated
    ; from the same position, but this keeps the execution path independently
    ; protected by ValidateMove and its king-safety check.
    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call ValidateMove
    jnc  .destination_revalidated
    jmp  .done

.destination_revalidated:
    ; DI = destination BoardPosition index. Save it in memory so calls to
    ; the graphics routines cannot accidentally change the destination.
    call GetCursorBoardIndex
    mov  [DestinationIndex], di

    ; Remember the exact destination code.
    mov  al, [BoardPosition + di]
    mov  [CapturedPiece], al

    ; Defense in depth: a king is never a capturable piece. ValidateMove
    ; already excludes a king destination from MoveMask, but the final
    ; executor checks the live BoardPosition again before erasing anything.
    ; This protects the board even if a stale/corrupted marker is present.
    mov  ah, al
    and  ah, 07h
    cmp  ah, KING
    jne  .destination_not_king
    jmp  .done

.destination_not_king:
    test al, 07h
    jz   .destination_allowed

    ; An occupied destination is legal only when its side bit differs
    ; from the selected piece. If both side bits match, leave the source
    ; selected so the player can move the cursor to another destination.
    mov  ah, al
    xor  ah, [SelectedPiece]
    test ah, BLACK
    jnz  .destination_allowed
    jmp  .done

.destination_allowed:
    ; Freeze the special-move classification produced by the final
    ; ValidateMove call. For en passant this also resolves the captured pawn's
    ; actual square, which differs from the empty destination square.
    call PrepareCommittedSpecialMove
    jnc  .special_move_ready
    jmp  .done

.special_move_ready:
    ; The move will proceed. Remove every move marker while BoardPosition
    ; still describes the position against which they were drawn.
    cmp  byte [ComputerMoveActive], 0
    jne  .markers_removed
    call DrawMoveMarkersXor

    ; Remove the persistent source marker.
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    call DrawSourceMarkerXor

.markers_removed:

    ; If an opponent occupies the destination, restore the board beneath its
    ; opaque silhouette. Its board entry is replaced by the mover below.
    mov  al, [CapturedPiece]
    test al, 07h
    jz   .destination_empty
    mov  al, [CapturedPiece]
    mov  bl, [SpecialCaptureColumn]
    mov  bh, [SpecialCaptureRow]
    call ErasePieceCodeOpaque

.destination_empty:
    ; Erase the moving piece from its source.
    mov  al, [SelectedPiece]
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    call ErasePieceCodeOpaque

    ; Clear the source BoardPosition entry.
    xor  di, di
    mov  al, [SourceRow]
    xor  ah, ah
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [SourceColumn]
    add  di, ax
    mov  byte [BoardPosition + di], EMPTY

    ; En passant captures from the pawn's adjacent square rather than from
    ; the destination. Clear that square before placing the moving pawn.
    test byte [CommittedMoveFlags], MOVE_FLAG_EN_PASSANT
    jz   .en_passant_board_done
    xor  ax, ax
    mov  al, [SpecialCaptureRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [SpecialCaptureColumn]
    add  di, ax
    mov  byte [BoardPosition + di], EMPTY

.en_passant_board_done:
    ; Replace the captured/empty destination with the selected piece.
    mov  di, [DestinationIndex]
    mov  al, [SelectedPiece]
    mov  [BoardPosition + di], al

    ; Draw the selected piece at the destination.
    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call DrawPieceCodeOpaque

    ; Castling also moves the rook. Promotion then replaces a pawn on its
    ; final rank after the player chooses Q, R, B, or N.
    call CommitCastlingRookMove
    call HandlePromotionIfRequired

    ; Erase the old recent-move list, append this completed move to the
    ; persistent circular history, update special-rule state for the next
    ; player, then draw the refreshed list.
    call DrawRecentMovesXor
    call RecordCompletedMove
    call UpdateSpecialRuleState
    call DrawRecentMovesXor

    ; Give immediate foreground feedback while the completed-move state is
    ; still available. En-passant captures also leave CapturedPiece nonzero.
    mov  al, [CapturedPiece]
    test al, 07h
    jz   .ordinary_move_sound
    call PlayCaptureSound
    jmp  .move_sound_done

.ordinary_move_sound:
    call PlayMoveSound

.move_sound_done:
    mov  byte [CapturedPiece], EMPTY
    mov  byte [CommittedMoveFlags], 0
    mov  byte [SelectionState], SELECT_SOURCE
    call ClearMoveMask
    call AdvanceTurn

.done:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; PrepareCommittedSpecialMove
;
; Freezes the special classification produced by the final ValidateMove and
; preserves the rule state that belongs in the history record. En passant
; resolves and independently verifies the captured pawn's actual square.
;
; Carry clear = ready to commit; carry set = special state is inconsistent.
; Preserves all registers.
; ------------------------------------------------------------------
PrepareCommittedSpecialMove:
    push ax
    push bx

    mov  al, [PendingMoveFlags]
    mov  [CommittedMoveFlags], al
    mov  al, [CastlingRights]
    mov  [PreviousCastlingRights], al
    mov  al, [EnPassantSquare]
    mov  [PreviousEnPassantSquare], al
    mov  byte [PromotionPiece], EMPTY

    mov  al, [CursorColumn]
    mov  [SpecialCaptureColumn], al
    mov  al, [CursorRow]
    mov  [SpecialCaptureRow], al

    test byte [CommittedMoveFlags], MOVE_FLAG_EN_PASSANT
    jz   .ready

    mov  al, [SourceRow]
    mov  [SpecialCaptureRow], al
    mov  bl, [SpecialCaptureColumn]
    mov  bh, [SpecialCaptureRow]
    call GetBoardPieceAt
    jc   .invalid
    mov  ah, al
    and  al, 07h
    cmp  al, PAWN
    jne  .invalid
    xor  ah, [SelectedPiece]
    test ah, BLACK
    jz   .invalid
    ; AH was used for the side comparison. Reload the exact pawn code.
    mov  bl, [SpecialCaptureColumn]
    mov  bh, [SpecialCaptureRow]
    call GetBoardPieceAt
    mov  [CapturedPiece], al

.ready:
    clc
    jmp  .restore

.invalid:
    stc

.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; CommitCastlingRookMove
;
; The king has already been committed and drawn. If this is castling, move
; the verified rook on both the logical board and the display.
; Preserves all registers.
; ------------------------------------------------------------------
CommitCastlingRookMove:
    push ax
    push bx
    push di

    test byte [CommittedMoveFlags], MOVE_FLAG_CASTLE
    jz   .done

    mov  bl, [CastleRookSourceColumn]
    mov  bh, [SourceRow]
    call GetBoardPieceAt
    mov  [CastleRookPiece], al
    call ErasePieceCodeOpaque

    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CastleRookSourceColumn]
    add  di, ax
    mov  byte [BoardPosition + di], EMPTY

    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CastleRookDestinationColumn]
    add  di, ax
    mov  al, [CastleRookPiece]
    mov  [BoardPosition + di], al

    mov  bl, [CastleRookDestinationColumn]
    mov  bh, [SourceRow]
    call DrawPieceCodeOpaque

.done:
    pop  di
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; HandlePromotionIfRequired
;
; A pawn on its last rank must be replaced before the opponent's position is
; evaluated. Display a compact prompt and wait for Q/R/B/N. Esc retains its
; global meaning and exits to DOS.
; Preserves all registers.
; ------------------------------------------------------------------
HandlePromotionIfRequired:
    push ax
    push bx
    push dx
    push di

    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, PAWN
    jne  .done

    test byte [SelectedPiece], BLACK
    jnz  .black_pawn
    cmp  byte [CursorRow], 0
    jne  .done
    jmp  .promotion_required

.black_pawn:
    cmp  byte [CursorRow], 7
    jne  .done

.promotion_required:
    ; Computer promotion is always to a queen. No prompt was drawn,
    ; so enter below the human prompt-erasure point.
    cmp  byte [ComputerMoveActive], 0
    je   .human_promotion
    mov  dl, QUEEN
    jmp  .install_choice

.human_promotion:
    call DrawPromotionPromptXor

.wait_for_choice:
    xor  ax, ax
    int  16h
    cmp  al, 1Bh
    jne  .not_escape
    mov  ax, 4C00h
    int  21h

.not_escape:
    and  al, 0DFh
    cmp  al, 'Q'
    jne  .not_queen
    mov  dl, QUEEN
    jmp  .choice_ready

.not_queen:
    cmp  al, 'R'
    jne  .not_rook
    mov  dl, ROOK
    jmp  .choice_ready

.not_rook:
    cmp  al, 'B'
    jne  .not_bishop
    mov  dl, BISHOP
    jmp  .choice_ready

.not_bishop:
    cmp  al, 'N'
    jne  .wait_for_choice
    mov  dl, KNIGHT

.choice_ready:
    call DrawPromotionPromptXor

.install_choice:
    ; Erase the pawn that was just drawn at the destination.
    mov  al, [SelectedPiece]
    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call ErasePieceCodeOpaque

    mov  al, [SelectedPiece]
    and  al, BLACK
    or   al, dl
    mov  [PromotionPiece], al
    mov  di, [DestinationIndex]
    mov  [BoardPosition + di], al

    mov  bl, [CursorColumn]
    mov  bh, [CursorRow]
    call DrawPieceCodeOpaque
    or   byte [CommittedMoveFlags], MOVE_FLAG_PROMOTION

.done:
    pop  di
    pop  dx
    pop  bx
    pop  ax
    ret


DrawPromotionPromptXor:
    push cx
    push dx
    push si

    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, PROMOTION_PROMPT_X
    mov  dx, PROMOTION_TITLE_Y
    mov  si, PromoteTitle
    call DrawSmallStringXor
    mov  cx, PROMOTION_PROMPT_X
    mov  dx, PROMOTION_CHOICES_Y
    mov  si, PromoteChoices
    call DrawSmallStringXor

    pop  si
    pop  dx
    pop  cx
    ret


; ------------------------------------------------------------------
; UpdateSpecialRuleState
;
; Called after the move has been recorded with the previous rule state.
; Creates the next one-move en-passant opportunity and permanently removes
; castling rights after king/rook movement or a rook capture.
; Preserves all registers.
; ------------------------------------------------------------------
UpdateSpecialRuleState:
    push ax
    push bx

    mov  byte [EnPassantSquare], NO_EN_PASSANT
    test byte [CommittedMoveFlags], MOVE_FLAG_PAWN_DOUBLE
    jz   .en_passant_updated

    xor  ax, ax
    mov  al, [SourceRow]
    xor  bx, bx
    mov  bl, [CursorRow]
    add  ax, bx
    shr  ax, 1
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    xor  bx, bx
    mov  bl, [SourceColumn]
    add  ax, bx
    mov  [EnPassantSquare], al

.en_passant_updated:
    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, KING
    jne  .not_king
    test byte [SelectedPiece], BLACK
    jnz  .black_king
    and  byte [CastlingRights], 0FCh
    jmp  .check_capture

.black_king:
    and  byte [CastlingRights], 0F3h
    jmp  .check_capture

.not_king:
    cmp  al, ROOK
    jne  .check_capture
    xor  ax, ax
    mov  al, [SourceRow]
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    add  al, [SourceColumn]
    call ClearCastlingRightForSquare

.check_capture:
    mov  al, [CapturedPiece]
    and  al, 07h
    cmp  al, ROOK
    jne  .done
    xor  ax, ax
    mov  al, [SpecialCaptureRow]
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    add  al, [SpecialCaptureColumn]
    call ClearCastlingRightForSquare

.done:
    pop  bx
    pop  ax
    ret


; Input AL = board square index. Clears the right tied to an original rook
; square. Calling this for any other square is harmless.
ClearCastlingRightForSquare:
    cmp  al, 0
    jne  .not_a8
    and  byte [CastlingRights], 0F7h
    ret
.not_a8:
    cmp  al, 7
    jne  .not_h8
    and  byte [CastlingRights], 0FBh
    ret
.not_h8:
    cmp  al, 56
    jne  .not_a1
    and  byte [CastlingRights], 0FDh
    ret
.not_a1:
    cmp  al, 63
    jne  .done
    and  byte [CastlingRights], 0FEh
.done:
    ret


; ------------------------------------------------------------------
; ValidateMove
;
; Input:
;   BL = candidate destination column, 0..7
;   BH = candidate destination row,    0..7
;   SourceColumn/SourceRow/SelectedPiece describe the selected source.
;
; Output:
;   Carry clear = legal destination
;   Carry set   = illegal destination
;
; This routine never changes VRAM. It validates ownership, movement geometry,
; sliding paths, normal pawn movement/captures, and king safety. For the king
; safety test, BoardPosition is changed temporarily and restored before return.
; Preserves all registers.
; ------------------------------------------------------------------
ValidateMove:
    push ax
    push bx
    push dx
    push si
    push di

    ; Pattern validators set these bits when the candidate is a special move.
    ; Every candidate starts with a clean classification.
    mov  byte [PendingMoveFlags], 0

    cmp  bl, 7
    jbe  .column_valid
    stc
    jmp  .restore

.column_valid:
    cmp  bh, 7
    jbe  .row_valid
    stc
    jmp  .restore

.row_valid:
    ; Source and destination must differ.
    mov  al, bl
    cmp  al, [SourceColumn]
    jne  .different
    mov  al, bh
    cmp  al, [SourceRow]
    jne  .different
    stc
    jmp  .restore

.different:
    mov  [CandidateColumn], bl
    mov  [CandidateRow], bh

    ; DI = destination row * 8 + destination column.
    xor  ax, ax
    mov  al, bh
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, bl
    add  di, ax

    mov  al, [BoardPosition + di]
    mov  [DestinationPiece], al
    test al, 07h
    jz   .destination_side_ok

    ; An occupied destination must belong to the other side.
    mov  ah, al
    xor  ah, [SelectedPiece]
    test ah, BLACK
    jnz  .destination_side_ok
    stc
    jmp  .restore

.destination_side_ok:
    ; A king is never captured in chess. Check/checkmate handling determines
    ; the result instead, so the opponent king is not a legal destination.
    mov  al, [DestinationPiece]
    and  al, 07h
    cmp  al, KING
    jne  .destination_not_king
    stc
    jmp  .restore

.destination_not_king:
    ; Signed deltas are small enough to keep in bytes (-7..+7).
    mov  al, [CandidateColumn]
    sub  al, [SourceColumn]
    mov  [MoveDeltaX], al
    mov  al, [CandidateRow]
    sub  al, [SourceRow]
    mov  [MoveDeltaY], al

    mov  al, [SelectedPiece]
    and  al, 07h

    cmp  al, PAWN
    jne  .not_pawn
    call ValidatePawnPattern
    jmp  .check_king_if_pattern_valid

.not_pawn:
    cmp  al, KNIGHT
    jne  .not_knight
    call ValidateKnightPattern
    jmp  .check_king_if_pattern_valid

.not_knight:
    cmp  al, BISHOP
    jne  .not_bishop
    call ValidateBishopPattern
    jmp  .check_king_if_pattern_valid

.not_bishop:
    cmp  al, ROOK
    jne  .not_rook
    call ValidateRookPattern
    jmp  .check_king_if_pattern_valid

.not_rook:
    cmp  al, QUEEN
    jne  .not_queen
    call ValidateQueenPattern
    jmp  .check_king_if_pattern_valid

.not_queen:
    cmp  al, KING
    jne  .invalid_piece

    ; Castling has its own explicit dispatch. Do not make the special move
    ; depend on the ordinary king-delta helper: the normal interactive path
    ; must recognize e1/e8 to g1/g8 or c1/c8 directly on an 8088.
    mov  dl, [CandidateRow]
    cmp  dl, [SourceRow]
    jne  .ordinary_king_pattern
    cmp  byte [SourceColumn], 4
    jne  .ordinary_king_pattern
    cmp  byte [CandidateColumn], 6
    je   .explicit_castling_pattern
    cmp  byte [CandidateColumn], 2
    jne  .ordinary_king_pattern

.explicit_castling_pattern:
    call ValidateCastlingPattern
    jmp  .check_king_if_pattern_valid

.ordinary_king_pattern:
    call ValidateKingPattern
    jmp  .check_king_if_pattern_valid

.invalid_piece:
    stc
    jmp  .restore

.check_king_if_pattern_valid:
    ; A failed geometry/path test already set carry. Only a pseudo-legal
    ; candidate needs the temporary make/check/undo king-safety test.
    jnc  .pattern_valid
    jmp  .restore

.pattern_valid:
    call IsMoveKingSafe

.restore:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; IsMoveKingSafe
;
; SourceColumn/SourceRow and CandidateColumn/CandidateRow describe a
; pseudo-legal candidate. Apply it to BoardPosition, locate the moving
; player's king, test that square for enemy attacks, and restore both
; changed board bytes.
;
; Output:
;   Carry clear = the moving player's king is safe
;   Carry set   = the king is attacked, or no king was found
;
; BoardPosition is always restored before return. VRAM is never touched.
; Preserves all registers.
; ------------------------------------------------------------------
IsMoveKingSafe:
    push ax
    push bx
    push dx
    push si
    push di

    ; DI = source row * 8 + source column.
    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [SourceColumn]
    add  di, ax
    mov  [SafetySourceIndex], di
    mov  al, [BoardPosition + di]
    mov  [SafetySourcePiece], al

    ; DI = candidate row * 8 + candidate column.
    xor  ax, ax
    mov  al, [CandidateRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  [SafetyDestinationIndex], di
    mov  al, [BoardPosition + di]
    mov  [SafetyDestinationPiece], al

    ; Temporarily make the candidate move.
    mov  di, [SafetySourceIndex]
    mov  byte [BoardPosition + di], EMPTY
    mov  di, [SafetyDestinationIndex]
    mov  al, [SelectedPiece]
    mov  [BoardPosition + di], al

    ; A special move can change more than the source and destination squares.
    ; Apply those extra changes so discovered attacks are evaluated against the
    ; real resulting position.
    mov  byte [SafetySpecialApplied], 0

    test byte [PendingMoveFlags], MOVE_FLAG_EN_PASSANT
    jz   .not_en_passant

    ; The captured pawn is beside the source pawn, on the destination file.
    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  [SafetySpecialSourceIndex], di
    mov  al, [BoardPosition + di]
    mov  [SafetySpecialSourcePiece], al
    mov  byte [BoardPosition + di], EMPTY
    mov  byte [SafetySpecialApplied], MOVE_FLAG_EN_PASSANT
    jmp  .special_applied

.not_en_passant:
    test byte [PendingMoveFlags], MOVE_FLAG_CASTLE
    jz   .special_applied

    ; Move the rook as part of the final castled position.
    mov  al, [CandidateColumn]
    cmp  al, 6
    jne  .safety_queenside
    mov  bl, 7
    mov  dl, 5
    jmp  .safety_rook_columns_ready

.safety_queenside:
    xor  bl, bl
    mov  dl, 3

.safety_rook_columns_ready:
    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, bl
    add  di, ax
    mov  [SafetySpecialSourceIndex], di
    mov  al, [BoardPosition + di]
    mov  [SafetySpecialSourcePiece], al

    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, dl
    add  di, ax
    mov  [SafetySpecialDestinationIndex], di
    mov  al, [BoardPosition + di]
    mov  [SafetySpecialDestinationPiece], al

    mov  di, [SafetySpecialSourceIndex]
    mov  byte [BoardPosition + di], EMPTY
    mov  di, [SafetySpecialDestinationIndex]
    mov  al, [SafetySpecialSourcePiece]
    mov  [BoardPosition + di], al
    mov  byte [SafetySpecialApplied], MOVE_FLAG_CASTLE

.special_applied:
    ; When the king itself moved, test the candidate coordinates directly.
    ; This avoids depending on a board scan for the most important case.
    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, KING
    jne  .locate_stationary_king
    mov  bl, [CandidateColumn]
    mov  bh, [CandidateRow]
    jmp  .test_king_square

.locate_stationary_king:
    ; For every other piece, locate the king after applying the candidate.
    call FindCurrentKing
    jnc  .king_found
    mov  byte [KingSafetyResult], 1
    jmp  .restore_board

.king_found:
.test_king_square:
    mov  al, [CurrentTurn]
    call IsSquareAttacked
    jnc  .king_safe
    mov  byte [KingSafetyResult], 1
    jmp  .restore_board

.king_safe:
    mov  byte [KingSafetyResult], 0

.restore_board:
    cmp  byte [SafetySpecialApplied], MOVE_FLAG_EN_PASSANT
    jne  .not_restore_en_passant
    mov  di, [SafetySpecialSourceIndex]
    mov  al, [SafetySpecialSourcePiece]
    mov  [BoardPosition + di], al
    jmp  .special_restored

.not_restore_en_passant:
    cmp  byte [SafetySpecialApplied], MOVE_FLAG_CASTLE
    jne  .special_restored
    mov  di, [SafetySpecialSourceIndex]
    mov  al, [SafetySpecialSourcePiece]
    mov  [BoardPosition + di], al
    mov  di, [SafetySpecialDestinationIndex]
    mov  al, [SafetySpecialDestinationPiece]
    mov  [BoardPosition + di], al

.special_restored:
    mov  di, [SafetySourceIndex]
    mov  al, [SafetySourcePiece]
    mov  [BoardPosition + di], al
    mov  di, [SafetyDestinationIndex]
    mov  al, [SafetyDestinationPiece]
    mov  [BoardPosition + di], al

    cmp  byte [KingSafetyResult], 0
    je   .return_safe
    stc
    jmp  .restore

.return_safe:
    clc

.restore:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; FindCurrentKing
;
; Searches BoardPosition for the king whose BLACK bit matches CurrentTurn.
;
; Output:
;   Carry clear: BL=king column, BH=king row
;   Carry set:   king not found
;
; Preserves all registers except BX.
; ------------------------------------------------------------------
FindCurrentKing:
    push ax
    push cx
    push dx
    push si

    xor  si, si
    mov  cx, 64

.scan:
    mov  al, [BoardPosition + si]
    mov  ah, al
    and  al, 07h
    cmp  al, KING
    jne  .next
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jz   .found

.next:
    inc  si
    loop .scan
    stc
    jmp  .restore

.found:
    ; Column = index & 7; row = index >> 3.
    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  bl, dl
    mov  ax, si
    shr  ax, 1
    shr  ax, 1
    shr  ax, 1
    mov  bh, al
    clc

.restore:
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; IsSquareAttacked
;
; Input:
;   BL = target column, 0..7
;   BH = target row,    0..7
;   AL = side occupying the target: 00h White or 80h Black
;
; Output:
;   Carry set   = the opposite side attacks the target
;   Carry clear = the target is not attacked
;
; This target-centered implementation tests pawn, knight, king, diagonal-ray,
; and orthogonal-ray attacks directly around the target square.  It is shared
; by legal-move filtering and the visible CHECK indication.
; Preserves all registers.
; ------------------------------------------------------------------
IsSquareAttacked:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  [AttackTargetColumn], bl
    mov  [AttackTargetRow], bh
    and  al, BLACK
    xor  al, BLACK
    mov  [AttackSide], al

    ; Pawns are asymmetric, so test their two possible origin squares
    ; separately from the symmetric offset and ray pieces.
    call CheckPawnAttackers
    jnc  .no_pawn_attack
    jmp  .attacked
.no_pawn_attack:

    mov  si, KnightAttackOffsets
    mov  cx, 8
    mov  dl, KNIGHT
    call CheckAttackOffsetList
    jnc  .no_knight_attack
    jmp  .attacked
.no_knight_attack:

    mov  si, KingAttackOffsets
    mov  cx, 8
    mov  dl, KING
    call CheckAttackOffsetList
    jnc  .no_king_attack
    jmp  .attacked
.no_king_attack:

    ; Diagonal rays: the first occupied square may attack only when it is
    ; an enemy bishop or queen.
    mov  dl, 0FFh
    mov  dh, 0FFh
    mov  cl, BISHOP
    call ScanAttackRay
    jnc  .no_diag_nw
    jmp  .attacked
.no_diag_nw:
    mov  dl, 1
    mov  dh, 0FFh
    mov  cl, BISHOP
    call ScanAttackRay
    jnc  .no_diag_ne
    jmp  .attacked
.no_diag_ne:
    mov  dl, 0FFh
    mov  dh, 1
    mov  cl, BISHOP
    call ScanAttackRay
    jnc  .no_diag_sw
    jmp  .attacked
.no_diag_sw:
    mov  dl, 1
    mov  dh, 1
    mov  cl, BISHOP
    call ScanAttackRay
    jnc  .no_diag_se
    jmp  .attacked
.no_diag_se:

    ; Orthogonal rays: the first occupied square may attack only when it is
    ; an enemy rook or queen.
    mov  dl, 0FFh
    xor  dh, dh
    mov  cl, ROOK
    call ScanAttackRay
    jnc  .no_ray_west
    jmp  .attacked
.no_ray_west:
    mov  dl, 1
    xor  dh, dh
    mov  cl, ROOK
    call ScanAttackRay
    jnc  .no_ray_east
    jmp  .attacked
.no_ray_east:
    xor  dl, dl
    mov  dh, 0FFh
    mov  cl, ROOK
    call ScanAttackRay
    jnc  .no_ray_north
    jmp  .attacked
.no_ray_north:
    xor  dl, dl
    mov  dh, 1
    mov  cl, ROOK
    call ScanAttackRay
    jnc  .no_ray_south
    jmp  .attacked
.no_ray_south:

    clc
    jmp  .restore

.attacked:
    stc

.restore:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; CheckPawnAttackers
;
; AttackSide is the enemy side.  Test the two squares from which one of
; that side's pawns would attack AttackTargetColumn/AttackTargetRow.
; Output: carry set when an enemy pawn attacks the target.
; Preserves all registers.
; ------------------------------------------------------------------
CheckPawnAttackers:
    push ax
    push bx
    push dx

    mov  bh, [AttackTargetRow]
    test byte [AttackSide], BLACK
    jz   .white_pawn_origin

    ; A Black pawn moves toward increasing rows, so its origin is one row
    ; above the target.
    dec  bh
    jmp  .test_files

.white_pawn_origin:
    ; A White pawn moves toward decreasing rows, so its origin is one row
    ; below the target.
    inc  bh

.test_files:
    mov  bl, [AttackTargetColumn]
    dec  bl
    mov  dl, PAWN
    call IsEnemyPieceTypeAt
    jc   .yes

    ; Starting from target-1, adding two reaches target+1.  Byte wrap is
    ; harmless because GetBoardPieceAt rejects coordinates outside 0..7.
    add  bl, 2
    mov  dl, PAWN
    call IsEnemyPieceTypeAt
    jc   .yes

    clc
    jmp  .restore

.yes:
    stc

.restore:
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; CheckAttackOffsetList
;
; Input:
;   DS:SI = list of signed column,row offsets
;   CX    = number of offset pairs
;   DL    = required attacking piece type
;
; Output: carry set when an enemy piece of that type occupies any offset.
; Preserves all registers.
; ------------------------------------------------------------------
CheckAttackOffsetList:
    push ax
    push bx
    push cx
    push dx
    push si

.next_offset:
    mov  bl, [AttackTargetColumn]
    add  bl, [si]
    inc  si
    mov  bh, [AttackTargetRow]
    add  bh, [si]
    inc  si
    call IsEnemyPieceTypeAt
    jc   .yes
    loop .next_offset

    clc
    jmp  .restore

.yes:
    stc

.restore:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; IsEnemyPieceTypeAt
;
; Input: BL=column, BH=row, DL=required piece type.
; Output: carry set only when that square contains the required type and its
;         BLACK bit matches AttackSide.
; Preserves all registers.
; ------------------------------------------------------------------
IsEnemyPieceTypeAt:
    push ax
    push dx

    call GetBoardPieceAt
    jc   .no

    mov  ah, al
    and  al, 07h
    cmp  al, dl
    jne  .no
    xor  ah, [AttackSide]
    test ah, BLACK
    jnz  .no

    stc
    jmp  .restore

.no:
    clc

.restore:
    pop  dx
    pop  ax
    ret


; ------------------------------------------------------------------
; ScanAttackRay
;
; Input:
;   DL = signed column step (-1,0,+1)
;   DH = signed row step    (-1,0,+1)
;   CL = required sliding type (BISHOP or ROOK); QUEEN also matches.
;
; Scan outward from the target.  The first occupied square blocks the ray.
; It attacks only when it is an enemy CL piece or enemy queen.
; Output: carry set when the target is attacked along this ray.
; Preserves all registers.
; ------------------------------------------------------------------
ScanAttackRay:
    push ax
    push bx
    push cx
    push dx

    mov  bl, [AttackTargetColumn]
    mov  bh, [AttackTargetRow]

.next_square:
    add  bl, dl
    add  bh, dh
    call GetBoardPieceAt
    jc   .no
    test al, 07h
    jz   .next_square

    ; The first occupied square blocks the ray even when it is friendly or
    ; an enemy piece of the wrong type.
    mov  ah, al
    xor  ah, [AttackSide]
    test ah, BLACK
    jnz  .no

    and  al, 07h
    cmp  al, cl
    je   .yes
    cmp  al, QUEEN
    je   .yes

.no:
    clc
    jmp  .restore

.yes:
    stc

.restore:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Signed (column,row) origins around a target square.
KnightAttackOffsets:
    db -2,-1, -2,1, -1,-2, -1,2
    db  1,-2,  1,2,  2,-1,  2,1

KingAttackOffsets:
    db -1,-1, 0,-1, 1,-1, -1,0
    db  1, 0, -1,1,  0, 1,  1,1


; ------------------------------------------------------------------
; DoesScannedPieceAttackTarget
;
; AttackCandidatePiece at AttackOriginColumn/Row is known to belong to
; AttackSide. Test whether it attacks AttackTargetColumn/Row.
;
; Output: carry set = attacks target, carry clear = does not attack.
; Preserves all registers.
; ------------------------------------------------------------------
DoesScannedPieceAttackTarget:
    push ax
    push bx

    mov  al, [AttackTargetColumn]
    sub  al, [AttackOriginColumn]
    mov  [AttackDeltaX], al
    mov  al, [AttackTargetRow]
    sub  al, [AttackOriginRow]
    mov  [AttackDeltaY], al

    mov  al, [AttackCandidatePiece]
    and  al, 07h

    cmp  al, PAWN
    jne  .not_pawn
    call DoesPawnAttackTarget
    jmp  .restore

.not_pawn:
    cmp  al, KNIGHT
    jne  .not_knight
    call DoesKnightAttackTarget
    jmp  .restore

.not_knight:
    cmp  al, BISHOP
    jne  .not_bishop
    call DoesBishopAttackTarget
    jmp  .restore

.not_bishop:
    cmp  al, ROOK
    jne  .not_rook
    call DoesRookAttackTarget
    jmp  .restore

.not_rook:
    cmp  al, QUEEN
    jne  .not_queen
    call DoesQueenAttackTarget
    jmp  .restore

.not_queen:
    cmp  al, KING
    jne  .not_an_attacker
    call DoesKingAttackTarget
    jmp  .restore

.not_an_attacker:
    clc

.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; Piece-specific attack geometry.
; ------------------------------------------------------------------
DoesPawnAttackTarget:
    mov  al, [AttackDeltaX]
    cmp  al, 1
    je   .file_ok
    cmp  al, 0FFh
    jne  .no

.file_ok:
    test byte [AttackSide], BLACK
    jz   .white
    cmp  byte [AttackDeltaY], 1
    je   .yes
    jmp  .no

.white:
    cmp  byte [AttackDeltaY], 0FFh
    je   .yes
    jmp  .no

.yes:
    stc
    ret
.no:
    clc
    ret


DoesKnightAttackTarget:
    call GetAbsoluteAttackDeltas
    cmp  al, 1
    jne  .try_other_order
    cmp  ah, 2
    je   .yes

.try_other_order:
    cmp  al, 2
    jne  .no
    cmp  ah, 1
    jne  .no

.yes:
    stc
    ret
.no:
    clc
    ret


DoesKingAttackTarget:
    call GetAbsoluteAttackDeltas
    cmp  al, 1
    ja   .no
    cmp  ah, 1
    ja   .no
    or   al, ah
    jz   .no
    stc
    ret
.no:
    clc
    ret


DoesBishopAttackTarget:
    call GetAbsoluteAttackDeltas
    cmp  al, ah
    jne  .no
    or   al, al
    jz   .no
    call SetAttackSteps
    call AttackPathIsClear
    ret
.no:
    clc
    ret


DoesRookAttackTarget:
    mov  al, [AttackDeltaX]
    or   al, al
    jz   .vertical
    mov  al, [AttackDeltaY]
    or   al, al
    jnz  .no
    jmp  .geometry_ok

.vertical:
    mov  al, [AttackDeltaY]
    or   al, al
    jz   .no

.geometry_ok:
    call SetAttackSteps
    call AttackPathIsClear
    ret
.no:
    clc
    ret


DoesQueenAttackTarget:
    call GetAbsoluteAttackDeltas
    cmp  al, ah
    jne  .try_orthogonal
    or   al, al
    jnz  .geometry_ok
    jmp  .no

.try_orthogonal:
    mov  al, [AttackDeltaX]
    or   al, al
    jz   .vertical
    mov  al, [AttackDeltaY]
    or   al, al
    jnz  .no
    jmp  .geometry_ok

.vertical:
    mov  al, [AttackDeltaY]
    or   al, al
    jz   .no

.geometry_ok:
    call SetAttackSteps
    call AttackPathIsClear
    ret
.no:
    clc
    ret


GetAbsoluteAttackDeltas:
    mov  al, [AttackDeltaX]
    test al, 80h
    jz   .x_ready
    neg  al
.x_ready:
    mov  ah, [AttackDeltaY]
    test ah, 80h
    jz   .done
    neg  ah
.done:
    ret


SetAttackSteps:
    mov  al, [AttackDeltaX]
    call SignOfAL
    mov  [AttackStepX], al
    mov  al, [AttackDeltaY]
    call SignOfAL
    mov  [AttackStepY], al
    ret


; Follow the line from the attacking piece to the target. The target itself is
; not tested for occupancy; every intervening square must be empty.
AttackPathIsClear:
    push ax
    push bx

    mov  al, [AttackOriginColumn]
    mov  [AttackPathColumn], al
    mov  al, [AttackOriginRow]
    mov  [AttackPathRow], al

.next_square:
    mov  al, [AttackStepX]
    add  [AttackPathColumn], al
    mov  al, [AttackStepY]
    add  [AttackPathRow], al

    mov  al, [AttackPathColumn]
    cmp  al, [AttackTargetColumn]
    jne  .test_intermediate
    mov  al, [AttackPathRow]
    cmp  al, [AttackTargetRow]
    je   .clear

.test_intermediate:
    mov  bl, [AttackPathColumn]
    mov  bh, [AttackPathRow]
    call IsBoardSquareEmpty
    jc   .blocked
    jmp  .next_square

.clear:
    clc
    jmp  .restore
.blocked:
    stc
.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; GetBoardPieceAt
;
; Input:  BL=column, BH=row
; Output: AL=piece code and carry clear, or AL=EMPTY and carry set when
;         the coordinates are outside the board.
; Preserves all registers except AX.
; ------------------------------------------------------------------
GetBoardPieceAt:
    push di

    cmp  bl, 7
    ja   .outside
    cmp  bh, 7
    ja   .outside

    xor  ax, ax
    mov  al, bh
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, bl
    add  di, ax
    mov  al, [BoardPosition + di]
    clc
    jmp  .restore

.outside:
    mov  al, EMPTY
    stc

.restore:
    pop  di
    ret


; ------------------------------------------------------------------
; ValidatePawnPattern
;
; White starts at row 6 and moves toward decreasing rows.
; Black starts at row 1 and moves toward increasing rows.
; Carry result; preserves all registers.
; ------------------------------------------------------------------
ValidatePawnPattern:
    push ax
    push bx
    push di

    test byte [SelectedPiece], BLACK
    jz   .white
    jmp  .black

.white:
    ; White: one step is DY=-1 (FFh), first double step is DY=-2 (FEh).
    cmp  byte [MoveDeltaX], 0
    jne  .white_capture
    test byte [DestinationPiece], 07h
    jnz  .white_illegal
    cmp  byte [MoveDeltaY], 0FFh
    je   .white_legal
    cmp  byte [MoveDeltaY], 0FEh
    jne  .white_illegal
    cmp  byte [SourceRow], 6
    jne  .white_illegal

    ; White's intermediate square is SourceRow-1.
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    dec  bh
    call IsBoardSquareEmpty
    jc   .white_illegal
    or   byte [PendingMoveFlags], MOVE_FLAG_PAWN_DOUBLE
    jmp  .white_legal

.white_capture:
    cmp  byte [MoveDeltaY], 0FFh
    jne  .white_illegal
    mov  al, [MoveDeltaX]
    cmp  al, 1
    je   .white_capture_delta_ok
    cmp  al, 0FFh
    jne  .white_illegal
.white_capture_delta_ok:
    test byte [DestinationPiece], 07h
    jnz  .white_legal
    call ValidateEnPassantCapture
    jc   .white_illegal
    jmp  .white_legal

.white_legal:
    clc
    jmp  .restore

.white_illegal:
    stc
    jmp  .restore

.black:
    ; Black: one step is DY=+1, first double step is DY=+2.
    cmp  byte [MoveDeltaX], 0
    jne  .black_capture
    test byte [DestinationPiece], 07h
    jnz  .illegal
    cmp  byte [MoveDeltaY], 1
    je   .legal
    cmp  byte [MoveDeltaY], 2
    jne  .illegal
    cmp  byte [SourceRow], 1
    jne  .illegal

    ; Black's intermediate square is SourceRow+1.
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    inc  bh
    call IsBoardSquareEmpty
    jc   .illegal
    or   byte [PendingMoveFlags], MOVE_FLAG_PAWN_DOUBLE
    jmp  .legal

.black_capture:
    cmp  byte [MoveDeltaY], 1
    jne  .illegal
    mov  al, [MoveDeltaX]
    cmp  al, 1
    je   .black_capture_delta_ok
    cmp  al, 0FFh
    jne  .illegal
.black_capture_delta_ok:
    test byte [DestinationPiece], 07h
    jnz  .legal
    call ValidateEnPassantCapture
    jc   .illegal
    jmp  .legal

.legal:
    clc
    jmp  .restore

.illegal:
    stc

.restore:
    pop  di
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ValidateEnPassantCapture
;
; The pawn geometry has already established a one-step diagonal move into an
; empty square. The destination must be the one target made available by the
; immediately preceding double-step, and the adjacent piece must still be an
; opposing pawn.
;
; Carry clear = legal en passant capture; carry set = illegal.
; Preserves all registers.
; ------------------------------------------------------------------
ValidateEnPassantCapture:
    push ax
    push bx
    push di

    cmp  byte [EnPassantSquare], NO_EN_PASSANT
    je   .illegal

    xor  ax, ax
    mov  al, [CandidateRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CandidateColumn]
    add  di, ax
    mov  ax, di
    cmp  al, [EnPassantSquare]
    jne  .illegal

    mov  bl, [CandidateColumn]
    mov  bh, [SourceRow]
    call GetBoardPieceAt
    jc   .illegal
    mov  ah, al
    and  al, 07h
    cmp  al, PAWN
    jne  .illegal
    xor  ah, [SelectedPiece]
    test ah, BLACK
    jz   .illegal

    or   byte [PendingMoveFlags], MOVE_FLAG_EN_PASSANT
    clc
    jmp  .restore

.illegal:
    stc

.restore:
    pop  di
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ValidateKnightPattern / ValidateKingPattern
; Carry result; preserve all registers.
; ------------------------------------------------------------------
ValidateKnightPattern:
    push ax
    push bx

    call GetAbsoluteDeltas
    cmp  al, 1
    jne  .try_other_order
    cmp  ah, 2
    je   .legal

.try_other_order:
    cmp  al, 2
    jne  .illegal
    cmp  ah, 1
    jne  .illegal

.legal:
    clc
    jmp  .restore
.illegal:
    stc
.restore:
    pop  bx
    pop  ax
    ret


ValidateKingPattern:
    push ax
    push bx

    call GetAbsoluteDeltas
    cmp  al, 2
    jne  .ordinary_king_move
    cmp  ah, 0
    jne  .illegal
    call ValidateCastlingPattern
    jmp  .restore

.ordinary_king_move:
    cmp  al, 1
    ja   .illegal
    cmp  ah, 1
    ja   .illegal
    or   al, ah
    jz   .illegal
    clc
    jmp  .restore

.illegal:
    stc
.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ValidateCastlingPattern
;
; The caller has established a two-file horizontal king move. This routine
; checks the retained right, original king/rook squares, empty path, and that
; neither the starting square nor the transit square is attacked. The final
; destination is checked by IsMoveKingSafe with the rook also moved.
;
; Carry clear = legal castling pattern; carry set = illegal.
; Preserves all registers.
; ------------------------------------------------------------------
ValidateCastlingPattern:
    push ax
    push bx
    push dx

    cmp  byte [SourceColumn], 4
    jne  .illegal

    test byte [SelectedPiece], BLACK
    jnz  .black

    cmp  byte [SourceRow], 7
    jne  .illegal
    cmp  byte [CandidateRow], 7
    jne  .illegal
    cmp  byte [CandidateColumn], 6
    je   .white_kingside
    cmp  byte [CandidateColumn], 2
    jne  .illegal
    mov  al, [CastlingRights]
    test al, CASTLE_WHITE_QUEENSIDE
    jz   .illegal
    jmp  .queenside

.white_kingside:
    mov  al, [CastlingRights]
    test al, CASTLE_WHITE_KINGSIDE
    jz   .illegal
    jmp  .kingside

.black:
    cmp  byte [SourceRow], 0
    jne  .illegal
    cmp  byte [CandidateRow], 0
    jne  .illegal
    cmp  byte [CandidateColumn], 6
    je   .black_kingside
    cmp  byte [CandidateColumn], 2
    jne  .illegal
    mov  al, [CastlingRights]
    test al, CASTLE_BLACK_QUEENSIDE
    jz   .illegal
    jmp  .queenside

.black_kingside:
    mov  al, [CastlingRights]
    test al, CASTLE_BLACK_KINGSIDE
    jz   .illegal

.kingside:
    mov  byte [CastleRookSourceColumn], 7
    mov  byte [CastleRookDestinationColumn], 5
    mov  byte [CastleTransitColumn], 5

    mov  bl, 5
    mov  bh, [SourceRow]
    call IsBoardSquareEmpty
    jc   .illegal
    mov  bl, 6
    mov  bh, [SourceRow]
    call IsBoardSquareEmpty
    jc   .illegal
    jmp  .check_rook

.queenside:
    mov  byte [CastleRookSourceColumn], 0
    mov  byte [CastleRookDestinationColumn], 3
    mov  byte [CastleTransitColumn], 3

    mov  bl, 1
    mov  bh, [SourceRow]
    call IsBoardSquareEmpty
    jc   .illegal
    mov  bl, 2
    mov  bh, [SourceRow]
    call IsBoardSquareEmpty
    jc   .illegal
    mov  bl, 3
    mov  bh, [SourceRow]
    call IsBoardSquareEmpty
    jc   .illegal

.check_rook:
    mov  bl, [CastleRookSourceColumn]
    mov  bh, [SourceRow]
    call GetBoardPieceAt
    jc   .illegal
    mov  ah, [SelectedPiece]
    and  ah, BLACK
    or   ah, ROOK
    cmp  al, ah
    jne  .illegal

    ; The king may not castle out of check.
    mov  bl, [SourceColumn]
    mov  bh, [SourceRow]
    mov  al, [SelectedPiece]
    and  al, BLACK
    call IsSquareAttacked
    jc   .illegal

    ; Nor may it cross an attacked square.
    call IsCastlingTransitSafe
    jc   .illegal

    or   byte [PendingMoveFlags], MOVE_FLAG_CASTLE
    clc
    jmp  .restore

.illegal:
    stc

.restore:
    pop  dx
    pop  bx
    pop  ax
    ret


; Temporarily place the king on the castling transit square and test attacks.
IsCastlingTransitSafe:
    push ax
    push bx
    push dx
    push si
    push di

    xor  ax, ax
    mov  al, [SourceRow]
    mov  si, ax
    shl  si, 1
    shl  si, 1
    shl  si, 1
    xor  ax, ax
    mov  al, [SourceColumn]
    add  si, ax

    xor  ax, ax
    mov  al, [SourceRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CastleTransitColumn]
    add  di, ax

    mov  dl, [BoardPosition + di]
    mov  byte [BoardPosition + si], EMPTY
    mov  al, [SelectedPiece]
    mov  [BoardPosition + di], al

    mov  bl, [CastleTransitColumn]
    mov  bh, [SourceRow]
    mov  al, [SelectedPiece]
    and  al, BLACK
    call IsSquareAttacked
    jnc  .safe
    mov  byte [CastleTransitAttacked], 1
    jmp  .restore_board

.safe:
    mov  byte [CastleTransitAttacked], 0

.restore_board:
    mov  al, [SelectedPiece]
    mov  [BoardPosition + si], al
    mov  [BoardPosition + di], dl

    cmp  byte [CastleTransitAttacked], 0
    je   .return_safe
    stc
    jmp  .restore

.return_safe:
    clc

.restore:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ValidateBishopPattern / ValidateRookPattern / ValidateQueenPattern
; Sliding-piece geometry plus an unobstructed path.
; Carry result; preserve all registers.
; ------------------------------------------------------------------
ValidateBishopPattern:
    push ax
    push bx

    call GetAbsoluteDeltas
    cmp  al, ah
    jne  .illegal
    or   al, al
    jz   .illegal
    call SetDiagonalSteps
    call PathIsClear
    jmp  .restore

.illegal:
    stc
.restore:
    pop  bx
    pop  ax
    ret


ValidateRookPattern:
    push ax

    mov  al, [MoveDeltaX]
    or   al, al
    jz   .vertical
    mov  al, [MoveDeltaY]
    or   al, al
    jnz  .illegal
    call SetOrthogonalSteps
    call PathIsClear
    jmp  .restore

.vertical:
    mov  al, [MoveDeltaY]
    or   al, al
    jz   .illegal
    call SetOrthogonalSteps
    call PathIsClear
    jmp  .restore

.illegal:
    stc
.restore:
    pop  ax
    ret


ValidateQueenPattern:
    push ax
    push bx

    ; First test diagonal geometry.
    call GetAbsoluteDeltas
    cmp  al, ah
    jne  .try_orthogonal
    or   al, al
    jz   .illegal
    call SetDiagonalSteps
    call PathIsClear
    jmp  .restore

.try_orthogonal:
    mov  al, [MoveDeltaX]
    or   al, al
    jz   .orthogonal
    mov  al, [MoveDeltaY]
    or   al, al
    jnz  .illegal

.orthogonal:
    call SetOrthogonalSteps
    call PathIsClear
    jmp  .restore

.illegal:
    stc
.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; GetAbsoluteDeltas
;
; Output: AL=abs(MoveDeltaX), AH=abs(MoveDeltaY)
; Preserves all other registers.
; ------------------------------------------------------------------
GetAbsoluteDeltas:
    mov  al, [MoveDeltaX]
    test al, 80h
    jz   .x_ready
    neg  al
.x_ready:
    mov  ah, [MoveDeltaY]
    test ah, 80h
    jz   .done
    neg  ah
.done:
    ret


; ------------------------------------------------------------------
; SetDiagonalSteps / SetOrthogonalSteps
;
; Convert signed deltas to signed unit steps (-1,0,+1).
; ------------------------------------------------------------------
SetDiagonalSteps:
    mov  al, [MoveDeltaX]
    call SignOfAL
    mov  [MoveStepX], al
    mov  al, [MoveDeltaY]
    call SignOfAL
    mov  [MoveStepY], al
    ret


SetOrthogonalSteps:
    mov  al, [MoveDeltaX]
    call SignOfAL
    mov  [MoveStepX], al
    mov  al, [MoveDeltaY]
    call SignOfAL
    mov  [MoveStepY], al
    ret


SignOfAL:
    or   al, al
    jz   .done
    test al, 80h
    jnz  .negative
    mov  al, 1
    ret
.negative:
    mov  al, 0FFh
.done:
    ret


; ------------------------------------------------------------------
; PathIsClear
;
; Starting immediately after the source, follow MoveStepX/MoveStepY.
; The destination itself is not tested here; intervening squares must be empty.
; Carry clear = clear path, carry set = blocked.
; Preserves all registers.
; ------------------------------------------------------------------
PathIsClear:
    push ax
    push bx
    push di

    mov  al, [SourceColumn]
    mov  [PathColumn], al
    mov  al, [SourceRow]
    mov  [PathRow], al

.next_square:
    mov  al, [MoveStepX]
    add  [PathColumn], al
    mov  al, [MoveStepY]
    add  [PathRow], al

    mov  al, [PathColumn]
    cmp  al, [CandidateColumn]
    jne  .test_intermediate
    mov  al, [PathRow]
    cmp  al, [CandidateRow]
    je   .clear

.test_intermediate:
    mov  bl, [PathColumn]
    mov  bh, [PathRow]
    call IsBoardSquareEmpty
    jc   .blocked
    jmp  .next_square

.clear:
    clc
    jmp  .restore
.blocked:
    stc
.restore:
    pop  di
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; IsBoardSquareEmpty
;
; Input: BL=column, BH=row
; Output: carry clear if empty, carry set if occupied/out of range.
; Preserves all registers.
; ------------------------------------------------------------------
IsBoardSquareEmpty:
    push ax
    push di

    cmp  bl, 7
    ja   .occupied
    cmp  bh, 7
    ja   .occupied

    xor  ax, ax
    mov  al, bh
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, bl
    add  di, ax
    test byte [BoardPosition + di], 07h
    jnz  .occupied
    clc
    jmp  .restore

.occupied:
    stc
.restore:
    pop  di
    pop  ax
    ret


; ------------------------------------------------------------------
; ClearMoveMask / GenerateMoveMask / IsCursorMoveMarked
;
; MoveMask contains one byte per board row. Bit N represents column N.
; GenerateMoveMask calls ValidateMove for every destination square.
; ------------------------------------------------------------------
ClearMoveMask:
    push cx
    push di

    mov  di, MoveMask
    mov  cx, 8
.clear_byte:
    mov  byte [di], 0
    inc  di
    loop .clear_byte

    pop  di
    pop  cx
    ret


GenerateMoveMask:
    push ax
    push bx
    push cx
    push dx
    push di

    call ClearMoveMask
    xor  bx, bx              ; BH=row, BL=column

.candidate:
    call ValidateMove
    jc   .next_candidate

    mov  al, 1
    mov  cl, bl
    shl  al, cl
    xor  dx, dx
    mov  dl, bh
    mov  di, dx
    or   [MoveMask + di], al

.next_candidate:
    inc  bl
    cmp  bl, 8
    jb   .candidate
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .candidate

    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


IsCursorMoveMarked:
    push ax
    push cx
    push di

    xor  ax, ax
    mov  al, [CursorRow]
    mov  di, ax
    mov  al, 1
    mov  cl, [CursorColumn]
    shl  al, cl
    test [MoveMask + di], al
    jz   .not_marked
    clc
    jmp  .restore

.not_marked:
    stc
.restore:
    pop  di
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; GetCursorBoardIndex
;
; Output:
;   DI = CursorRow * 8 + CursorColumn
;
; Preserves all other registers.
; ------------------------------------------------------------------
GetCursorBoardIndex:
    push ax

    xor  ax, ax
    mov  al, [CursorRow]
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, [CursorColumn]
    add  di, ax

    pop  ax
    ret


; ------------------------------------------------------------------
; AdvanceTurn
;
; Erases the current label, toggles the side-to-move bit, and draws
; the new label. It then classifies the new position as normal play,
; CHECK, CHECKMATE, or STALEMATE.
; Called only after a successful completed move.
; Preserves all registers.
; ------------------------------------------------------------------
AdvanceTurn:
    call DrawTurnIndicatorXor
    call DrawClockActiveIndicatorXor
    xor  byte [CurrentTurn], BLACK
    call DrawClockActiveIndicatorXor
    call DrawTurnIndicatorXor
    call EvaluateGameState
    cmp  byte [PositionInCheck], 0
    je   .done
    call PlayCheckSound
.done:
    ret


; ------------------------------------------------------------------
; HasAnyLegalMove
;
; Searches every piece belonging to CurrentTurn and every destination square.
; The existing ValidateMove routine supplies the complete movement, occupancy,
; path, and king-safety rules. No markers are generated and VRAM is unchanged.
;
; Output:
;   Carry clear = CurrentTurn has at least one legal move
;   Carry set   = CurrentTurn has no legal move
;
; Preserves all registers and restores the interactive selection variables.
; ------------------------------------------------------------------
HasAnyLegalMove:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  al, [SourceColumn]
    mov  [SavedSourceColumn], al
    mov  al, [SourceRow]
    mov  [SavedSourceRow], al
    mov  al, [SelectedPiece]
    mov  [SavedSelectedPiece], al

    mov  byte [AnyLegalMoveResult], 0
    xor  si, si

.next_source:
    mov  al, [BoardPosition + si]
    test al, 07h
    jz   .advance_source

    ; The candidate source must belong to CurrentTurn.
    mov  ah, al
    xor  ah, [CurrentTurn]
    test ah, BLACK
    jnz  .advance_source

    mov  [SelectedPiece], al

    mov  ax, si
    mov  dl, al
    and  dl, 07h
    mov  [SourceColumn], dl
    mov  ax, si
    shr  ax, 1
    shr  ax, 1
    shr  ax, 1
    mov  [SourceRow], al

    xor  bx, bx              ; BH=row, BL=column.

.next_destination:
    call ValidateMove
    jc   .destination_illegal
    mov  byte [AnyLegalMoveResult], 1
    jmp  .restore_selection

.destination_illegal:
    inc  bl
    cmp  bl, 8
    jb   .next_destination
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_destination

.advance_source:
    inc  si
    cmp  si, 64
    jb   .next_source

.restore_selection:
    mov  al, [SavedSourceColumn]
    mov  [SourceColumn], al
    mov  al, [SavedSourceRow]
    mov  [SourceRow], al
    mov  al, [SavedSelectedPiece]
    mov  [SelectedPiece], al

    cmp  byte [AnyLegalMoveResult], 0
    jne  .move_found
    stc
    jmp  .restore

.move_found:
    clc

.restore:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; EvaluateGameState
;
; Evaluates the side to move after startup and after every completed move:
;
;   safe + legal reply   -> continue
;   check + legal reply  -> CHECK
;   check + no reply     -> CHECKMATE
;   safe + no reply      -> STALEMATE
;
; Any old reversible CHECK label is erased before a terminal label is drawn.
; Preserves all registers.
; ------------------------------------------------------------------
EvaluateGameState:
    push ax

    ; A clock loss is terminal and must never be converted back into a normal
    ; board state by a defensive re-evaluation.
    cmp  byte [GameState], GAME_TIME_FORFEIT
    je   .done

    mov  byte [GameState], GAME_PLAYING

    ; Remove the previous side's CHECK label before classifying the new side.
    cmp  byte [CheckIndicatorVisible], 0
    je   .old_check_removed
    call DrawCheckIndicatorXor
    mov  byte [CheckIndicatorVisible], 0

.old_check_removed:
    mov  byte [PositionInCheck], 0
    call IsCurrentKingInCheck
    jnc  .check_state_saved
    mov  byte [PositionInCheck], 1

.check_state_saved:
    call HasAnyLegalMove
    jc   .no_legal_move

    ; The game continues. Announce CHECK only when the side has a legal reply.
    cmp  byte [PositionInCheck], 0
    je   .done
    call DrawCheckIndicatorXor
    mov  byte [CheckIndicatorVisible], 1
    jmp  .done

.no_legal_move:
    cmp  byte [PositionInCheck], 0
    je   .stalemate

    mov  byte [GameState], GAME_CHECKMATE
    call DrawCheckmateIndicatorXor
    jmp  .done

.stalemate:
    mov  byte [GameState], GAME_STALEMATE
    call DrawStalemateIndicatorXor

.done:
    pop  ax
    ret


; ------------------------------------------------------------------
; IsCurrentKingInCheck
;
; Uses the same attack detector as king-safety move filtering.
;
; Output:
;   Carry set   = CurrentTurn's king is attacked, or no king was found
;   Carry clear = CurrentTurn's king is safe
;
; Preserves all registers.
; ------------------------------------------------------------------
IsCurrentKingInCheck:
    push ax
    push bx

    call FindCurrentKing
    jnc  .king_found
    stc
    jmp  .restore

.king_found:
    mov  al, [CurrentTurn]
    call IsSquareAttacked

.restore:
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; UpdateCheckIndicator
;
; Synchronizes the reversible CHECK bitmap with the actual check state
; of the side whose turn it is. CheckIndicatorVisible records whether
; the XOR bitmap is currently present in VRAM.
;
; Preserves all registers.
; ------------------------------------------------------------------
UpdateCheckIndicator:
    push ax

    call IsCurrentKingInCheck
    jc   .check_required

    cmp  byte [CheckIndicatorVisible], 0
    je   .done
    call DrawCheckIndicatorXor
    mov  byte [CheckIndicatorVisible], 0
    jmp  .done

.check_required:
    cmp  byte [CheckIndicatorVisible], 0
    jne  .done
    call DrawCheckIndicatorXor
    mov  byte [CheckIndicatorVisible], 1

.done:
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawCheckIndicatorXor
;
; Draws or erases the native 32x8 CHECK bitmap below the turn label.
; Calling it twice restores the previous display.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawCheckIndicatorXor:
    push ax
    push cx
    push si
    push di
    push bp
    push es

    mov  si, CheckBitmap
    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  di, CHECK_INDICATOR_OFFSET
    mov  bp, CHECK_INDICATOR_WIDTH_BYTES

.next_bitmap_column:
    mov  cx, CHECK_INDICATOR_HEIGHT

.next_bitmap_byte:
    lodsb
    xor  byte [es:di], al
    inc  di
    loop .next_bitmap_byte

    add  di, 0200h - CHECK_INDICATOR_HEIGHT
    dec  bp
    jnz  .next_bitmap_column

    pop  es
    pop  bp
    pop  di
    pop  si
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawCheckmateIndicatorXor / DrawStalemateIndicatorXor
;
; Draw a 56x8 terminal-state label beneath the turn indicator.
; The completed game is frozen, so each label is drawn only once.
; Preserves all registers.
; ------------------------------------------------------------------
DrawCheckmateIndicatorXor:
    push si
    mov  si, CheckmateBitmap
    call DrawTerminalIndicatorXor
    pop  si
    ret


DrawStalemateIndicatorXor:
    push si
    mov  si, StalemateBitmap
    call DrawTerminalIndicatorXor
    pop  si
    ret


DrawTerminalIndicatorXor:
    push ax
    push cx
    push si
    push di
    push bp
    push es

    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  di, TERMINAL_INDICATOR_OFFSET
    mov  bp, TERMINAL_INDICATOR_WIDTH_BYTES

.next_bitmap_column:
    mov  cx, TERMINAL_INDICATOR_HEIGHT

.next_bitmap_byte:
    lodsb
    xor  byte [es:di], al
    inc  di
    loop .next_bitmap_byte

    add  di, 0200h - TERMINAL_INDICATOR_HEIGHT
    dec  bp
    jnz  .next_bitmap_column

    pop  es
    pop  bp
    pop  di
    pop  si
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawTurnIndicatorXor
;
; Draws or erases WHITE TURN / BLACK TURN through the normal small-font
; renderer in the upper-bank left margin beside the board. This deliberately
; selects 8000h here rather than inheriting the panel segment.
; CurrentTurn selects the text.
; Calling the routine twice without changing CurrentTurn restores the
; previous display.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawTurnIndicatorXor:
    push ax
    push cx
    push dx
    push si

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], 8000h

    test byte [CurrentTurn], BLACK
    jnz  .black_turn
    mov  si, WhiteTurnText
    jmp  .draw

.black_turn:
    mov  si, BlackTurnText

.draw:
    mov  cx, TURN_INDICATOR_X
    mov  dx, TURN_INDICATOR_Y
    call DrawSmallStringXor

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; RecordCompletedMove
;
; Appends the completed move to a 256-entry circular history. The record
; layout is intentionally ready for later special-move support:
;
;   byte 0 = source square index,      0..63
;   byte 1 = destination square index, 0..63
;   byte 2 = moving piece code
;   byte 3 = captured piece code
;   byte 4 = flags (capture, double-step, castle, en passant, promotion)
;   byte 5 = previous castling rights
;   byte 6 = previous en-passant square, FFh when none
;   byte 7 = promoted piece code, EMPTY when not a promotion
;
; HistoryNext always identifies the next record to write. HistoryCount grows
; to 256 and then remains saturated while HistoryNext continues to wrap.
; Preserves all registers.
; ------------------------------------------------------------------
RecordCompletedMove:
    push ax
    push bx
    push dx
    push di

    xor  bx, bx
    mov  bl, [HistoryNext]
    mov  di, bx
    shl  di, 1
    shl  di, 1
    shl  di, 1
    lea  di, [MoveHistory + di]

    ; Convert source row/column to row * 8 + column.
    xor  ax, ax
    mov  al, [SourceRow]
    shl  ax, 1
    shl  ax, 1
    shl  ax, 1
    add  al, [SourceColumn]
    mov  [di + 0], al

    mov  ax, [DestinationIndex]
    mov  [di + 1], al
    mov  al, [SelectedPiece]
    mov  [di + 2], al
    mov  al, [CapturedPiece]
    mov  [di + 3], al

    mov  dl, [CommittedMoveFlags]
    test al, 07h
    jz   .capture_flag_done
    or   dl, MOVE_FLAG_CAPTURE

.capture_flag_done:
    mov  [di + 4], dl
    mov  al, [PreviousCastlingRights]
    mov  [di + 5], al
    mov  al, [PreviousEnPassantSquare]
    mov  [di + 6], al
    mov  al, [PromotionPiece]
    mov  [di + 7], al

    inc  byte [HistoryNext]
    cmp  word [HistoryCount], MOVE_HISTORY_CAPACITY
    jae  .count_saturated
    inc  word [HistoryCount]

.count_saturated:
    pop  di
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawBoardCoordinates
;
; Labels files A-H above and below the board and ranks 8-1 on both sides.
; The characters are painted once during startup and never overlap any
; reversible cursor, move marker, piece, or status bitmap.
; Preserves all registers.
; ------------------------------------------------------------------
DrawBoardCoordinates:
    push ax
    push bx
    push cx
    push dx

    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    xor  bx, bx
    mov  cx, BOARD_LEFT + 22

.next_file:
    mov  al, 41h
    add  al, bl
    xor  dx, dx
    call DrawSmallCharacterPaint

    ; The lower file labels live just below the board in the lower 200-line
    ; bank. Small text coordinates are local to the segment it selects.
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG
    mov  dx, BOARD_BOTTOM + 6 - 200
    call DrawSmallCharacterPaint
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG

    add  cx, CELL_WIDTH
    inc  bl
    cmp  bl, BOARD_CELLS
    jb   .next_file

    xor  bx, bx
    mov  dx, BOARD_TOP + 14

.next_rank:
    mov  al, 38h
    sub  al, bl
    cmp  dx, 200
    jb   .rank_bank_ready
    sub  dx, 200
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

.rank_bank_ready:
    mov  cx, BOARD_LEFT - 11
    call DrawSmallCharacterPaint
    mov  cx, BOARD_RIGHT + 8
    call DrawSmallCharacterPaint

    ; Convert the local lower-bank coordinate back to global Y before
    ; advancing to the next board row.
    cmp  word [SmallDrawSegment], PANEL_VRAM_SEG
    jne  .rank_global_ready
    add  dx, 200

.rank_global_ready:
    add  dx, CELL_HEIGHT
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    inc  bl
    cmp  bl, BOARD_CELLS
    jb   .next_rank

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawUpperStaticText
;
; Paints the plain labels beside the board. These are intentionally drawn at
; runtime instead of being stored in an upper-screen bitmap.
; Preserves all registers.
; ------------------------------------------------------------------
DrawUpperStaticText:
    push cx
    push dx
    push si

    mov  word [SmallDrawSegment], BOARD_VRAM_SEG

    mov  cx, 24
    mov  dx, 100
    mov  si, UpperTitleLine1
    call DrawSmallStringPaint

    mov  cx, 30
    mov  dx, 112
    mov  si, UpperTitleLine2
    call DrawSmallStringPaint

    mov  cx, 24
    mov  dx, 136
    mov  si, UpperControlLine1
    call DrawSmallStringPaint

    mov  cx, 36
    mov  dx, 148
    mov  si, UpperControlLine2
    call DrawSmallStringPaint

    mov  cx, 30
    mov  dx, 164
    mov  si, UpperControlLine3
    call DrawSmallStringPaint

    mov  cx, 24
    mov  dx, 176
    mov  si, UpperControlLine4
    call DrawSmallStringPaint

    mov  cx, 30
    mov  dx, 188
    mov  si, UpperControlLine5
    call DrawSmallStringPaint

    pop  si
    pop  dx
    pop  cx
    ret


; ------------------------------------------------------------------
; DrawMoveHistoryHeader / DrawRecentMovesXor
;
; The static title is painted once. The recent list is reversible: call it
; before changing history to erase the old list and again afterward to draw
; the new list. Up to eight half-moves are shown, oldest to newest:
;
;   W E2-E4
;   B E7-E5
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawMoveHistoryHeader:
    push cx
    push dx
    push si

    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, MOVE_LIST_X
    mov  dx, MOVE_LIST_TITLE_Y
    mov  si, LastMovesTitle
    call DrawSmallStringPaint

    pop  si
    pop  dx
    pop  cx
    ret


DrawRecentMovesXor:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  ax, [HistoryCount]
    or   ax, ax
    jnz  .history_present
    jmp  .done

.history_present:
    cmp  ax, MOVE_HISTORY_VISIBLE_LINES
    jbe  .line_count_ready
    mov  al, MOVE_HISTORY_VISIBLE_LINES

.line_count_ready:
    mov  [MoveDisplayLineCount], al

    ; HistoryNext points after the newest record. Subtracting the visible
    ; count produces the oldest record to display; byte arithmetic naturally
    ; wraps around the 256-entry circular buffer.
    mov  al, [HistoryNext]
    sub  al, [MoveDisplayLineCount]
    mov  [MoveDisplayRecordIndex], al
    mov  byte [MoveDisplayLineNumber], 0

.next_line:
    call FormatMoveDisplayLine

    xor  ax, ax
    mov  al, [MoveDisplayLineNumber]
    mov  bl, MOVE_LIST_LINE_STEP
    mul  bl
    add  ax, MOVE_LIST_FIRST_Y
    mov  dx, ax
    mov  cx, MOVE_LIST_X
    mov  si, MoveLineText
    call DrawSmallStringXor

    inc  byte [MoveDisplayRecordIndex]
    inc  byte [MoveDisplayLineNumber]
    mov  al, [MoveDisplayLineNumber]
    cmp  al, [MoveDisplayLineCount]
    jb   .next_line

.done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; FormatMoveDisplayLine
;
; Formats the record selected by MoveDisplayRecordIndex into:
;
;   "W A2-A4 " or "B G8-F6"
;   "W A7-A8Q" for promotion (Q/R/B/N suffix)
;
; BoardPosition row zero is rank 8, so rank character = '8' - row.
; Preserves all registers.
; ------------------------------------------------------------------
FormatMoveDisplayLine:
    push ax
    push bx
    push di

    xor  bx, bx
    mov  bl, [MoveDisplayRecordIndex]
    mov  di, bx
    shl  di, 1
    shl  di, 1
    shl  di, 1
    lea  di, [MoveHistory + di]

    mov  byte [MoveLineText + 0], 57h
    test byte [di + 2], BLACK
    jz   .side_ready
    mov  byte [MoveLineText + 0], 42h

.side_ready:
    mov  al, [di + 0]
    mov  ah, al
    and  al, 07h
    add  al, 41h
    mov  [MoveLineText + 2], al
    mov  al, ah
    shr  al, 1
    shr  al, 1
    shr  al, 1
    mov  ah, 38h
    sub  ah, al
    mov  [MoveLineText + 3], ah

    mov  al, [di + 1]
    mov  ah, al
    and  al, 07h
    add  al, 41h
    mov  [MoveLineText + 5], al
    mov  al, ah
    shr  al, 1
    shr  al, 1
    shr  al, 1
    mov  ah, 38h
    sub  ah, al
    mov  [MoveLineText + 6], ah

    mov  byte [MoveLineText + 7], ' '
    test byte [di + 4], MOVE_FLAG_PROMOTION
    jz   .promotion_suffix_done

    mov  al, [di + 7]
    and  al, 07h
    cmp  al, QUEEN
    jne  .not_queen
    mov  byte [MoveLineText + 7], 'Q'
    jmp  .promotion_suffix_done
.not_queen:
    cmp  al, ROOK
    jne  .not_rook
    mov  byte [MoveLineText + 7], 'R'
    jmp  .promotion_suffix_done
.not_rook:
    cmp  al, BISHOP
    jne  .not_bishop
    mov  byte [MoveLineText + 7], 'B'
    jmp  .promotion_suffix_done
.not_bishop:
    cmp  al, KNIGHT
    jne  .promotion_suffix_done
    mov  byte [MoveLineText + 7], 'N'

.promotion_suffix_done:
    pop  di
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawLargeStringPaint / DrawLargeStringXor
;
; Doubles each 5x7 font pixel into a 2x2 block. Character advance is 12 pixels.
; ------------------------------------------------------------------
DrawLargeStringPaint:
    mov  byte [SmallDrawMode], SMALL_DRAW_PAINT
    jmp  DrawLargeString


DrawLargeStringXor:
    mov  byte [SmallDrawMode], SMALL_DRAW_XOR


DrawLargeString:
    push ax
    push cx
    push dx
    push si

.next_character:
    lodsb
    or   al, al
    jz   .done
    call DrawLargeCharacter
    add  cx, 12
    jmp  .next_character

.done:
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


DrawLargeCharacter:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov  di, cx
    mov  bp, dx
    call GetSmallGlyphPointer
    mov  bl, 5

.next_glyph_column:
    lodsb
    mov  ah, al
    mov  bh, 7
    mov  cx, di
    mov  dx, bp

.next_glyph_row:
    test ah, 01h
    jz   .pixel_done
    call DrawLargeFontDot

.pixel_done:
    shr  ah, 1
    add  dx, 2
    dec  bh
    jnz  .next_glyph_row

    add  di, 2
    dec  bl
    jnz  .next_glyph_column

    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


DrawLargeFontDot:
    push cx
    push dx

    cmp  byte [SmallDrawMode], SMALL_DRAW_XOR
    je   .xor_top_left
    call PaintPixelSmall
    inc  cx
    call PaintPixelSmall
    inc  dx
    call PaintPixelSmall
    dec  cx
    call PaintPixelSmall
    jmp  .done

.xor_top_left:
    call XorPixelSmall
    inc  cx
    call XorPixelSmall
    inc  dx
    call XorPixelSmall
    dec  cx
    call XorPixelSmall

.done:
    pop  dx
    pop  cx
    ret


; ------------------------------------------------------------------
; DrawSmallStringPaint / DrawSmallStringXor
;
; Input:
;   DS:SI = zero-terminated string
;   CX    = left X coordinate
;   DX    = top Y coordinate
;
; Characters use a compact 5x7 font with a one-pixel gap.
; Preserves all registers.
; ------------------------------------------------------------------
DrawSmallStringPaint:
    mov  byte [SmallDrawMode], SMALL_DRAW_PAINT
    jmp  DrawSmallString


DrawSmallStringXor:
    mov  byte [SmallDrawMode], SMALL_DRAW_XOR


DrawSmallString:
    push ax
    push cx
    push dx
    push si

.next_character:
    lodsb
    or   al, al
    jz   .done
    call DrawSmallCharacter
    add  cx, 6
    jmp  .next_character

.done:
    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


DrawSmallCharacterPaint:
    mov  byte [SmallDrawMode], SMALL_DRAW_PAINT
    jmp  DrawSmallCharacter


DrawSmallCharacterXor:
    mov  byte [SmallDrawMode], SMALL_DRAW_XOR


; ------------------------------------------------------------------
; DrawSmallCharacter
;
; Input:
;   AL = ASCII character
;   CX = left X coordinate
;   DX = top Y coordinate
;
; The glyph contains five column bytes; bit zero is the top pixel.
; Preserves all registers.
; ------------------------------------------------------------------
DrawSmallCharacter:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov  di, cx
    mov  bp, dx
    call GetSmallGlyphPointer
    mov  bl, 5

.next_glyph_column:
    lodsb
    mov  ah, al
    mov  bh, 7
    mov  cx, di
    mov  dx, bp

.next_glyph_row:
    test ah, 01h
    jz   .pixel_done
    cmp  byte [SmallDrawMode], SMALL_DRAW_XOR
    je   .xor_pixel
    call PaintPixelSmall
    jmp  .pixel_done

.xor_pixel:
    call XorPixelSmall

.pixel_done:
    shr  ah, 1
    inc  dx
    dec  bh
    jnz  .next_glyph_row

    inc  di
    dec  bl
    jnz  .next_glyph_column

    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; GetSmallGlyphPointer
;
; Input:  AL = ASCII character
; Output: SI = address of five-byte glyph
; ------------------------------------------------------------------
GetSmallGlyphPointer:
    cmp  al, 2Dh
    jne  .not_hyphen
    mov  si, SmallGlyphHyphen
    ret

.not_hyphen:
    cmp  al, 30h
    jb   .space
    cmp  al, 39h
    ja   .not_digit

    sub  al, 30h
    xor  bx, bx
    mov  bl, al
    shl  bx, 1
    mov  si, [SmallDigitTable + bx]
    ret

.not_digit:
    cmp  al, 41h
    jb   .space
    cmp  al, 5Ah
    ja   .space

    sub  al, 41h
    xor  bx, bx
    mov  bl, al
    shl  bx, 1
    mov  si, [SmallLetterTable + bx]
    ret

.space:
    mov  si, SmallGlyphSpace
    ret


; ------------------------------------------------------------------
; DrawPieceCodeOpaque / ErasePieceCodeOpaque
;
; Input:
;   AL = complete BoardPosition piece code
;   BL = column, 0..7
;   BH = row,    0..7
;
; Drawing selects both the visible artwork and the solid silhouette mask.
; Erasing restores only the masked silhouette pixels from the board's native
; dark or AAh/55h background. EMPTY or invalid codes are ignored.
; Preserves all registers.
; ------------------------------------------------------------------
DrawPieceCodeOpaque:
    push ax
    push bx
    push dx
    push si
    push di

    mov  ah, al
    and  al, 07h
    jz   .done
    cmp  al, KING
    ja   .done

    dec  al
    xor  di, di
    mov  dl, al
    xor  dh, dh
    mov  di, dx
    shl  di, 1

    mov  si, [OutlinePieceTable + di]
    test ah, BLACK
    jz   .mask_ready

.solid_art:
    mov  si, [SolidPieceTable + di]

.mask_ready:
    ; DI always addresses the complete silhouette used as the opacity mask.
    mov  di, [SolidPieceTable + di]
    call DrawPieceOpaque

.done:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


ErasePieceCodeOpaque:
    push ax
    push bx
    push dx
    push si
    push di

    and  al, 07h
    jz   .done
    cmp  al, KING
    ja   .done

    dec  al
    xor  di, di
    mov  dl, al
    xor  dh, dh
    mov  di, dx
    shl  di, 1
    mov  si, [SolidPieceTable + di]
    call RestorePieceBackground

.done:
    pop  di
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawClockFace
;
; Paints a traditional two-player chess clock in the lower bank:
; rectangular case, center divider, two top plungers, WHITE/BLACK labels,
; and two analog faces with twelve hour marks. The case is separate from
; the XOR hands and active-side underline so RTC updates do not need
; to clear or rebuild the information panel.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawClockFace:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

    ; Main clock case.
    mov  ax, CHESS_CLOCK_LEFT
    mov  bx, CHESS_CLOCK_TOP
    mov  cx, CHESS_CLOCK_RIGHT
    mov  dx, CHESS_CLOCK_BOTTOM
    call DrawClockRectanglePaint

    ; Center divider between the two mechanisms.
    mov  ax, CHESS_CLOCK_DIVIDER_X
    mov  bx, CHESS_CLOCK_TOP
    mov  cx, CHESS_CLOCK_DIVIDER_X
    mov  dx, CHESS_CLOCK_BOTTOM
    call DrawClockLinePaint

    ; The two push buttons make the silhouette immediately recognizable as
    ; a chess clock rather than two unrelated wall clocks.
    mov  ax, WHITE_CLOCK_CENTER_X - 12
    mov  bx, CHESS_CLOCK_TOP - 12
    mov  cx, WHITE_CLOCK_CENTER_X + 12
    mov  dx, CHESS_CLOCK_TOP
    call DrawClockRectanglePaint

    mov  ax, BLACK_CLOCK_CENTER_X - 12
    mov  bx, CHESS_CLOCK_TOP - 12
    mov  cx, BLACK_CLOCK_CENTER_X + 12
    mov  dx, CHESS_CLOCK_TOP
    call DrawClockRectanglePaint

    ; White dial.
    mov  cx, WHITE_CLOCK_CENTER_X
    mov  dx, CLOCK_CENTER_Y
    call DrawClockDial

    ; Black dial.
    mov  cx, BLACK_CLOCK_CENTER_X
    mov  dx, CLOCK_CENTER_Y
    call DrawClockDial

    ; Permanent player labels.
    mov  cx, WHITE_CLOCK_CENTER_X - 15
    mov  dx, 185
    mov  si, WhiteClockLabel
    call DrawSmallStringPaint

    mov  cx, BLACK_CLOCK_CENTER_X - 15
    mov  dx, 185
    mov  si, BlackClockLabel
    call DrawSmallStringPaint

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  bp
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: AX=left, BX=top, CX=right, DX=bottom.
; Preserves all registers.
DrawClockRectanglePaint:
    push ax
    push bx
    push cx
    push dx

    mov  [ClockRectLeft], ax
    mov  [ClockRectTop], bx
    mov  [ClockRectRight], cx
    mov  [ClockRectBottom], dx

    ; Top.
    mov  dx, bx
    call DrawClockLinePaint

    ; Bottom.
    mov  ax, [ClockRectLeft]
    mov  bx, [ClockRectBottom]
    mov  cx, [ClockRectRight]
    mov  dx, [ClockRectBottom]
    call DrawClockLinePaint

    ; Left.
    mov  ax, [ClockRectLeft]
    mov  bx, [ClockRectTop]
    mov  cx, [ClockRectLeft]
    mov  dx, [ClockRectBottom]
    call DrawClockLinePaint

    ; Right.
    mov  ax, [ClockRectRight]
    mov  bx, [ClockRectTop]
    mov  cx, [ClockRectRight]
    mov  dx, [ClockRectBottom]
    call DrawClockLinePaint

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: CX=center X, DX=center Y.
; Paints one circular face and its twelve marks.
DrawClockDial:
    mov  [ClockCenterX], cx
    mov  [ClockCenterY], dx

    mov  word [ClockCircleX], CLOCK_FACE_RADIUS
    mov  word [ClockCircleY], 0
    mov  ax, 1
    sub  ax, CLOCK_FACE_RADIUS
    mov  [ClockCircleError], ax

.circle_loop:
    call PlotClockCirclePoints

    mov  ax, [ClockCircleX]
    cmp  ax, [ClockCircleY]
    jl   .circle_done

    inc  word [ClockCircleY]
    cmp  word [ClockCircleError], 0
    jl   .circle_inside

    dec  word [ClockCircleX]
    mov  ax, [ClockCircleY]
    sub  ax, [ClockCircleX]
    shl  ax, 1
    inc  ax
    add  [ClockCircleError], ax
    jmp  .circle_loop

.circle_inside:
    mov  ax, [ClockCircleY]
    shl  ax, 1
    inc  ax
    add  [ClockCircleError], ax
    jmp  .circle_loop

.circle_done:
    mov  si, ClockTickTable
    mov  bp, CLOCK_TICK_COUNT

.next_tick:
    mov  ax, [si + 0]
    add  ax, [ClockCenterX]
    mov  bx, [si + 2]
    add  bx, [ClockCenterY]
    mov  cx, [si + 4]
    add  cx, [ClockCenterX]
    mov  dx, [si + 6]
    add  dx, [ClockCenterY]
    call DrawClockLinePaint
    add  si, 8
    dec  bp
    jnz  .next_tick
    ret


; Paints all eight symmetric points for the current midpoint-circle X/Y.
; Preserves all registers.
PlotClockCirclePoints:
    push ax
    push cx
    push dx

    mov  ax, [ClockCircleX]
    mov  cx, [ClockCenterX]
    add  cx, ax
    mov  ax, [ClockCircleY]
    mov  dx, [ClockCenterY]
    add  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleX]
    mov  cx, [ClockCenterX]
    sub  cx, ax
    mov  ax, [ClockCircleY]
    mov  dx, [ClockCenterY]
    add  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleX]
    mov  cx, [ClockCenterX]
    add  cx, ax
    mov  ax, [ClockCircleY]
    mov  dx, [ClockCenterY]
    sub  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleX]
    mov  cx, [ClockCenterX]
    sub  cx, ax
    mov  ax, [ClockCircleY]
    mov  dx, [ClockCenterY]
    sub  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleY]
    mov  cx, [ClockCenterX]
    add  cx, ax
    mov  ax, [ClockCircleX]
    mov  dx, [ClockCenterY]
    add  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleY]
    mov  cx, [ClockCenterX]
    sub  cx, ax
    mov  ax, [ClockCircleX]
    mov  dx, [ClockCenterY]
    add  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleY]
    mov  cx, [ClockCenterX]
    add  cx, ax
    mov  ax, [ClockCircleX]
    mov  dx, [ClockCenterY]
    sub  dx, ax
    call PaintPixelSmall

    mov  ax, [ClockCircleY]
    mov  cx, [ClockCenterX]
    sub  cx, ax
    mov  ax, [ClockCircleX]
    mov  dx, [ClockCenterY]
    sub  dx, ax
    call PaintPixelSmall

    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawClockHandsXor
;
; Draws or erases both players' hands. Each player has an independent
; hour/minute/second triplet. Calling this routine twice without changing
; either time restores both permanent clock faces.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawClockHandsXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

    mov  bp, WhiteClockHour
    mov  cx, WHITE_CLOCK_CENTER_X
    mov  dx, CLOCK_CENTER_Y
    call DrawClockHandsForSideXor

    mov  bp, BlackClockHour
    mov  cx, BLACK_CLOCK_CENTER_X
    mov  dx, CLOCK_CENTER_Y
    call DrawClockHandsForSideXor

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  bp
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: BP points to hour/minute/second bytes, CX/DX select the dial center.
; SmallDrawSegment must already select the lower bank.
DrawClockHandsForSideXor:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  [ClockCenterX], cx
    mov  [ClockCenterY], dx

    ; Hour-hand position includes five minute subdivisions per hour.
    xor  ax, ax
    mov  al, [ds:bp + 1]
    mov  bl, 12
    div  bl
    mov  dl, al

    xor  ax, ax
    mov  al, [ds:bp + 0]
    cmp  al, 12
    jb   .hour_normalized
    sub  al, 12

.hour_normalized:
    mov  bl, 5
    mul  bl
    add  al, dl
    mov  si, ClockHourHandTable
    call DrawClockHandFromTable

    xor  ax, ax
    mov  al, [ds:bp + 1]
    mov  si, ClockMinuteHandTable
    call DrawClockHandFromTable

    xor  ax, ax
    mov  al, [ds:bp + 2]
    mov  si, ClockSecondHandTable
    call DrawClockHandFromTable

    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; Input: AL=hand position 0..59, SI=table of sixty signed X/Y word pairs.
DrawClockHandFromTable:
    xor  ah, ah
    shl  ax, 1
    shl  ax, 1
    add  si, ax

    ; Scale the original hand tables to 1/2 size so they fit the compact
    ; 34-pixel clock faces stored in the static lower-screen bitmap.
    mov  cx, [si + 0]
    sar  cx, 1
    add  cx, [ClockCenterX]
    mov  dx, [si + 2]
    sar  dx, 1
    add  dx, [ClockCenterY]
    mov  ax, [ClockCenterX]
    mov  bx, [ClockCenterY]
    call DrawClockLineXor
    ret


; Draws or erases only the clock belonging to CurrentTurn.
DrawActiveClockHandsXor:
    push ax
    push cx
    push dx
    push bp

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

    test byte [CurrentTurn], BLACK
    jnz  .black
    mov  bp, WhiteClockHour
    mov  cx, WHITE_CLOCK_CENTER_X
    jmp  .draw

.black:
    mov  bp, BlackClockHour
    mov  cx, BLACK_CLOCK_CENTER_X

.draw:
    mov  dx, CLOCK_CENTER_Y
    call DrawClockHandsForSideXor

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  bp
    pop  dx
    pop  cx
    pop  ax
    ret


; Underlines the active player's permanent WHITE/BLACK label. Erase it before
; changing CurrentTurn and draw it again afterward.
DrawClockActiveIndicatorXor:
    push ax
    push bx
    push cx
    push dx

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

    test byte [CurrentTurn], BLACK
    jnz  .black
    mov  ax, WHITE_CLOCK_CENTER_X - 18
    mov  cx, WHITE_CLOCK_CENTER_X + 18
    jmp  .draw

.black:
    mov  ax, BLACK_CLOCK_CENTER_X - 18
    mov  cx, BLACK_CLOCK_CENTER_X + 18

.draw:
    mov  bx, 193
    mov  dx, 193
    call DrawClockLineXor
    mov  bx, 194
    mov  dx, 194
    call DrawClockLineXor

    pop  ax
    mov  [SmallDrawSegment], ax

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ServiceClockUpdates
;
; Atomically transfers the ISR-owned pending counters, then updates VRAM in
; foreground context. White and Black have separate queues so an interrupt
; occurring at a turn boundary can never be charged to the wrong player.
;
; Preserves all registers.
; ------------------------------------------------------------------
ServiceClockUpdates:
    push ax
    push cx
    push bp

    pushf
    cli
    mov  al, [WhiteSecondsPending]
    mov  [ClockApplyCount], al
    mov  byte [WhiteSecondsPending], 0
    mov  al, [BlackSecondsPending]
    mov  [ClockBlackApplyCount], al
    mov  byte [BlackSecondsPending], 0
    popf

    mov  al, [ClockApplyCount]
    or   al, al
    jz   .black
    mov  bp, WhiteClockHour
    mov  cx, WHITE_CLOCK_CENTER_X
    call ApplyClockSecondsForSide
    cmp  byte [GameState], GAME_PLAYING
    jne  .done

.black:
    mov  al, [ClockBlackApplyCount]
    or   al, al
    jz   .done
    mov  bp, BlackClockHour
    mov  cx, BLACK_CLOCK_CENTER_X
    call ApplyClockSecondsForSide

.done:
    pop  bp
    pop  cx
    pop  ax
    ret


; Input:
;   AL = number of elapsed seconds
;   BP = address of hour/minute/second countdown triplet
;   CX = dial center X
;
; The old hands are erased once, all queued seconds are applied, and the new
; hands are drawn once. A clock at 00:00:00 remains stopped at zero.
ApplyClockSecondsForSide:
    push ax
    push bx
    push cx
    push dx

    mov  [ClockApplyCount], al

    mov  al, [ds:bp + 0]
    or   al, [ds:bp + 1]
    or   al, [ds:bp + 2]
    jz   .done

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], PANEL_VRAM_SEG

    mov  dx, CLOCK_CENTER_Y
    call DrawClockHandsForSideXor

.decrement_loop:
    cmp  byte [ClockApplyCount], 0
    je   .redraw

    mov  al, [ds:bp + 0]
    or   al, [ds:bp + 1]
    or   al, [ds:bp + 2]
    jz   .redraw

    cmp  byte [ds:bp + 2], 0
    jne  .decrement_second
    cmp  byte [ds:bp + 1], 0
    jne  .borrow_minute

    dec  byte [ds:bp + 0]
    mov  byte [ds:bp + 1], 59
    mov  byte [ds:bp + 2], 59
    jmp  .one_applied

.borrow_minute:
    dec  byte [ds:bp + 1]
    mov  byte [ds:bp + 2], 59
    jmp  .one_applied

.decrement_second:
    dec  byte [ds:bp + 2]

.one_applied:
    dec  byte [ClockApplyCount]
    jmp  .decrement_loop

.redraw:
    mov  dx, CLOCK_CENTER_Y
    call DrawClockHandsForSideXor

    pop  ax
    mov  [SmallDrawSegment], ax
    call HandleFlagFall

.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; HandleFlagFall
;
; BP identifies the White or Black clock triplet. If that clock has just
; reached 00:00:00, freeze the game, remove the active-clock underline,
; announce the opponent as winner, and play one long alarm.
; ------------------------------------------------------------------
MaybePlayFlagFallSound:
HandleFlagFall:
    push ax

    mov  al, [ds:bp + 0]
    or   al, [ds:bp + 1]
    or   al, [ds:bp + 2]
    jnz  .done
    cmp  byte [GameState], GAME_PLAYING
    jne  .done

    mov  ax, WhiteClockHour
    cmp  bp, ax
    jne  .black
    cmp  byte [WhiteFlagSoundPlayed], 0
    jne  .done
    mov  byte [WhiteFlagSoundPlayed], 1
    mov  byte [TimeWinner], BLACK
    jmp  .finish_game

.black:
    cmp  byte [BlackFlagSoundPlayed], 0
    jne  .done
    mov  byte [BlackFlagSoundPlayed], 1
    mov  byte [TimeWinner], 0

.finish_game:
    mov  byte [GameState], GAME_TIME_FORFEIT

    ; No further ISR time is accepted after GameState changes. Discard any
    ; already transferred seconds belonging to the other clock.
    mov  byte [ClockApplyCount], 0
    mov  byte [ClockBlackApplyCount], 0

    ; CHECK shares the winner-message area, so remove it first when present.
    cmp  byte [CheckIndicatorVisible], 0
    je   .check_removed
    call DrawCheckIndicatorXor
    mov  byte [CheckIndicatorVisible], 0

.check_removed:
    call DrawClockActiveIndicatorXor
    call DrawTimeWinnerIndicatorXor
    call PlayFlagFallSound

.done:
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawTimeWinnerIndicatorXor
;
; Draws WHITE WINS or BLACK WINS in the upper-bank terminal-message area.
; ------------------------------------------------------------------
DrawTimeWinnerIndicatorXor:
    push ax
    push cx
    push dx
    push si

    mov  ax, [SmallDrawSegment]
    push ax
    mov  word [SmallDrawSegment], BOARD_VRAM_SEG
    mov  cx, 18
    mov  dx, 40
    mov  si, WhiteWinsText
    test byte [TimeWinner], BLACK
    jz   .draw
    mov  si, BlackWinsText

.draw:
    call DrawSmallStringXor
    pop  ax
    mov  [SmallDrawSegment], ax

    pop  si
    pop  dx
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; SetClockTimeAndRedraw
;
; Manual/test entry point. Normal animation is driven by INT 7Ah and
; ServiceClockUpdates.
;
; Input:
;   AL = hour,   0..23
;   AH = minute, 0..59
;   DL = second, 0..59
;
; The old hands are erased, the new time is installed, and the hands are
; redrawn. No interrupt vector, RTC mode, or acknowledgment is installed in
; this build.
; ------------------------------------------------------------------
SetClockTimeAndRedraw:
    push ax
    push dx
    call DrawActiveClockHandsXor
    pop  dx
    pop  ax

    test byte [CurrentTurn], BLACK
    jnz  .black
    mov  si, WhiteClockHour
    jmp  .store

.black:
    mov  si, BlackClockHour

.store:
    mov  [si + 0], al
    mov  [si + 1], ah
    mov  [si + 2], dl
    call DrawActiveClockHandsXor
    ret


; ------------------------------------------------------------------
; SN76489AN foreground sound effects -- QX-11 port 14h
;
; The game uses tone channel 0 and the noise channel only. Every public
; effect preserves all registers, starts from a known muted state, and leaves
; the PSG silent. Interrupts remain enabled during the short delay loops, so
; INT 7Ah continues to account for elapsed chess-clock time.
; ------------------------------------------------------------------
SilenceAllSound:
    push ax

    mov  al, 09Fh           ; Tone 0 attenuation = silent.
    out  PSG_DATA_PORT, al
    mov  al, 0BFh           ; Tone 1 attenuation = silent.
    out  PSG_DATA_PORT, al
    mov  al, 0DFh           ; Tone 2 attenuation = silent.
    out  PSG_DATA_PORT, al
    mov  al, 0FFh           ; Noise attenuation = silent.
    out  PSG_DATA_PORT, al

    pop  ax
    ret


; AX = 10-bit tone divider for channel 0.
SetPSGTone0Period:
    push ax
    push bx
    push cx

    mov  bx, ax
    and  al, 0Fh
    or   al, 080h
    out  PSG_DATA_PORT, al

    mov  ax, bx
    mov  cl, 4
    shr  ax, cl
    and  al, 3Fh
    out  PSG_DATA_PORT, al

    pop  cx
    pop  bx
    pop  ax
    ret


; AL = attenuation 0..15 for tone channel 0.
SetPSGTone0Volume:
    push ax
    and  al, 0Fh
    or   al, 090h
    out  PSG_DATA_PORT, al
    pop  ax
    ret


; AL = SN76489 noise-control value 0..7.
SetPSGNoiseControl:
    push ax
    and  al, 07h
    or   al, 0E0h
    out  PSG_DATA_PORT, al
    pop  ax
    ret


; AL = attenuation 0..15 for the noise channel.
SetPSGNoiseVolume:
    push ax
    and  al, 0Fh
    or   al, 0F0h
    out  PSG_DATA_PORT, al
    pop  ax
    ret


; CX = duration units. One unit is roughly 12 ms on the native 4.9 MHz CPU.
; This deliberately uses no DOS or BIOS service and leaves interrupts enabled.
SoundDelayUnits:
    push bx
    push cx

    mov  bx, cx
.outer:
    mov  cx, 3500
.inner:
    loop .inner
    dec  bx
    jnz  .outer

    pop  cx
    pop  bx
    ret


PlayMoveSound:
    push ax
    push cx

    call SilenceAllSound
    mov  ax, 0077h          ; Same short, bright range used by QX-11 beeps.
    call SetPSGTone0Period
    mov  al, 5
    call SetPSGTone0Volume
    mov  cx, 2
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret


PlayCaptureSound:
    push ax
    push cx

    call SilenceAllSound
    mov  ax, 0180h          ; Low tone beneath a short white-noise thump.
    call SetPSGTone0Period
    mov  al, 6
    call SetPSGTone0Volume
    mov  al, 6              ; White noise, fixed low-rate source.
    call SetPSGNoiseControl
    mov  al, 4
    call SetPSGNoiseVolume
    mov  cx, 4
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret


PlayIllegalMoveSound:
    push ax
    push cx

    call SilenceAllSound
    mov  ax, 02A0h
    call SetPSGTone0Period
    mov  al, 3
    call SetPSGTone0Volume
    mov  al, 6
    call SetPSGNoiseControl
    mov  al, 8
    call SetPSGNoiseVolume
    mov  cx, 7
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret


PlayCheckSound:
    push ax
    push cx

    call SilenceAllSound
    mov  ax, 00BEh
    call SetPSGTone0Period
    mov  al, 4
    call SetPSGTone0Volume
    mov  cx, 3
    call SoundDelayUnits
    mov  al, 15
    call SetPSGTone0Volume
    mov  cx, 1
    call SoundDelayUnits
    mov  ax, 0077h
    call SetPSGTone0Period
    mov  al, 3
    call SetPSGTone0Volume
    mov  cx, 3
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret


PlayFlagFallSound:
    push ax
    push cx

    ; A sustained bright tone is deliberately much longer than the other
    ; foreground effects so a flag fall cannot be missed on real hardware.
    call SilenceAllSound
    mov  ax, 0077h
    call SetPSGTone0Period
    mov  al, 1
    call SetPSGTone0Volume
    mov  cx, 150            ; Approximately 1.8 seconds at 4.9 MHz.
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawClockLinePaint / DrawClockLineXor
;
; Signed all-octant Bresenham line used for clock ticks and hands.
;
; Input:
;   AX = X0, BX = Y0, CX = X1, DX = Y1
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawClockLinePaint:
    mov  byte [ClockLineMode], SMALL_DRAW_PAINT
    jmp  DrawClockLineCommon


DrawClockLineXor:
    mov  byte [ClockLineMode], SMALL_DRAW_XOR


DrawClockLineCommon:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  [ClockLineX0], ax
    mov  [ClockLineY0], bx
    mov  [ClockLineX1], cx
    mov  [ClockLineY1], dx

    mov  ax, cx
    sub  ax, [ClockLineX0]
    jge  .positive_dx
    neg  ax
    mov  word [ClockLineStepX], -1
    jmp  .dx_ready

.positive_dx:
    mov  word [ClockLineStepX], 1

.dx_ready:
    mov  [ClockLineDeltaX], ax

    mov  ax, dx
    sub  ax, [ClockLineY0]
    jge  .positive_dy
    neg  ax
    mov  word [ClockLineStepY], -1
    jmp  .dy_ready

.positive_dy:
    mov  word [ClockLineStepY], 1

.dy_ready:
    neg  ax
    mov  [ClockLineDeltaY], ax
    add  ax, [ClockLineDeltaX]
    mov  [ClockLineError], ax

.next_pixel:
    mov  cx, [ClockLineX0]
    mov  dx, [ClockLineY0]
    cmp  byte [ClockLineMode], SMALL_DRAW_XOR
    je   .xor_pixel
    call PaintPixelSmall
    jmp  .pixel_drawn

.xor_pixel:
    call XorPixelSmall

.pixel_drawn:
    mov  ax, [ClockLineX0]
    cmp  ax, [ClockLineX1]
    jne  .continue_line
    mov  ax, [ClockLineY0]
    cmp  ax, [ClockLineY1]
    je   .done

.continue_line:
    mov  ax, [ClockLineError]
    shl  ax, 1
    mov  [ClockLineDoubleError], ax

    cmp  ax, [ClockLineDeltaY]
    jl   .skip_x_step
    mov  ax, [ClockLineDeltaY]
    add  [ClockLineError], ax
    mov  ax, [ClockLineStepX]
    add  [ClockLineX0], ax

.skip_x_step:
    mov  ax, [ClockLineDoubleError]
    cmp  ax, [ClockLineDeltaX]
    jg   .next_pixel
    mov  ax, [ClockLineDeltaX]
    add  [ClockLineError], ax
    mov  ax, [ClockLineStepY]
    add  [ClockLineY0], ax
    jmp  .next_pixel

.done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; ClearUpperScreen / LoadLowerStaticBitmap
;
; ClearUpperScreen clears only the visible 200 bytes in each upper-bank VRAM
; column. LoadLowerStaticBitmap copies the one permanent 80-column x 200-byte
; lower image. Neither routine touches the unused gaps or display registers.
;
; Preserves all registers and flags.
; ------------------------------------------------------------------
; ------------------------------------------------------------------
; InitializeGAVDPFromPRE
;
; Exact display-controller initialization recovered from original Epson
; PRE.EXE at load-module offsets 1137h..1161h:
;   8000:C060 = 35h
;   8000:D068 = 02h
;   8000:C261 = 00h
;   8000:C462 = 00h
;   8000:C663 = 00h
;
; Preserves registers and flags.
; ------------------------------------------------------------------
InitializeGAVDPFromPRE:
    pushf
    push ax
    push bx
    push es

    mov  ax, 8000h
    mov  es, ax

    mov  bx, 0C060h
    mov  al, 35h
    mov  es:[bx], al

    mov  bx, 0D068h
    mov  al, 02h
    mov  es:[bx], al

    xor  al, al
    mov  bx, 0C261h
    mov  es:[bx], al
    mov  bx, 0C462h
    mov  es:[bx], al
    mov  bx, 0C663h
    mov  es:[bx], al

    pop  es
    pop  bx
    pop  ax
    popf
    ret


ShowPhase6IISplash:
    push ax
    push cx
    push si
    push di
    push es

    ; Load IMG.DAT using the same external scanline-major format accepted by
    ; Epson PRE.EXE.  If the file is absent or invalid, skip the splash and
    ; continue into the game rather than failing startup.
    call DrawCompressedVRAMSnapshot
    jc   .skip_splash

    call PlaySplashTune
    xor  ax, ax
    int  16h
    call SilenceAllSound

.skip_splash:
    pop  es
    pop  di
    pop  si
    pop  cx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawCompressedVRAMSnapshot
;
; Restores a hardware-validated QX-11 VRAM snapshot. BIOS mode 7 has already
; cleared the screen, so zero regions are omitted. Each record is:
;   word destination offset
;   byte literal length (1..255)
;   literal bytes
; A destination offset of FFFFh terminates the stream.
;
; Each literal is copied with a short REP MOVSB burst. No burst exceeds 255
; bytes, avoiding the long uninterrupted transfer that failed on real HW.
; ------------------------------------------------------------------
DrawCompressedVRAMSnapshot:
    pushf
    push ax
    push cx
    push si
    push di
    push ds
    push es

    cld
    push cs
    pop  ds
    mov  ax,8000h
    mov  es,ax
    mov  si,CompressedVRAMSnapshot

.next_record:
    lodsw
    cmp  ax,0FFFFh
    je   .done
    mov  di,ax
    lodsb
    xor  ch,ch
    mov  cl,al
    rep  movsb
    jmp  .next_record

.done:
    pop  es
    pop  ds
    pop  di
    pop  si
    pop  cx
    pop  ax
    popf
    clc
    ret


PlaySplashTune:
    push ax
    push cx

    call SilenceAllSound
    mov  al, 5
    call SetPSGTone0Volume

    mov  ax, 0190h
    call SetPSGTone0Period
    mov  cx, 5
    call SoundDelayUnits
    mov  ax, 0140h
    call SetPSGTone0Period
    mov  cx, 5
    call SoundDelayUnits
    mov  ax, 0100h
    call SetPSGTone0Period
    mov  cx, 5
    call SoundDelayUnits
    mov  ax, 00C8h
    call SetPSGTone0Period
    mov  cx, 7
    call SoundDelayUnits
    mov  ax, 0100h
    call SetPSGTone0Period
    mov  cx, 4
    call SoundDelayUnits
    mov  ax, 0098h
    call SetPSGTone0Period
    mov  cx, 10
    call SoundDelayUnits
    call SilenceAllSound

    pop  cx
    pop  ax
    ret



; ------------------------------------------------------------------
; ClearScreenWithBIOS
;
; Uses the QX-11 BIOS scroll-window service to clear the complete 80x25
; display safely. AL=0 requests clearing the entire window. Re-establish DS
; afterward because the BIOS is not assumed to preserve it.
; ------------------------------------------------------------------
ClearScreenWithBIOS:
    pushf
    push ax
    push bx
    push cx
    push dx

    mov  ax, 0600h
    xor  bx, bx
    xor  cx, cx
    mov  dx, 184Fh
    int  10h

    push cs
    pop  ds

    ; The BIOS scroll-window clear may alter display state. Restore the
    ; exact GAVDP configuration used by Epson PRE.EXE before redrawing.
    call InitializeGAVDPFromPRE

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    popf
    ret

ClearLowerScreen:
    pushf
    push ax
    push cx
    push di
    push bp
    push es

    cld
    mov  ax, PANEL_VRAM_SEG
    mov  es, ax
    xor  ax, ax
    xor  di, di
    mov  bp, VRAM_COLUMN_COUNT

.next_column:
    mov  cx, VRAM_COLUMN_HEIGHT
.clear_byte:
    mov  es:[di], al
    inc  di
    loop .clear_byte
    add  di, VRAM_COLUMN_SKIP
    dec  bp
    jnz  .next_column

    pop  es
    pop  bp
    pop  di
    pop  cx
    pop  ax
    popf
    ret


ClearUpperScreen:
    pushf
    push ax
    push cx
    push di
    push bp
    push es

    cld
    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    xor  ax, ax
    xor  di, di
    mov  bp, VRAM_COLUMN_COUNT

.next_column:
    mov  cx, VRAM_COLUMN_HEIGHT
.clear_byte:
    mov  es:[di], al
    inc  di
    loop .clear_byte
    add  di, VRAM_COLUMN_SKIP
    dec  bp
    jnz  .next_column

    pop  es
    pop  bp
    pop  di
    pop  cx
    pop  ax
    popf
    ret


LoadLowerStaticBitmap:
    pushf
    push ax
    push cx
    push si
    push di
    push bp
    push es

    cld
    mov  si, StaticLowerBitmap
    mov  ax, PANEL_VRAM_SEG
    mov  es, ax
    xor  di, di
    mov  bp, VRAM_COLUMN_COUNT

.next_column:
    mov  cx, VRAM_COLUMN_HEIGHT
.copy_byte:
    mov  al, [si]
    mov  es:[di], al
    inc  si
    inc  di
    loop .copy_byte

    add  di, VRAM_COLUMN_SKIP
    dec  bp
    jnz  .next_column

    pop  es
    pop  bp
    pop  di
    pop  si
    pop  cx
    pop  ax
    popf
    ret


; ------------------------------------------------------------------
; DrawAllPieces
;
; Walks the 64-byte BoardPosition array and paints every occupied square with
; the opaque masked renderer.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawAllPieces:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor  di, di              ; BoardPosition index, 0..63
    xor  dx, dx              ; DH=row, DL=column

.next_square:
    mov  al, [BoardPosition + di]
    inc  di
    test al, 07h
    jz   .advance_square

    ; DrawPieceCodeOpaque expects AL=piece code, BL=column, BH=row.
    mov  bx, dx
    call DrawPieceCodeOpaque

.advance_square:
    inc  dl
    cmp  dl, BOARD_CELLS
    jb   .next_square

    xor  dl, dl
    inc  dh
    cmp  dh, BOARD_CELLS
    jb   .next_square

    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawChessboard
;
; Draws the already-verified Blue wireframe and fills the 32
; alternating square interiors. Every board pixel goes through the
; proven PaintPixelBlue routine.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawChessboard:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; Draw the nine vertical wireframe lines.
    mov  si, BOARD_LEFT

.vertical_line:
    mov  dx, BOARD_TOP

.vertical_pixel:
    mov  cx, si
    call PaintPixelBlue
    inc  dx
    cmp  dx, BOARD_BOTTOM
    jbe  .vertical_pixel

    add  si, CELL_WIDTH
    cmp  si, BOARD_RIGHT
    jbe  .vertical_line

    ; Draw the nine horizontal wireframe lines.
    mov  si, BOARD_TOP

.horizontal_line:
    mov  cx, BOARD_LEFT

.horizontal_pixel:
    mov  dx, si
    call PaintPixelBlue
    inc  cx
    cmp  cx, BOARD_RIGHT
    jbe  .horizontal_pixel

    add  si, CELL_HEIGHT
    cmp  si, BOARD_BOTTOM
    jbe  .horizontal_line

    ; Dither alternating light-square interiors. Instead of setting every
    ; pixel (the old solid FFh appearance), paint only alternating pixels and
    ; reverse the phase on each scanline. The resulting AAh/55h texture makes
    ; outlined White pieces visibly distinct. The opaque piece renderer later
    ; masks this texture out of every occupied silhouette.
    ; BP=row, BX=column, SI=top, DI=left.
    xor  bp, bp
    mov  si, BOARD_TOP

.square_row:
    xor  bx, bx
    mov  di, BOARD_LEFT

.square_column:
    mov  ax, bp
    add  ax, bx
    test al, 1
    jnz  .skip_square

    mov  dx, si
    inc  dx                  ; top + 1

.fill_row:
    mov  cx, di
    inc  cx                  ; left + 1

.fill_pixel:
    mov  ax, cx
    xor  ax, dx
    test al, 1
    jnz  .dither_pixel_done
    call PaintPixelBlue
.dither_pixel_done:
    inc  cx

    mov  ax, di
    add  ax, CELL_WIDTH
    cmp  cx, ax
    jb   .fill_pixel

    inc  dx

    mov  ax, si
    add  ax, CELL_HEIGHT
    cmp  dx, ax
    jb   .fill_row

.skip_square:
    add  di, CELL_WIDTH
    inc  bx
    cmp  bx, BOARD_CELLS
    jb   .square_column

    add  si, CELL_HEIGHT
    inc  bp
    cmp  bp, BOARD_CELLS
    jb   .square_row

    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawSelectionFrameXor
;
; Draws a one-pixel XOR frame inside one board square.
;
; Input:
;   BL = board column, 0..7
;   BH = board row,    0..7
;
; Frame coordinates within the selected 48x36 square:
;   left   = square_left + 2
;   right  = square_left + 46
;   top    = square_top  + 1
;   bottom = square_top  + 35
;
; The visible detailed piece occupies X+4..43 and Y+2..33. The left and
; right selection-frame edges are at X+2 and X+46, so the frame remains
; separate. Calling this routine twice restores the original display.
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawSelectionFrameXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    cmp  bl, 7
    ja   .done
    cmp  bh, 7
    ja   .done

    ; SI = left edge = BOARD_LEFT + 2 + column * CELL_WIDTH.
    mov  si, BOARD_LEFT + 2
    xor  cx, cx
    mov  cl, bl
    jcxz .left_ready

.add_frame_column:
    add  si, CELL_WIDTH
    loop .add_frame_column

.left_ready:
    ; DI = right edge.
    mov  di, si
    add  di, CELL_WIDTH - 4

    ; BP = top edge = BOARD_TOP + 1 + row * CELL_HEIGHT.
    mov  bp, BOARD_TOP + 1
    xor  cx, cx
    mov  cl, bh
    jcxz .top_ready

.add_frame_row:
    add  bp, CELL_HEIGHT
    loop .add_frame_row

.top_ready:
    ; Draw top and bottom horizontal lines, inclusive.
    mov  cx, si

.horizontal_pixel:
    mov  dx, bp
    call XorPixelBlue
    mov  dx, bp
    add  dx, CELL_HEIGHT - 2
    call XorPixelBlue

    inc  cx
    cmp  cx, di
    jbe  .horizontal_pixel

    ; Draw the vertical sides between the horizontal lines.
    mov  dx, bp
    inc  dx
    mov  ax, bp
    add  ax, CELL_HEIGHT - 2

.vertical_pixel:
    mov  cx, si
    call XorPixelBlue
    mov  cx, di
    call XorPixelBlue

    inc  dx
    cmp  dx, ax
    jb   .vertical_pixel

.done:
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawSourceMarkerXor
;
; Visually marks the source square after Enter is pressed. Two short
; vertical marks are drawn in each side margin, outside the 32-pixel
; piece area. Calling the routine again removes the marker.
;
; Input:
;   BL = board column, 0..7
;   BH = board row,    0..7
;
; Preserves all registers.
; ------------------------------------------------------------------
DrawSourceMarkerXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    cmp  bl, 7
    ja   .done
    cmp  bh, 7
    ja   .done

    ; SI = square_left + 4.
    mov  si, BOARD_LEFT + 4
    xor  cx, cx
    mov  cl, bl
    jcxz .x_ready

.add_column:
    add  si, CELL_WIDTH
    loop .add_column

.x_ready:
    ; DI = square_left + 43. Both are outside piece X+8..39.
    mov  di, si
    add  di, CELL_WIDTH - 9

    ; BP = square_top + 6.
    mov  bp, BOARD_TOP + 6
    xor  cx, cx
    mov  cl, bh
    jcxz .y_ready

.add_row:
    add  bp, CELL_HEIGHT
    loop .add_row

.y_ready:
    xor  ax, ax              ; AX = marker-row counter, 0..3.

.marker_row:
    ; Upper pair at Y = top+6..top+9.
    mov  dx, bp
    add  dx, ax
    mov  cx, si
    call XorPixelBlue
    mov  cx, di
    call XorPixelBlue

    ; Lower pair at Y = top+26..top+29.
    add  dx, 20
    mov  cx, si
    call XorPixelBlue
    mov  cx, di
    call XorPixelBlue

    inc  ax
    cmp  ax, 4
    jb   .marker_row

.done:
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawMoveMarkersXor
;
; Walks MoveMask and XORs one marker on every legal destination.
; Calling it again against the unchanged board removes all markers.
; Quiet destinations receive a 3x3 center dot. Captures receive four 2x2
; blocks in the side margins. En passant uses the capture marker even though
; its destination square is empty.
; Preserves all registers.
; ------------------------------------------------------------------
DrawMoveMarkersXor:
    push ax
    push bx
    push cx
    push dx
    push si

    xor  bx, bx              ; BH=row, BL=column

.next_square:
    xor  dx, dx
    mov  dl, bh
    mov  si, dx
    mov  al, 1
    mov  cl, bl
    shl  al, cl
    test [MoveMask + si], al
    jz   .advance
    call DrawMoveMarkerXor

.advance:
    inc  bl
    cmp  bl, 8
    jb   .next_square
    xor  bl, bl
    inc  bh
    cmp  bh, 8
    jb   .next_square

    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawMoveMarkerXor
;
; Input: BL=column, BH=row.
; Chooses an empty-square dot or an occupied-square capture marker from
; BoardPosition. Calling it twice restores the underlying display.
; Preserves all registers.
; ------------------------------------------------------------------
DrawMoveMarkerXor:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    cmp  bl, 7
    jbe  .column_valid
    jmp  .done
.column_valid:
    cmp  bh, 7
    jbe  .coordinates_valid
    jmp  .done
.coordinates_valid:

    ; DI = BoardPosition row * 8 + column.
    xor  ax, ax
    mov  al, bh
    mov  di, ax
    shl  di, 1
    shl  di, 1
    shl  di, 1
    xor  ax, ax
    mov  al, bl
    add  di, ax

    ; SI = square left coordinate.
    xor  ax, ax
    mov  al, bl
    mov  dl, CELL_WIDTH
    mul  dl
    add  ax, BOARD_LEFT
    mov  si, ax

    ; BP = square top coordinate.
    xor  ax, ax
    mov  al, bh
    mov  dl, CELL_HEIGHT
    mul  dl
    add  ax, BOARD_TOP
    mov  bp, ax

    test byte [BoardPosition + di], 07h
    jnz  .capture_marker

    ; The en-passant destination is empty but still represents a capture.
    mov  al, [SelectedPiece]
    and  al, 07h
    cmp  al, PAWN
    jne  .empty_marker
    mov  ax, di
    cmp  al, [EnPassantSquare]
    je   .capture_marker

.empty_marker:
    ; Empty destination: draw a centered 3x3 XOR dot.
    add  si, 23
    add  bp, 17
    mov  dx, bp
    mov  di, 3

.empty_row:
    mov  cx, si
    call XorPixelBlue
    inc  cx
    call XorPixelBlue
    inc  cx
    call XorPixelBlue
    inc  dx
    dec  di
    jnz  .empty_row
    jmp  .done

.capture_marker:
    ; Occupied opponent destination: four 2x2 blocks. The X positions are
    ; outside the native piece area (piece occupies square X+8..X+39).
    add  si, 5               ; left block X
    mov  di, si
    add  di, 36              ; right block X = square_left+41
    add  bp, 6               ; upper block Y
    mov  dx, bp
    call .draw_capture_pair
    add  dx, 21              ; lower block Y = square_top+27
    call .draw_capture_pair
    jmp  .done

.draw_capture_pair:
    ; Two 2x2 blocks at (SI,DX) and (DI,DX).
    mov  cx, si
    call XorPixelBlue
    inc  cx
    call XorPixelBlue
    mov  cx, di
    call XorPixelBlue
    inc  cx
    call XorPixelBlue

    inc  dx
    mov  cx, si
    call XorPixelBlue
    inc  cx
    call XorPixelBlue
    mov  cx, di
    call XorPixelBlue
    inc  cx
    call XorPixelBlue
    ret

.done:
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; DrawPieceOpaque
;
; Paints one detailed piece without allowing any square texture to show
; through its silhouette:
;
;   destination = (destination AND NOT mask) OR artwork
;
; Input:
;   DS:SI = 192-byte visible artwork
;   DS:DI = 192-byte solid silhouette/opacity mask
;   BL/BH = board column/row, 0..7
;
; Both streams use native six-column by 32-row QX-11 order. The global-Y
; conversion keeps row 5 continuous across Y=199/200.
; ------------------------------------------------------------------
DrawPieceOpaque:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es

    cmp  bl, 7
    ja   .done
    cmp  bh, 7
    ja   .done

    ; Preserve the mask stream before DI becomes the VRAM destination.
    mov  [PieceMaskPointer], di
    mov  di, PIECE_FIRST_X_OFFSET

    ; Add chessboard column * 0C00h.
    xor  cx, cx
    mov  cl, bl
    jcxz .column_position_done

.add_cell_column:
    add  di, PIECE_CELL_X_STEP
    loop .add_cell_column

.column_position_done:
    ; DX = first global display Y for this board row.
    mov  dx, PIECE_FIRST_Y
    xor  cx, cx
    mov  cl, bh
    jcxz .row_position_done

.add_cell_row:
    add  dx, CELL_HEIGHT
    loop .add_cell_row

.row_position_done:
    mov  ax, BOARD_VRAM_SEG
    mov  es, ax

    mov  bp, PIECE_WIDTH_BYTES

.next_bitmap_column:
    push dx
    mov  cx, PIECE_SOURCE_HEIGHT

.next_bitmap_byte:
    lodsb
    mov  ah, al
    mov  bx, [PieceMaskPointer]
    mov  al, [bx]
    inc  bx
    mov  [PieceMaskPointer], bx
    not  al

    mov  bx, dx
    cmp  bx, 200
    jb   .y_ready
    add  bx, 56              ; 0100h + (Y-200) = Y+56
.y_ready:
    and  byte [es:di+bx], al
    or   byte [es:di+bx], ah
    inc  dx
    loop .next_bitmap_byte

    pop  dx
    add  di, 0200h

    dec  bp
    jnz  .next_bitmap_column

.done:
    pop  es
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; RestorePieceBackground
;
; Restores the board underneath one solid piece silhouette without touching
; the selection frame or side markers outside that silhouette:
;
;   destination = (destination AND NOT mask) OR (board_pattern AND mask)
;
; DS:SI = 192-byte solid silhouette mask; BL/BH = square coordinates.
; Light squares use AAh on even global rows and 55h on odd global rows;
; dark-square background is zero. This is the exact DrawChessboard parity.
; ------------------------------------------------------------------
RestorePieceBackground:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es

    cmp  bl, 7
    ja   .done
    cmp  bh, 7
    ja   .done

    mov  al, bl
    add  al, bh
    and  al, 1
    xor  al, 1
    mov  [PieceSquareIsLight], al

    mov  di, PIECE_FIRST_X_OFFSET
    xor  cx, cx
    mov  cl, bl
    jcxz .column_position_done

.add_cell_column:
    add  di, PIECE_CELL_X_STEP
    loop .add_cell_column

.column_position_done:
    mov  dx, PIECE_FIRST_Y
    xor  cx, cx
    mov  cl, bh
    jcxz .row_position_done

.add_cell_row:
    add  dx, CELL_HEIGHT
    loop .add_cell_row

.row_position_done:
    mov  ax, BOARD_VRAM_SEG
    mov  es, ax
    mov  bp, PIECE_WIDTH_BYTES

.next_bitmap_column:
    push dx
    mov  cx, PIECE_SOURCE_HEIGHT

.next_bitmap_byte:
    lodsb
    mov  ah, al              ; AH = original silhouette mask.
    not  al

    mov  bx, dx
    cmp  bx, 200
    jb   .y_ready
    add  bx, 56
.y_ready:
    and  byte [es:di+bx], al

    cmp  byte [PieceSquareIsLight], 0
    je   .background_done
    mov  al, 0AAh
    test dl, 1
    jz   .pattern_ready
    mov  al, 055h
.pattern_ready:
    and  al, ah
    or   byte [es:di+bx], al

.background_done:
    inc  dx
    loop .next_bitmap_byte

    pop  dx
    add  di, 0200h
    dec  bp
    jnz  .next_bitmap_column

.done:
    pop  es
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; PaintPixelBlue
;
; Input:
;   CX = X coordinate, 0..639
;   DX = global Y coordinate, 0..399
;
; Operation:
;   byte_column = X >> 3
;   y_index     = Y when Y<200, otherwise 0100h+(Y-200)
;   address     = 80000h + (byte_column << 9) + y_index
;   bit_mask    = 80h >> (X & 7)
;   VRAM[address] |= bit_mask
;
; Out-of-range coordinates are ignored.
; Preserves all registers.
; ------------------------------------------------------------------
PaintPixelBlue:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp  cx, 639
    ja   .done
    cmp  dx, 399
    ja   .done

    mov  bx, cx
    and  cl, 7
    mov  al, 80h
    shr  al, cl

    mov  di, bx
    shr  di, 1
    shr  di, 1
    shr  di, 1
    mov  cl, 9
    shl  di, cl

    mov  bx, dx
    cmp  bx, 200
    jb   .y_ready
    add  bx, 56              ; 0100h + (Y-200) = Y+56
.y_ready:
    add  di, bx

    ; Both visible halves use the proven stacked column-major 8000h window.
    mov  bx, 8000h
    mov  es, bx
    or   byte [es:di], al

.done:
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; XorPixelBlue
;
; Same verified address calculation as PaintPixelBlue, but XORs the
; pixel. Drawing the same pixel twice restores its previous value.
;
; Input:
;   CX = X coordinate, 0..639
;   DX = global Y coordinate, 0..399
;
; Preserves all registers.
; ------------------------------------------------------------------
XorPixelBlue:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp  cx, 639
    ja   .done
    cmp  dx, 399
    ja   .done

    mov  bx, cx
    and  cl, 7
    mov  al, 80h
    shr  al, cl

    mov  di, bx
    shr  di, 1
    shr  di, 1
    shr  di, 1
    mov  cl, 9
    shl  di, cl

    mov  bx, dx
    cmp  bx, 200
    jb   .y_ready
    add  bx, 56
.y_ready:
    add  di, bx

    ; Cursor, selection, and legal-move pixels share the continuous canvas.
    mov  bx, 8000h
    mov  es, bx
    xor  byte [es:di], al

.done:
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; PaintPixelSmall / XorPixelSmall
;
; Pixel operations used by the compact 5x7 text renderer. The caller selects
; either BOARD_VRAM_SEG or PANEL_VRAM_SEG in SmallDrawSegment. Coordinates are
; local to that 640x200 bank.
;
; Input:
;   CX = X coordinate, 0..639
;   DX = local Y coordinate, 0..199
;
; Preserves all registers.
; ------------------------------------------------------------------
PaintPixelSmall:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp  cx, 639
    ja   .done
    cmp  dx, 199
    ja   .done

    mov  bx, cx
    and  cl, 7
    mov  al, 80h
    shr  al, cl

    mov  di, bx
    shr  di, 1
    shr  di, 1
    shr  di, 1
    mov  cl, 9
    shl  di, cl
    add  di, dx

    mov  bx, [SmallDrawSegment]
    mov  es, bx
    or   byte [es:di], al

.done:
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


XorPixelSmall:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp  cx, 639
    ja   .done
    cmp  dx, 199
    ja   .done

    mov  bx, cx
    and  cl, 7
    mov  al, 80h
    shr  al, cl

    mov  di, bx
    shr  di, 1
    shr  di, 1
    shr  di, 1
    mov  cl, 9
    shl  di, cl
    add  di, dx

    mov  bx, [SmallDrawSegment]
    mov  es, bx
    xor  byte [es:di], al

.done:
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret


; ------------------------------------------------------------------
; Logical starting position
;
; Bits 0..2 = EMPTY/PAWN/KNIGHT/BISHOP/ROOK/QUEEN/KING
; Bit 7     = BLACK side, which selects the solid bitmap.
; ------------------------------------------------------------------
BoardPosition:
    %define INITIAL_CURSOR_COLUMN 4
    %define INITIAL_CURSOR_ROW    6
    %define INITIAL_TURN          0

    db BLACK+ROOK, BLACK+KNIGHT, BLACK+BISHOP, BLACK+QUEEN
    db BLACK+KING, BLACK+BISHOP, BLACK+KNIGHT, BLACK+ROOK

    db BLACK+PAWN, BLACK+PAWN, BLACK+PAWN, BLACK+PAWN
    db BLACK+PAWN, BLACK+PAWN, BLACK+PAWN, BLACK+PAWN

    times 32 db EMPTY

    db PAWN, PAWN, PAWN, PAWN, PAWN, PAWN, PAWN, PAWN
    db ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK

InitialBoardPosition:
    db BLACK+ROOK, BLACK+KNIGHT, BLACK+BISHOP, BLACK+QUEEN
    db BLACK+KING, BLACK+BISHOP, BLACK+KNIGHT, BLACK+ROOK
    db BLACK+PAWN, BLACK+PAWN, BLACK+PAWN, BLACK+PAWN
    db BLACK+PAWN, BLACK+PAWN, BLACK+PAWN, BLACK+PAWN
    times 32 db EMPTY
    db PAWN, PAWN, PAWN, PAWN, PAWN, PAWN, PAWN, PAWN
    db ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK


; Embedded build identity.
BuildSignature:
    db 'QXCHESS-COMPUTER-PHASE6-MENU-HINT-20260731',0

; Interactive selection state.
CursorColumn:
    db INITIAL_CURSOR_COLUMN
CursorRow:
    db INITIAL_CURSOR_ROW
SelectionState:
    db SELECT_SOURCE
CurrentTurn:
    db INITIAL_TURN         ; 00h = White, 80h = Black.
CheckIndicatorVisible:
    db 0                    ; 0 = CHECK absent, 1 = CHECK drawn in VRAM.
GameState:
    db GAME_PLAYING         ; Playing, checkmate, or stalemate.
PositionInCheck:
    db 0                    ; Scratch result used by EvaluateGameState.
SourceColumn:
    db 0
SourceRow:
    db 0
SelectedPiece:
    db EMPTY
CapturedPiece:
    db EMPTY
DestinationIndex:
    dw 0

; Phase-3 computer-turn state. The saved cursor remains the human's visible
; selection location while the computer uses CursorColumn/CursorRow internally
; as the destination coordinates required by the common move executor.
ComputerMoveActive:
    db 0
SavedHumanCursorColumn:
    db INITIAL_CURSOR_COLUMN
SavedHumanCursorRow:
    db INITIAL_CURSOR_ROW
ComputerSourceIndex:
    db 0
ComputerDestinationIndex:
    db 0
ComputerBestMoveFound:
    db 0
ComputerBestScore:
    dw 0
ComputerRootNodes:
    dw 0
ComputerReplyNodes:
    dw 0
ComputerAlphaCutoffs:
    dw 0
ComputerThirdPlyNodes:
    dw 0
ComputerPhase4Cutoffs:
    dw 0
ComputerQuiescenceLeaves:
    dw 0
ComputerRepetitionPenalties:
    dw 0
ComputerCompletedDepth:
    db 0
ComputerSearchTimedOut:
    db 0
ComputerThinkSecondsElapsed:
    db 0
ComputerThinkBlinkPending:
    db 0
ComputerThinkingVisible:
    db 0

; Phase-6 modal menu, pause, and human-hint state.
ClockPaused:
    db 0
GamePaused:
    db 0
PausedTextVisible:
    db 0
MenuSelection:
    db 0
HintActive:
    db 0
HintVisible:
    db 0
HintTextVisible:
    db 0
HintCursorHidden:
    db 0
HintBlinkPending:
    db 0
HintSearchSucceeded:
    db 0
HintBestMoveFound:
    db 0
HintSourceIndex:
    db 0
HintDestinationIndex:
    db 0
HintBestScore:
    dw 0
HintWorstScore:
    dw 0
HintRootNodes:
    dw 0
HintReplyNodes:
    dw 0
HintReplyFound:
    db 0
HintSavedSourceColumn:
    db 0
HintSavedSourceRow:
    db 0
HintSavedSelectedPiece:
    db EMPTY
HintSavedTurn:
    db 0
HintSavedCastlingRights:
    db CASTLE_ALL_RIGHTS
HintSavedEnPassantSquare:
    db NO_EN_PASSANT
HintRootSourceColumn:
    db 0
HintRootSourceRow:
    db 0
HintRootSelectedPiece:
    db EMPTY
HintBoardBackup:
    times 64 db EMPTY
MenuBackgroundBuffer:
    times MENU_SAVE_COLUMNS * MENU_SAVE_HEIGHT db 0

; Immediate material values indexed by piece type 0..6.
PieceMaterialValues:
    dw 0, 100, 320, 330, 500, 900, 0

; Compact signed piece-square values from White's a8..h1 orientation. Black
; mirrors the row with index XOR 56. Values remain deliberately much smaller
; than a pawn so positional preferences never conceal a sound material result.
PieceSquareTablePointers:
    dw EmptyPositionTable, PawnPositionTable, KnightPositionTable
    dw BishopPositionTable, RookPositionTable, QueenPositionTable
    dw KingPositionTable

EmptyPositionTable:
    times 64 db 0
PawnPositionTable:
    db  0, 0, 0, 0, 0, 0, 0, 0
    db 40,42,44,46,46,44,42,40
    db 24,26,30,34,34,30,26,24
    db 14,16,20,26,26,20,16,14
    db  8,10,14,22,22,14,10, 8
    db  4, 6,10,16,16,10, 6, 4
    db  0, 0, 0,-4,-4, 0, 0, 0
    db  0, 0, 0, 0, 0, 0, 0, 0
KnightPositionTable:
    db -30,-20,-12,-10,-10,-12,-20,-30
    db -20, -4,  4,  8,  8,  4, -4,-20
    db -12,  4, 12, 16, 16, 12,  4,-12
    db -10,  8, 16, 22, 22, 16,  8,-10
    db -10,  8, 16, 22, 22, 16,  8,-10
    db -12,  4, 12, 16, 16, 12,  4,-12
    db -20, -4,  4,  8,  8,  4, -4,-20
    db -30,-20,-12,-10,-10,-12,-20,-30
BishopPositionTable:
    db -14,-10,-8,-8,-8,-8,-10,-14
    db -10,  4, 4, 6, 6, 4,  4,-10
    db  -8,  4, 8,10,10, 8,  4, -8
    db  -8,  6,10,14,14,10,  6, -8
    db  -8,  6,10,14,14,10,  6, -8
    db  -8,  4, 8,10,10, 8,  4, -8
    db -10,  4, 4, 6, 6, 4,  4,-10
    db -14,-10,-8,-8,-8,-8,-10,-14
RookPositionTable:
    db  0, 2, 4, 6, 6, 4, 2, 0
    db 12,14,16,18,18,16,14,12
    db -2, 0, 2, 4, 4, 2, 0,-2
    db -2, 0, 2, 4, 4, 2, 0,-2
    db -2, 0, 2, 4, 4, 2, 0,-2
    db -2, 0, 2, 4, 4, 2, 0,-2
    db -2, 0, 2, 4, 4, 2, 0,-2
    db  0, 0, 0, 2, 2, 0, 0, 0
QueenPositionTable:
    db -8,-6,-4,-2,-2,-4,-6,-8
    db -6, 0, 2, 2, 2, 2, 0,-6
    db -4, 2, 4, 6, 6, 4, 2,-4
    db -2, 2, 6, 8, 8, 6, 2,-2
    db -2, 2, 6, 8, 8, 6, 2,-2
    db -4, 2, 4, 6, 6, 4, 2,-4
    db -6, 0, 2, 2, 2, 2, 0,-6
    db -8,-6,-4,-2,-2,-4,-6,-8
KingPositionTable:
    db -30,-30,-30,-30,-30,-30,-30,-30
    db -30,-30,-30,-30,-30,-30,-30,-30
    db -30,-30,-30,-30,-30,-30,-30,-30
    db -32,-32,-34,-36,-36,-34,-32,-32
    db -34,-34,-36,-40,-40,-36,-34,-34
    db -20,-20,-24,-30,-30,-24,-20,-20
    db  10, 12,  4,  0,  0,  4, 12, 10
    db  18, 26, 20,  0,  0, 12, 28, 20

; Two-ply search state. SearchBoardBackup makes every speculative Black move
; exactly reversible without invoking graphics, history, clocks, or sounds.
SearchBoardBackup:
    times 64 db EMPTY
SearchRootSourceIndex:
    dw 0
SearchRootDestinationIndex:
    db 0
SearchRootSourceColumn:
    db 0
SearchRootSourceRow:
    db 0
SearchRootDestinationColumn:
    db 0
SearchRootDestinationRow:
    db 0
SearchRootSelectedPiece:
    db EMPTY
SearchRootCapturedPiece:
    db EMPTY
SearchRootMoveFlags:
    db 0
SearchRootCastleSourceColumn:
    db 0
SearchRootCastleDestinationColumn:
    db 0
SearchRootGain:
    dw 0
SearchRootPenalty:
    dw 0
SearchBestWhiteGain:
    dw 0
SearchCandidateScore:
    dw 0
SearchReplyFound:
    db 0
SearchSavedCurrentTurn:
    db 0
SearchSavedCastlingRights:
    db 0
SearchSavedEnPassantSquare:
    db NO_EN_PASSANT
SearchServiceSavedTurn:
    db 0

; Phase-4 iterative-search state. Three independent 64-byte snapshots cover
; the pre-root position, the post-root position, and short move-order/mate
; probes. The completed Phase-3 move stays in Computer* until depth three has
; completed successfully.
Phase4BestMoveFound:
    db 0
Phase4BestScore:
    dw 0
Phase4BestSourceIndex:
    db 0
Phase4BestDestinationIndex:
    db 0
SearchRootOrderPass:
    db 0
SearchWhiteOrderPass:
    db 0
SearchBlackOrderPass:
    db 0
SearchBestWhiteScore:
    dw 0
SearchCurrentReplyScore:
    dw 0
SearchWhiteGain:
    dw 0
SearchBestBlackGain:
    dw 0
SearchContinuationGain:
    dw 0
SearchBlackContinuationFound:
    db 0
SearchWhiteSourceColumn:
    db 0
SearchWhiteSourceRow:
    db 0
SearchWhiteSelectedPiece:
    db 0
SearchPlySavedCastlingRights:
    db 0
SearchPlySavedEnPassantSquare:
    db NO_EN_PASSANT
SearchOrderSavedCurrentTurn:
    db 0
SearchOrderSavedCastlingRights:
    db 0
SearchOrderSavedEnPassantSquare:
    db NO_EN_PASSANT
SearchMoveGivesCheck:
    db 0
SearchMoveIsMate:
    db 0
SearchPlyBoardBackup:
    times 64 db EMPTY
SearchOrderBoardBackup:
    times 64 db EMPTY

; Phase-5 positional probes and bounded two-ply capture quiescence snapshots.
PositionProbeBoardBackup:
    times 64 db EMPTY
PositionProbeSavedTurn:
    db 0
PositionProbeSavedCastlingRights:
    db 0
PositionProbeSavedEnPassantSquare:
    db NO_EN_PASSANT
PositionProbeScore:
    dw 0

QuiescenceBaseBoardBackup:
    times 64 db EMPTY
QuiescenceBaseSavedTurn:
    db 0
QuiescenceBaseSavedCastlingRights:
    db 0
QuiescenceBaseSavedEnPassantSquare:
    db NO_EN_PASSANT
QuiescenceWhiteBoardBackup:
    times 64 db EMPTY
QuiescenceWhiteSavedCastlingRights:
    db 0
QuiescenceWhiteSavedEnPassantSquare:
    db NO_EN_PASSANT
QuiescenceWhiteSourceColumn:
    db 0
QuiescenceWhiteSourceRow:
    db 0
QuiescenceWhiteSelectedPiece:
    db EMPTY
QuiescenceBlackBoardBackup:
    times 64 db EMPTY
QuiescenceBlackSavedCastlingRights:
    db 0
QuiescenceBlackSavedEnPassantSquare:
    db NO_EN_PASSANT
QuiescenceBlackSourceColumn:
    db 0
QuiescenceBlackSourceRow:
    db 0
QuiescenceBlackSelectedPiece:
    db EMPTY
QuiescenceBestWhiteScore:
    dw 0
QuiescenceBestBlackScore:
    dw 0

; Persistent special-rule state. A castling bit, once cleared, is never
; restored. EnPassantSquare is valid for the immediately following half-move.
CastlingRights:
    db CASTLE_ALL_RIGHTS
EnPassantSquare:
    db NO_EN_PASSANT

; Classification/state frozen by the final ValidateMove before commit.
PendingMoveFlags:
    db 0
CommittedMoveFlags:
    db 0
PreviousCastlingRights:
    db CASTLE_ALL_RIGHTS
PreviousEnPassantSquare:
    db NO_EN_PASSANT
PromotionPiece:
    db EMPTY
SpecialCaptureColumn:
    db 0
SpecialCaptureRow:
    db 0
CastleRookSourceColumn:
    db 0
CastleRookDestinationColumn:
    db 0
CastleTransitColumn:
    db 0
CastleTransitAttacked:
    db 0
CastleRookPiece:
    db EMPTY

; One bit per destination square. MoveMask[row] bit column is set when
; ValidateMove accepts that source/destination pair.
MoveMask:
    times 8 db 0

; ValidateMove and PathIsClear scratch state.
CandidateColumn:
    db 0
CandidateRow:
    db 0
DestinationPiece:
    db EMPTY
MoveDeltaX:
    db 0
MoveDeltaY:
    db 0
MoveStepX:
    db 0
MoveStepY:
    db 0
PathColumn:
    db 0
PathRow:
    db 0

; Temporary make/check/undo state used by IsMoveKingSafe.
SafetySourceIndex:
    dw 0
SafetyDestinationIndex:
    dw 0
SafetySourcePiece:
    db EMPTY
SafetyDestinationPiece:
    db EMPTY
KingSafetyResult:
    db 0
SafetySpecialApplied:
    db 0
SafetySpecialSourceIndex:
    dw 0
SafetySpecialDestinationIndex:
    dw 0
SafetySpecialSourcePiece:
    db EMPTY
SafetySpecialDestinationPiece:
    db EMPTY

; HasAnyLegalMove preserves the interactive source selection while it scans.
SavedSourceColumn:
    db 0
SavedSourceRow:
    db 0
SavedSelectedPiece:
    db EMPTY
AnyLegalMoveResult:
    db 0

; Attack-detection scratch state. IsSquareAttacked scans every piece belonging
; to the opponent of the side supplied by IsMoveKingSafe.
AttackTargetColumn:
    db 0
AttackTargetRow:
    db 0
AttackSide:
    db 0
AttackCandidatePiece:
    db 0
AttackOriginColumn:
    db 0
AttackOriginRow:
    db 0
AttackDeltaX:
    db 0
AttackDeltaY:
    db 0
AttackStepX:
    db 0
AttackStepY:
    db 0
AttackPathColumn:
    db 0
AttackPathRow:
    db 0


; Persistent move tracking. Records are written as a circular buffer so a
; game can continue beyond 256 half-moves without overrunning memory.
HistoryNext:
    db 0
HistoryCount:
    dw 0
MoveHistory:
    times MOVE_HISTORY_CAPACITY * MOVE_HISTORY_RECORD_SIZE db 0

; Recent-move rendering scratch state.
MoveDisplayLineCount:
    db 0
MoveDisplayLineNumber:
    db 0
MoveDisplayRecordIndex:
    db 0
MoveLineText:
    db 'W A2-A4 ',0

; Independent chess-clock states. Both players begin with ten minutes. Later
; the RTC periodic interrupt will decrement only the triplet selected by
; CurrentTurn.
WhiteClockHour:
    db 0
WhiteClockMinute:
    db 10
WhiteClockSecond:
    db 0
BlackClockHour:
    db 0
BlackClockMinute:
    db 10
BlackClockSecond:
    db 0

; RTC installation state and ISR/foreground handoff. INT 7Ah owns only the
; subsecond and pending counters; foreground code owns all renderer scratch.
RTCInstalled:
    db 0
SavedRTCRegisterA:
    db 0
SavedRTCRegisterB:
    db 0
RTCSubsecondTicks:
    db 0
WhiteSecondsPending:
    db 0
BlackSecondsPending:
    db 0
WhiteFlagSoundPlayed:
    db 0
BlackFlagSoundPlayed:
    db 0
TimeWinner:
    db 0                    ; 00h = White, 80h = Black.
ClockApplyCount:
    db 0
ClockBlackApplyCount:
    db 0
OldInt7AOffset:
    dw 0
OldInt7ASegment:
    dw 0

; Midpoint-circle and Bresenham-line scratch storage.
ClockCenterX:
    dw 0
ClockCenterY:
    dw 0
ClockCircleX:
    dw 0
ClockCircleY:
    dw 0
ClockCircleError:
    dw 0
ClockLineMode:
    db SMALL_DRAW_PAINT
ClockLineX0:
    dw 0
ClockLineY0:
    dw 0
ClockLineX1:
    dw 0
ClockLineY1:
    dw 0
ClockLineDeltaX:
    dw 0
ClockLineDeltaY:
    dw 0
ClockLineStepX:
    dw 0
ClockLineStepY:
    dw 0
ClockLineError:
    dw 0
ClockLineDoubleError:
    dw 0
ClockRectLeft:
    dw 0
ClockRectTop:
    dw 0
ClockRectRight:
    dw 0
ClockRectBottom:
    dw 0
GlobalRectLeftScratch:
    dw 0

SmallDrawMode:
    db SMALL_DRAW_PAINT
SmallDrawSegment:
    dw BOARD_VRAM_SEG
PieceSquareIsLight:
    db 0
PieceMaskPointer:
    dw 0
LastMovesTitle:
    db 'LAST MOVES',0
PromoteTitle:
    db 'PROMOTE',0
PromoteChoices:
    db 'Q R B N',0
WhiteTurnText:
    db 'WHITE TURN',0
BlackTurnText:
    db 'BLACK TURN',0
ComputerThinkingText:
    db 'COMPUTER THINKING',0
EscapeMenuTitle:
    db 'GAME MENU',0
MenuPauseText:
    db 'PAUSE',0
MenuRestartText:
    db 'RESTART',0
MenuQuitText:
    db 'QUIT',0
GamePausedText:
    db 'PAUSED',0
FindingHintText:
    db 'FINDING HINT',0
HintMoveText:
    db 'HINT A1 TO A1',0
WhiteWinsText:
    db 'WHITE WINS',0
BlackWinsText:
    db 'BLACK WINS',0
WhiteClockLabel:
    db 'WHITE',0
BlackClockLabel:
    db 'BLACK',0
UpperTitleLine1:
    db 'QX-11',0
UpperTitleLine2:
    db 'CHESS',0
UpperControlLine1:
    db 'ARROWS',0
UpperControlLine2:
    db 'MOVE',0
UpperControlLine3:
    db 'ENTER',0
UpperControlLine4:
    db 'SELECT',0
UpperControlLine5:
    db 'H HINT',0
SplashTitleText:
    db 'QX-11 CHESS',0
SplashCreditText:
    db 'CREATED BY SAN',0
SplashPhaseText:
    db 'PHASE 6 II',0
SplashPressKeyText:
    db 'PRESS ANY KEY',0
Phase6IISignature:
    db 'QX11 CHESS PHASE 6 II R3',0


; ------------------------------------------------------------------
; Compact 5x7 font
;
; Each glyph is five vertical columns. Bit 0 is the top pixel and bit 6
; is the bottom pixel. Unsupported letters point to the blank glyph.
; ------------------------------------------------------------------
SmallDigitTable:
    dw SmallGlyph0, SmallGlyph1, SmallGlyph2, SmallGlyph3, SmallGlyph4
    dw SmallGlyph5, SmallGlyph6, SmallGlyph7, SmallGlyph8, SmallGlyph9

SmallLetterTable:
    dw SmallGlyphA, SmallGlyphB, SmallGlyphC, SmallGlyphD, SmallGlyphE
    dw SmallGlyphF, SmallGlyphG, SmallGlyphH, SmallGlyphI, SmallGlyphSpace
    dw SmallGlyphK, SmallGlyphL, SmallGlyphM, SmallGlyphN, SmallGlyphO
    dw SmallGlyphP, SmallGlyphQ, SmallGlyphR, SmallGlyphS
    dw SmallGlyphT, SmallGlyphU, SmallGlyphV, SmallGlyphW
    dw SmallGlyphX, SmallGlyphY, SmallGlyphZ

SmallGlyphSpace:
    db 00h,00h,00h,00h,00h
SmallGlyphHyphen:
    db 08h,08h,08h,08h,08h

SmallGlyph0:
    db 3Eh,51h,49h,45h,3Eh
SmallGlyph1:
    db 00h,42h,7Fh,40h,00h
SmallGlyph2:
    db 42h,61h,51h,49h,46h
SmallGlyph3:
    db 21h,41h,45h,4Bh,31h
SmallGlyph4:
    db 18h,14h,12h,7Fh,10h
SmallGlyph5:
    db 27h,45h,45h,45h,39h
SmallGlyph6:
    db 3Ch,4Ah,49h,49h,30h
SmallGlyph7:
    db 01h,71h,09h,05h,03h
SmallGlyph8:
    db 36h,49h,49h,49h,36h
SmallGlyph9:
    db 06h,49h,49h,29h,1Eh

SmallGlyphA:
    db 7Eh,11h,11h,11h,7Eh
SmallGlyphB:
    db 7Fh,49h,49h,49h,36h
SmallGlyphC:
    db 3Eh,41h,41h,41h,22h
SmallGlyphD:
    db 7Fh,41h,41h,22h,1Ch
SmallGlyphE:
    db 7Fh,49h,49h,49h,41h
SmallGlyphF:
    db 7Fh,09h,09h,09h,01h
SmallGlyphG:
    db 3Eh,41h,49h,49h,7Ah
SmallGlyphH:
    db 7Fh,08h,08h,08h,7Fh
SmallGlyphI:
    db 00h,41h,7Fh,41h,00h
SmallGlyphK:
    db 7Fh,08h,14h,22h,41h
SmallGlyphL:
    db 7Fh,40h,40h,40h,40h
SmallGlyphM:
    db 7Fh,02h,0Ch,02h,7Fh
SmallGlyphN:
    db 7Fh,02h,04h,08h,7Fh
SmallGlyphO:
    db 3Eh,41h,41h,41h,3Eh
SmallGlyphP:
    db 7Fh,09h,09h,09h,06h
SmallGlyphQ:
    db 3Eh,41h,51h,21h,5Eh
SmallGlyphR:
    db 7Fh,09h,19h,29h,46h
SmallGlyphS:
    db 46h,49h,49h,49h,31h
SmallGlyphT:
    db 01h,01h,7Fh,01h,01h
SmallGlyphU:
    db 3Fh,40h,40h,40h,3Fh
SmallGlyphV:
    db 1Fh,20h,40h,20h,1Fh
SmallGlyphW:
    db 3Fh,40h,38h,40h,3Fh
SmallGlyphX:
    db 63h,14h,08h,14h,63h
SmallGlyphY:
    db 07h,08h,70h,08h,07h
SmallGlyphZ:
    db 61h,51h,49h,45h,43h


; Twelve radial marks: inner X/Y and outer X/Y relative to the clock center.
ClockTickTable:
    dw 0,-44,0,-52
    dw 22,-38,26,-45
    dw 38,-22,45,-26
    dw 44,0,52,0
    dw 38,22,45,26
    dw 22,38,26,45
    dw 0,44,0,52
    dw -22,38,-26,45
    dw -38,22,-45,26
    dw -44,0,-52,0
    dw -38,-22,-45,-26
    dw -22,-38,-26,-45

; Sixty signed X/Y endpoints per hand, starting at 12 o'clock and moving
; clockwise. Keeping the geometry in tables makes a future RTC refresh fast
; and avoids multiplication or trigonometry in the interrupt-driven path.
ClockHourHandTable:
    dw 0,-38, 4,-38, 8,-37, 12,-36, 15,-35
    dw 19,-33, 22,-31, 25,-28, 28,-25, 31,-22
    dw 33,-19, 35,-15, 36,-12, 37,-8, 38,-4
    dw 38,0, 38,4, 37,8, 36,12, 35,15
    dw 33,19, 31,22, 28,25, 25,28, 22,31
    dw 19,33, 15,35, 12,36, 8,37, 4,38
    dw 0,38, -4,38, -8,37, -12,36, -15,35
    dw -19,33, -22,31, -25,28, -28,25, -31,22
    dw -33,19, -35,15, -36,12, -37,8, -38,4
    dw -38,0, -38,-4, -37,-8, -36,-12, -35,-15
    dw -33,-19, -31,-22, -28,-25, -25,-28, -22,-31
    dw -19,-33, -15,-35, -12,-36, -8,-37, -4,-38

ClockMinuteHandTable:
    dw 0,-54, 6,-54, 11,-53, 17,-51, 22,-49
    dw 27,-47, 32,-44, 36,-40, 40,-36, 44,-32
    dw 47,-27, 49,-22, 51,-17, 53,-11, 54,-6
    dw 54,0, 54,6, 53,11, 51,17, 49,22
    dw 47,27, 44,32, 40,36, 36,40, 32,44
    dw 27,47, 22,49, 17,51, 11,53, 6,54
    dw 0,54, -6,54, -11,53, -17,51, -22,49
    dw -27,47, -32,44, -36,40, -40,36, -44,32
    dw -47,27, -49,22, -51,17, -53,11, -54,6
    dw -54,0, -54,-6, -53,-11, -51,-17, -49,-22
    dw -47,-27, -44,-32, -40,-36, -36,-40, -32,-44
    dw -27,-47, -22,-49, -17,-51, -11,-53, -6,-54

ClockSecondHandTable:
    dw 0,-49, 5,-49, 10,-48, 15,-47, 20,-45
    dw 24,-42, 29,-40, 33,-36, 36,-33, 40,-29
    dw 42,-25, 45,-20, 47,-15, 48,-10, 49,-5
    dw 49,0, 49,5, 48,10, 47,15, 45,20
    dw 42,24, 40,29, 36,33, 33,36, 29,40
    dw 24,42, 20,45, 15,47, 10,48, 5,49
    dw 0,49, -5,49, -10,48, -15,47, -20,45
    dw -24,42, -29,40, -33,36, -36,33, -40,29
    dw -42,25, -45,20, -47,15, -48,10, -49,5
    dw -49,0, -49,-5, -48,-10, -47,-15, -45,-20
    dw -42,-25, -40,-29, -36,-33, -33,-36, -29,-40
    dw -24,-42, -20,-45, -15,-47, -10,-48, -5,-49

; Native 32x8 CHECK label, stored in QX-11 column-major byte order.
; Each group of eight bytes is one 8-pixel-wide vertical column.
CheckBitmap:
    db 72h,8Ah,82h,83h,82h,8Ah,72h,00h
    db 2Fh,28h,28h,0EFh,28h,28h,2Fh,00h
    db 9Ch,22h,20h,20h,20h,22h,9Ch,00h
    db 88h,90h,0A0h,0C0h,0A0h,90h,88h,00h

; Native 56x8 terminal labels.
CheckmateBitmap:
    db 72h,8Ah,82h,83h,82h,8Ah,72h,00h
    db 2Fh,28h,28h,0EFh,28h,28h,2Fh,00h
    db 9Ch,22h,20h,20h,20h,22h,9Ch,00h
    db 8Ah,93h,0A2h,0C2h,0A2h,92h,8Ah,00h
    db 27h,68h,0A8h,0AFh,28h,28h,28h,00h
    db 3Eh,88h,88h,88h,88h,88h,88h,00h
    db 0F8h,80h,80h,0F0h,80h,80h,0F8h,00h

StalemateBitmap:
    db 7Bh,80h,80h,70h,08h,08h,0F0h,00h
    db 0E7h,88h,88h,8Fh,88h,88h,88h,00h
    db 20h,0A0h,0A0h,0A0h,0A0h,0A0h,0BEh,00h
    db 0FAh,83h,82h,0F2h,82h,82h,0FAh,00h
    db 27h,68h,0A8h,0AFh,28h,28h,28h,00h
    db 3Eh,88h,88h,88h,88h,88h,88h,00h
    db 0F8h,80h,80h,0F0h,80h,80h,0F8h,00h


SolidPieceTable:
    dw PawnSolid
    dw KnightSolid
    dw BishopSolid
    dw RookSolid
    dw QueenSolid
    dw KingSolid

OutlinePieceTable:
    dw PawnOutline
    dw KnightOutline
    dw BishopOutline
    dw RookOutline
    dw QueenOutline
    dw KingOutline


; ------------------------------------------------------------------
; Native detailed 48x32 piece bitmaps
;
; Each bitmap contains six groups of 32 bytes. Each group is one vertical
; 8-pixel VRAM column in exactly the order DrawPieceOpaque needs. The visible
; 40-pixel artwork is centered by four blank pixels at each horizontal edge.
; ------------------------------------------------------------------

PawnSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,01h,01h,03h,03h,03h,03h,00h,0Fh,1Fh,30h,7Fh,00h
    db 00h,03h,0Fh,1Fh,3Fh,3Fh,3Fh,3Fh,3Fh,1Fh,1Fh,1Fh,3Fh,3Fh,3Fh,7Fh
    db 7Fh,7Fh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,00h,0FFh,00h
    db 00h,0C0h,0F0h,0F8h,0FCh,0FCh,0FCh,0FCh,0FCh,0F8h,0F8h,0F8h,0FCh,0FCh,0FCh,0FEh
    db 0FEh,0FEh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,80h,80h,0C0h,0C0h,0C0h,0C0h,00h,0F0h,0F8h,0Ch,0FEh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

KnightSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,01h,01h,03h,23h,1Bh,0Eh,05h,01h,00h,00h,00h,07h,0Eh,1Eh
    db 1Dh,3Eh,7Fh,1Fh,04h,00h,00h,00h,00h,00h,07h,0Fh,10h,1Fh,3Fh,00h
    db 00h,00h,00h,0E0h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,7Fh,0FFh,0FFh,7Fh,0FFh,0FFh
    db 0FEh,7Eh,0BCh,7Ch,7Ch,7Ch,0F8h,0F8h,0FFh,00h,0FFh,0FFh,00h,0FFh,0FFh,00h
    db 10h,38h,38h,7Ch,0FCh,0FEh,0FFh,0FFh,0FBh,0F1h,0FBh,0FFh,0FFh,0FFh,0F8h,3Fh
    db 3Fh,1Fh,03h,00h,00h,00h,00h,00h,0E0h,00h,0FFh,0FFh,00h,0FFh,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,80h,0E0h,0F0h,0F0h,0F8h,0F8h,0FCh,0FCh,08h
    db 0D8h,0F8h,0E0h,80h,00h,00h,00h,00h,00h,40h,0E0h,0E0h,00h,0F8h,0FCh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

BishopSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,01h,01h,03h,03h,07h,1Ch,1Fh,1Fh,1Fh,00h
    db 00h,01h,03h,0Fh,1Fh,3Fh,3Fh,7Fh,7Fh,0FEh,0FCh,0F8h,79h,71h,3Bh,3Fh
    db 1Fh,0Fh,3Fh,3Fh,3Fh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 80h,0C0h,0E0h,0E0h,0C0h,0CCh,8Ch,1Eh,3Eh,7Fh,7Fh,0FFh,0FEh,0FEh,0FCh,0FCh
    db 0F8h,0F0h,0FCh,0FCh,0FCh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,80h,80h,0C0h,0C0h,0E0h,38h,0F8h,0F8h,0F8h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

RookSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,3Ch,3Ch,3Ch,3Ch,3Fh,3Fh,3Fh,3Fh,1Fh,1Fh,03h,02h,03h,03h
    db 03h,01h,01h,01h,01h,01h,01h,01h,03h,1Fh,1Fh,10h,1Fh,0FFh,0FFh,00h
    db 00h,00h,78h,78h,78h,78h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh
    db 0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,00h,0F1h,0F1h,0F1h,0F1h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh
    db 0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,00h,0FCh,0FCh,0FCh,0FCh,0FCh,0FCh,0FCh,0FCh,0F8h,0F8h,0C0h,40h,0C0h,0C0h
    db 0C0h,80h,80h,80h,80h,80h,80h,80h,0C0h,0F8h,0F8h,08h,0F8h,0FFh,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

QueenSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,01h,71h,0F9h,0F8h,0F8h,70h,30h,18h,1Ch,1Eh,1Fh,1Fh,1Fh,0Fh
    db 0Fh,08h,0Fh,01h,00h,01h,00h,00h,00h,01h,07h,38h,3Fh,3Fh,3Fh,00h
    db 00h,0E0h,0F0h,0F0h,0F1h,0E3h,33h,73h,79h,7Ch,0FCh,0FEh,0FFh,0BFh,1Eh,0BFh
    db 0FFh,00h,0FFh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,03h,07h,07h,0C7h,0E3h,0E6h,0E7h,0CFh,1Fh,1Fh,3Fh,7Fh,7Eh,3Ch,7Eh
    db 0FFh,00h,0FFh,0FFh,00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,80h,0C0h,0C7h,0CFh,8Fh,0Fh,07h,04h,0Ch,9Ch,0BCh,0F8h,0F8h,78h,0F8h
    db 0F0h,10h,0F0h,80h,00h,80h,00h,00h,00h,80h,0E0h,1Ch,0FCh,0FCh,0FCh,00h
    db 00h,00h,00h,00h,80h,80h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

KingSolid:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,03h,03h,07h,0Fh,07h
    db 07h,03h,03h,01h,00h,00h,00h,00h,00h,01h,03h,38h,3Fh,3Fh,3Fh,00h
    db 07h,07h,07h,7Fh,7Fh,7Fh,7Fh,7Fh,07h,0FFh,0FFh,80h,0FFh,0FFh,80h,0C0h
    db 0E0h,0F1h,0FBh,0FFh,7Fh,00h,7Fh,7Fh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 0E0h,0E0h,0E0h,0FEh,0FEh,0FEh,0FEh,0FEh,0E0h,0FFh,0FFh,01h,0FFh,0FFh,00h,01h
    db 83h,0C7h,0EFh,0FFh,0FEh,00h,0FEh,0FEh,0FFh,0FFh,0FFh,00h,0FFh,0FFh,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,0C0h,0C0h,0E0h,0F0h,0E0h
    db 0E0h,0C0h,0C0h,80h,00h,00h,00h,00h,00h,80h,0C0h,1Ch,0FCh,0FCh,0FCh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

PawnOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,01h,01h,02h,02h,02h,03h,00h,0Fh,1Fh,30h,7Fh,00h
    db 00h,03h,0Ch,10h,20h,20h,20h,20h,20h,10h,10h,10h,20h,20h,20h,40h
    db 40h,40h,80h,80h,00h,00h,00h,00h,00h,0FFh,00h,0FFh,0FFh,00h,0FFh,00h
    db 00h,0C0h,30h,08h,04h,04h,04h,04h,04h,08h,08h,08h,04h,04h,04h,02h
    db 02h,02h,01h,01h,00h,00h,00h,00h,00h,0FFh,00h,0FFh,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,80h,80h,40h,40h,40h,0C0h,00h,0F0h,0F8h,0Ch,0FEh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

KnightOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,01h,01h,02h,22h,1Bh,0Eh,05h,01h,00h,00h,00h,07h,0Ah,12h
    db 15h,22h,61h,1Bh,04h,00h,00h,00h,00h,00h,07h,0Fh,10h,1Fh,3Fh,00h
    db 00h,00h,00h,0E0h,1Fh,00h,00h,80h,00h,80h,40h,80h,80h,40h,80h,81h
    db 82h,42h,0A4h,44h,44h,44h,88h,88h,0FFh,00h,0FFh,0FFh,00h,0FFh,0FFh,00h
    db 10h,28h,28h,44h,84h,02h,01h,04h,0Ah,11h,0Ah,04h,00h,07h,0C8h,27h
    db 20h,1Ch,03h,00h,00h,00h,00h,00h,0E0h,00h,0FFh,0FFh,00h,0FFh,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,80h,60h,10h,10h,08h,08h,04h,0F4h,08h
    db 0D8h,38h,60h,80h,00h,00h,00h,00h,00h,40h,0A0h,0E0h,00h,0F8h,0FCh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

BishopOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,01h,01h,02h,02h,07h,1Ch,13h,10h,1Fh,00h
    db 00h,01h,02h,0Ch,10h,20h,20h,41h,41h,82h,84h,88h,49h,51h,2Ah,24h
    db 10h,08h,30h,20h,20h,0FFh,00h,0FFh,00h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 80h,40h,20h,20h,40h,4Ch,8Ch,12h,22h,41h,41h,81h,02h,02h,04h,04h
    db 08h,10h,0Ch,04h,04h,0FFh,00h,0FFh,00h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,80h,80h,40h,40h,0E0h,38h,0C8h,08h,0F8h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

RookOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,3Ch,24h,24h,24h,23h,20h,20h,20h,10h,1Ch,03h,02h,03h,02h
    db 02h,01h,01h,01h,01h,01h,01h,01h,02h,1Ch,1Fh,10h,1Fh,0E0h,0FFh,00h
    db 00h,00h,78h,48h,48h,48h,87h,00h,00h,00h,00h,00h,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,0FFh,00h,0FFh,00h,00h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,00h,0F1h,91h,91h,91h,0Eh,00h,00h,00h,00h,00h,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,0FFh,00h,0FFh,00h,00h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,00h,0FCh,04h,04h,04h,04h,04h,04h,04h,08h,38h,0C0h,40h,0C0h,40h
    db 40h,80h,80h,80h,80h,80h,80h,80h,40h,38h,0F8h,08h,0F8h,07h,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

QueenOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,01h,71h,89h,88h,88h,50h,30h,18h,14h,12h,11h,10h,11h,08h
    db 0Fh,08h,0Fh,01h,00h,01h,00h,00h,00h,01h,07h,38h,27h,20h,3Fh,00h
    db 00h,0E0h,10h,10h,11h,0E2h,32h,52h,49h,44h,84h,82h,41h,0A1h,12h,0A1h
    db 0FFh,00h,0FFh,0FFh,00h,0FFh,80h,80h,80h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,03h,04h,04h,0C4h,23h,26h,25h,0C9h,11h,10h,20h,41h,42h,24h,42h
    db 0FFh,00h,0FFh,0FFh,00h,0FFh,01h,01h,01h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,80h,40h,47h,48h,88h,08h,07h,04h,0Ch,94h,0A4h,48h,88h,48h,88h
    db 0F0h,10h,0F0h,80h,00h,80h,00h,00h,00h,80h,0E0h,1Ch,0E4h,04h,0FCh,00h
    db 00h,00h,00h,00h,80h,80h,80h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

KingOutline:
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,01h,02h,02h,04h,08h,04h
    db 04h,02h,02h,01h,00h,00h,00h,00h,00h,01h,03h,38h,27h,20h,3Fh,00h
    db 07h,04h,04h,78h,40h,40h,40h,78h,04h,0F8h,7Fh,80h,7Fh,7Fh,80h,40h
    db 20h,11h,0Ah,84h,7Fh,00h,7Fh,40h,80h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 0E0h,20h,20h,1Eh,02h,02h,02h,1Eh,20h,1Fh,0FEh,01h,0FEh,0FFh,00h,01h
    db 82h,44h,28h,11h,0FEh,00h,0FEh,02h,01h,00h,0FFh,00h,0FFh,00h,0FFh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,80h,40h,40h,20h,90h,20h
    db 20h,40h,40h,80h,00h,00h,00h,00h,00h,80h,0C0h,1Ch,0E4h,04h,0FCh,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    db 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; ------------------------------------------------------------------
; Compact permanent lower-screen image
;
; The file contains 80 consecutive byte-columns of 200 bytes. The loader
; expands it into the QX-11's 0200h-stride lower VRAM without touching gaps.
; ------------------------------------------------------------------
SplashFileName:
    db "IMG.DAT",0
SplashFileHandle:
    dw 0
SplashFileHeader:
    times 4 db 0
SplashScanlineBuffer:
    times 80 db 0

StaticLowerBitmap:
    incbin "QXCHESS_PHASE6II_BOTTOM.BIN"


; Phase 6 II R10 compressed hardware-validated VRAM snapshot
CompressedVRAMSnapshot:
    incbin "QXCHESS_PHASE6II_VRAM_R10.BIN"
