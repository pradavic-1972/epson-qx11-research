# Epson QX-11 Invaders

## A Native 640×200, 8-Color Arcade Game for the Epson QX-11

This project is a complete **Space Invaders-inspired arcade game** written in 8086 assembly language specifically for the Epson QX-11.

The goal was not to reproduce the original arcade game pixel-for-pixel. Instead, the project became an experiment in using the QX-11 as a native game platform and documenting hardware capabilities that were rarely used by commercial software.

The final game includes:

- Native 640×200 planar RGB graphics
- All eight hardware colors
- Multicolor sprites
- Animated alien formations
- Player and enemy bullets
- Destructible bunkers
- Multiple waves
- Scoring and lives
- Mystery UFO
- Large planar splash screen
- Bonus and game-over banners
- SN76489AN sound effects
- Screen shake
- Full-screen color flash effects
- Native QX-11 timer-based gameplay pacing

The game was designed and tested around real QX-11 hardware behavior rather than IBM PC assumptions.

---

## Why the Epson QX-11?

The Epson QX-11 was marketed primarily as a business computer. Most surviving software focuses on text, office applications, communications, and monochrome graphics.

However, the machine also contains hardware that can support much richer software:

- An 8088-class CPU
- 640×200 planar color graphics
- 640×400 monochrome graphics
- Eight RGB colors
- An SN76489AN programmable sound generator
- A high-frequency native timer interrupt
- Joystick BIOS support
- Hardware display-origin registers that can be used for effects such as screen shake

This project explores those capabilities directly.

---

# Development History

The project began with a very small goal:

> Draw one alien in QX-11 color mode.

That first test exposed one of the most important discoveries in the project: the QX-11 color framebuffer does **not** use the same memory organization as the 640×400 monochrome mode.

After the correct color formula was confirmed on real hardware, the project grew in stages:

1. Draw one alien.
2. Animate the alien.
3. Draw the complete 55-alien formation.
4. Move the formation left and right.
5. Add downward movement and acceleration.
6. Add alien explosions and alive/dead tracking.
7. Add the player ship.
8. Add player bullets.
9. Add bullet-to-alien collision.
10. Add enemy bullets.
11. Add lives and game over.
12. Add scoring.
13. Add destructible bunkers.
14. Add the mystery UFO.
15. Add a splash screen.
16. Add SN76489 sound.
17. Replace software delay loops with the native QX-11 timer.
18. Add screen shake and full-screen flash effects.
19. Add multiple waves and bonus banners.
20. Polish sprite size, color, sound, pacing, and animation.

The result is not only a game, but also a reusable body of QX-11 graphics, timing, sound, and input code.

---

# Video Modes and VRAM Organization

One of the most important lessons from this project is that QX-11 color and monochrome graphics must be treated as two different rendering systems.

## 640×200 Color Mode

The native color mode uses three separate 1-bit-per-pixel VRAM planes:

| Plane | Segment |
|---|---:|
| Blue | `8000h` |
| Red | `8008h` |
| Green | `9000h` |

Each plane represents the same 640×200 image.

The final pixel color is produced by combining the corresponding bit from the three planes.

| Blue | Red | Green | Result |
|---:|---:|---:|---|
| 0 | 0 | 0 | Black |
| 1 | 0 | 0 | Blue |
| 0 | 1 | 0 | Red |
| 1 | 1 | 0 | Magenta |
| 0 | 0 | 1 | Green |
| 1 | 0 | 1 | Cyan |
| 0 | 1 | 1 | Yellow |
| 1 | 1 | 1 | White |

### Color Pixel Formula

Valid coordinates are:

```text
X = 0..639
Y = 0..199
```

The address calculation is:

```text
x_byte  = X >> 3
bit_mask = 80h >> (X & 7)
offset   = (Y << 8) + x_byte
```

Equivalent form:

```text
offset = Y × 0100h + x_byte
```

Only the first 80 bytes of each 256-byte row slot are visible.

A pixel is drawn by performing a read-modify-write in each color plane:

```text
Blue bit  = color bit 0
Red bit   = color bit 1
Green bit = color bit 2
```

The leftmost pixel in each byte uses bit 7.

### Why the Row Size Is 256 Bytes

The visible scanline is only 80 bytes wide:

```text
640 pixels / 8 = 80 bytes
```

However, the QX-11 color framebuffer reserves a 256-byte address slot for each scanline.

Therefore, moving down one line means adding:

```text
0100h
```

not `50h`.

This detail was essential to getting color graphics working correctly.

---

## 640×400 Monochrome Mode

The 640×400 monochrome mode uses two 200-line banks:

| Screen Area | Segment |
|---|---:|
| Top half, Y=0..199 | `8000h` |
| Bottom half, Y=200..399 | `8010h` |

The addressing formula is:

```text
bank =
    8000h when Y < 200
    8010h when Y >= 200

local_y =
    Y when Y < 200
    Y - 200 when Y >= 200

x_byte  = X >> 3
bit_mask = 80h >> (X & 7)
offset   = (local_y << 8) + x_byte
```

The key point is that monochrome mode is banked vertically, while color mode uses three independent RGB planes.

The two renderers must not be mixed.

---

# Sprite Rendering

The game uses precomputed planar bitmap sprites.

Each multicolor sprite contains independent data for the three QX-11 color planes:

```asm
sprite_blue:
sprite_red:
sprite_green:
```

For every sprite row, the renderer copies:

- Blue data to segment `8000h`
- Red data to segment `8008h`
- Green data to segment `9000h`

This allows every pixel in a sprite to use any of the eight available colors without runtime color conversion.

The final alien designs use multiple colors within each sprite:

- Squid aliens: magenta, yellow, and white
- Crab aliens: cyan, blue, and white
- Octopus aliens: green, red, yellow, and white
- Player ship: cyan, red, yellow, and white
- UFO: red, magenta, cyan, yellow, and white
- Explosions: all seven nonblack colors

---

# Dirty-Rectangle Rendering

The game does not redraw the entire 640×200 display for every movement.

A complete visible color frame contains:

```text
80 bytes × 200 rows × 3 planes = 48,000 bytes
```

Rewriting all 48 KiB for every animation update would be unnecessarily expensive on an 8088.

Instead, the game uses dirty rectangles:

1. Erase the sprite at its old position.
2. Update its coordinates.
3. Draw the sprite at its new position.

For example, moving the 32×12 UFO requires only a few hundred VRAM byte writes rather than a 48 KiB screen copy.

This technique is used for:

- Alien movement
- Player movement
- UFO movement
- Bullets
- Explosions
- Banners
- Bunker damage

---

# Smooth UFO Movement

Most sprites move on byte boundaries because one VRAM byte represents eight horizontal pixels.

The UFO was improved by using multiple pre-shifted frames.

Four versions of the same UFO are stored:

```text
Phase 0: 0-pixel shift
Phase 1: 2-pixel shift
Phase 2: 4-pixel shift
Phase 3: 6-pixel shift
```

After phase 3, the UFO advances one full VRAM byte and returns to phase 0.

This produces two-pixel movement while retaining fast bitmap copies.

The UFO also:

- Selects a slightly different speed on each appearance
- Changes speed occasionally during flight
- May reverse direction once
- Uses a continuous pitch-swept siren
- Produces a large explosion and red screen flash when destroyed

---

# Game Timing

## Why Software Delay Loops Were Rejected

Early versions used loops such as:

```asm
mov cx,30000
.delay:
    loop .delay
```

This worked for simple prototypes but created several problems:

- Game speed depended on CPU speed
- More complex drawing changed the pacing
- Sound made timing differences easier to hear
- Heavy operations could cause pauses followed by rapid catch-up movement
- MAME and real hardware did not always behave identically

The final game uses the native Epson timer.

---

## QX-11 INT 71h

Real-hardware testing established that the QX-11 native timer interrupt runs at approximately:

```text
388.8 Hz
```

The game hooks:

```text
INT 71h
```

The interrupt handler remains intentionally small. It increments a software timing accumulator and then chains to the original BIOS handler.

A fractional divider produces one game tick for every 2.5 native INT 71h interrupts:

```text
388.8 Hz / 2.5 ≈ 155.52 Hz
```

Conceptually:

```asm
add byte [int71_accumulator],2
cmp byte [int71_accumulator],5
jb  .chain

sub byte [int71_accumulator],5
inc word [game_ticks]
```

This naturally alternates between two and three hardware interrupts per game tick.

The game scheduler uses this software tick for:

- Alien movement
- Player bullets
- Enemy bullets
- UFO movement
- Enemy firing
- Explosion timing
- Sound envelopes
- Screen flash duration
- Screen shake duration
- Wave transitions

Missed ticks are intentionally dropped instead of queued. This prevents a long drawing operation from being followed by a burst of accumulated movements.

---

# Alien Movement Engine

All 55 aliens share one formation position.

The game does not move 55 independent objects.

Each alien position is calculated from:

```text
screen_x = formation_x + column_offset
screen_y = formation_y + row_offset
```

The formation state includes:

```text
X position
Y position
Direction
Animation frame
Movement period
Alive count
Leftmost live column
Rightmost live column
```

When the formation reaches a live edge:

1. It moves downward.
2. Direction reverses.
3. The movement sound advances.
4. The speed may be recalculated.

The left and right limits are based only on living columns. Destroying an entire outside column allows the remaining formation to travel farther toward that side.

---

# Alien Speed

The original acceleration curve was too abrupt. The final version uses a gradual table based on the number of living aliens.

Example structure:

```text
46–55 aliens: slowest
36–45 aliens: slightly faster
26–35 aliens: faster
16–25 aliens: faster
 8–15 aliens: fast
 2–7  aliens: very fast
 1 alien: fastest
```

A smaller additional speed increase is applied as the formation descends.

This produces the familiar rising tension without making the early game too difficult.

---

# Correct Ground Detection

The game must stop when the lowest living alien reaches the player zone.

A fixed calculation based on the original fifth row is incorrect because lower rows may already have been destroyed.

The final code scans upward from row 4 and finds the lowest row containing at least one living alien.

The bottom position is then calculated as:

```text
bottom_y =
    formation_y
  + lowest_living_row × row_spacing
  + sprite_height - 1
```

Only that live row is used for the game-over decision.

---

# Screen Shake

The QX-11 can shift the displayed image by changing GAVDP display-origin registers.

The game uses the same technique previously developed for the QX-11 Sierra SCI driver.

The relevant physical addresses are:

```text
8C462h
8C663h
```

They are accessed through segment `8000h` as:

```text
8000:C462
8000:C663
```

When the player is hit, the game alternates these origin registers between their normal value and a small offset.

Conceptually:

```asm
mov al,02h
mov [es:0C462h],al
mov [es:0C663h],al
```

The effect is timer-driven and non-blocking.

When the effect ends, both registers are restored to zero.

This creates a convincing whole-screen shake without moving or redrawing every object.

---

# UFO Red Flash

When the UFO is destroyed, the game briefly turns the playfield red.

Rather than saving and restoring the entire screen, it performs a reversible XOR operation on the visible Red plane:

```asm
xor byte [es:di],0FFh
```

The same XOR is applied again after a short delay.

Because XOR is reversible, the original Red-plane contents are restored exactly.

This effect requires no 16 KiB backup buffer.

---

# Sound Hardware

The QX-11 uses a Texas Instruments SN76489AN programmable sound generator.

The sound chip is written through:

```text
I/O port 14h
```

The SN76489 provides:

- Three tone channels
- One noise channel
- Sixteen attenuation levels per channel
- Programmable tone periods
- Programmable noise modes

The chip does not provide hardware ADSR envelopes, echo, or reverb. Those effects are synthesized in software by changing tone and volume values over time.

---

# Sound Engine

The sound engine is updated from the same timer scheduler used by the game.

No sound routine contains a blocking delay loop.

The game implements:

- Four-step alien march
- Layered alien march bass
- Player shot pitch sweep
- Player shot echo
- Enemy shot sound
- Alien explosion
- Player explosion
- Bunker impact
- UFO siren
- UFO reversal chirp
- UFO destruction effect
- Player-ready cue
- Bonus fanfare

## Alien March

The alien movement sound is synchronized with actual formation movement.

Each step plays the next note in a four-note sequence.

The final version layers:

- A short lead tone
- A lower bass tone when the channel is available

As the formation moves faster, the sound naturally accelerates.

## Player Shot

The shot begins at a high pitch and falls rapidly.

A quieter delayed repeat creates an echo-like effect.

## Explosions

Explosions combine:

- Noise channel
- One or more descending tone channels
- Software-controlled volume decay
- Changes in noise mode during the tail

Alien explosions are short and sharp.

Player explosions are intentionally longer and heavier.

## UFO

The UFO uses a continuously updated tone-channel siren.

Its frequency rises and falls gradually, producing an engine-like wobble.

The siren stops when the UFO leaves the screen or is destroyed.

---

# Destructible Bunkers

Each bunker is represented by a software bitmap.

The displayed bunker is regenerated from this bitmap after damage.

Both player and enemy bullets can remove parts of the bunker.

The bunker state is not stored only in VRAM, which allows consistent redraw and future expansion.

---

# Bullets and Collision Detection

The player can have two simultaneous bullets.

Each bullet slot stores:

```text
active flag
X byte
Y coordinate
movement timer
```

The collision system checks bullets against:

1. UFO
2. Bunkers
3. Living aliens

Enemy bullets check:

1. Bunkers
2. Player ship

The bottom-most living alien in each column is tracked in an 11-byte lookup table. This makes alien firing efficient.

---

# Multiple Waves

When all aliens are destroyed:

1. The final alien score is awarded.
2. Active bullets are removed.
3. A centered `BONUS POINTS` banner appears.
4. A wave-clear bonus is added.
5. A fanfare plays.
6. The game waits briefly.
7. A new 55-alien formation is created.
8. Score and remaining lives are preserved.

Care was required to avoid continuing normal collision processing after the final alien was destroyed. Doing so previously caused a divide overflow because the bonus sequence changed working registers before the collision routine completed.

---

# Splash Screen and Banners

The splash screen and large banners are stored as native planar bitmaps.

The splash is copied into the three VRAM planes row by row.

Large banners such as:

```text
GAME OVER
BONUS POINTS
```

are stored as 320-pixel-wide planar graphics and centered in the 640-pixel display.

A 320-pixel image begins at:

```text
X = 160 pixels
X byte = 20
```

The banners are drawn and cleared using the same row-oriented color formula as the rest of the game.

---

# Input

The current playable version uses BIOS keyboard input:

```text
Left Arrow   Move left
Right Arrow  Move right
Space        Fire
Esc          Exit
R / Enter    Restart after game over
```

The QX-11 BIOS also provides joystick polling through:

```asm
mov ah,10h
mov al,0       ; joystick 0
int 15h
```

or:

```asm
mov ah,10h
mov al,1       ; joystick 1
int 15h
```

The BIOS selects the joystick through port `0Fh`, reads port `0Eh`, and waits until two consecutive values match.

The exact direction and button bit mapping still requires real-hardware testing with a physical joystick.

Joystick support is planned as the final hardware validation step.

---

# Building

The source is written for NASM and produces a DOS `.COM` executable.

Example:

```bash
nasm -f bin QX11_INVADERS_GOLD_V1.ASM -o QXGOLD.COM
```

Run the resulting executable on:

- A real Epson QX-11
- A compatible QX-11 environment
- MAME for preliminary testing

Real-hardware testing is still essential because timing, display behavior, and sound can differ from emulation.

---

# Technical Lessons

This project produced reusable techniques for native QX-11 software development:

- Correct 640×200 color VRAM addressing
- Correct 640×400 monochrome bank selection
- Multicolor planar sprite format
- Dirty-rectangle animation
- Pre-shifted sprite frames
- Timer-driven game scheduler
- Fractional interrupt divider
- SN76489 tone and noise programming
- Software volume envelopes
- Hardware screen shake
- Reversible full-screen color effects
- Dynamic formation bounds
- Living-row ground detection
- Stable wave transitions
- Native BIOS joystick access

These components can be separated into a future QX-11 game-development library.

---

# Possible Future Library Structure

```text
QX11LIB/
├── VIDEO.ASM
├── SPRITE.ASM
├── SOUND.ASM
├── TIMER.ASM
├── INPUT.ASM
├── JOYSTICK.ASM
├── COLLISION.ASM
├── BITMAP.ASM
├── FONT.ASM
└── RANDOM.ASM
```

Example programs could include:

- Draw one pixel
- Draw a multicolor sprite
- Animate a sprite
- Play a tone
- Play an explosion
- Load a planar bitmap
- Read the keyboard
- Read a joystick
- Use INT 71h as a scheduler
- Apply screen shake

---

# What Comes Next

The next planned game is **Galaga-inspired**.

Much of the current engine can be reused:

- Planar sprite rendering
- Sound engine
- Bullets
- Collision detection
- Explosions
- Score
- Lives
- Splash and banners
- Timer scheduler
- UFO movement
- Random number generator

The new work will focus on:

- Curved attack paths
- Formation entry animations
- Diving enemies
- Capture beam
- Dual-fighter mechanic
- More advanced enemy behavior
- Joystick control
- Richer music and sound

---

# Acknowledgements

This project was made possible through extensive reverse engineering and real-hardware testing of the Epson QX-11.

The work included investigation of:

- VRAM layout
- BIOS behavior
- Timer interrupts
- Display registers
- Sound hardware
- Joystick services
- Color-plane organization
- Real-machine performance characteristics

The Epson QX-11 was designed as a business computer, but this project demonstrates that it is also capable of colorful, smooth, arcade-style games when programmed directly.

---

# Project Status

**QX-11 Invaders Gold v1.0**

Gameplay is complete.

Remaining validation:

- Physical joystick bit mapping
- Final joystick integration
- Final real-hardware balancing
- Repository cleanup and source modularization

After that, development moves to the Galaga project.
