# Epson ICRT Worklog

## Purpose

This file is our working contract for the `epson_icrt` device used by the QX-11 and QX-16 drivers.
It exists to keep the current goals, assumptions, and known gaps close to the code so future work is easier to continue and review.

## Working Agreement

When changing `epson_icrt`, we will try to preserve these rules:

- Keep QX-11 and QX-16 behavior aligned unless documentation or hardware tests prove they differ.
- Prefer hardware-documented behavior over convenience hacks.
- Isolate machine-specific policy in the machine drivers when possible.
- Keep temporary compatibility shims clearly documented in code and in this file.
- Verify changes with a focused test case whenever possible before moving on.
- Prioritize faithful CGA-compatible behavior first, then apply Epson-specific memory mapping rules.

## Current Scope

The current ICRT work includes:

- CGA-compatible text and graphics behavior
- Plantronics-style graphics extensions
- Palette handling for CGA 4-color modes
- VRAM aperture and banking behavior controlled by `03CEh` and `03CFh`
- Shared use on both the QX-11 and QX-16

## Current Assumptions

- The ICRT card should emulate a CGA card as closely as possible in register behavior, timing expectations, and graphics mode interpretation.
- The most important baseline is to honor standard CGA registers and modes before applying Epson-specific extensions.
- `03CFh` controls whether the `B0000h` and `B8000h` CPU apertures respond.
- If both apertures are enabled, they mirror the same VRAM.
- In graphics modes, `03CEh` bit 7 selects 16K vs 32K VRAM access.
- In graphics modes, `03CEh` bit 6 selects lower vs upper 16K when 16K access is active.
- Display interpretation and CPU VRAM access are related but not identical, so both must be checked when debugging.
- High-resolution graphics modes are treated as `1bpp`.
- Low-resolution graphics modes are treated as `2bpp`.

## Documented Graphics Modes

The APX-ICRT documentation describes the graphics modes in terms of resolution, VRAM allocation, and control-register values. These notes should guide future renderer and memory-layout work.

- `VM0`: lower 16K VRAM (`0000-3fff`), repeated scanlines, used for 320x400-style display from 320x200 source data
- `VM1`: lower 16K VRAM (`0000-3fff`), non-repeated scanlines, 320x200
- `VM2`: upper 16K VRAM (`4000-7fff`), repeated scanlines
- `VM3`: upper 16K VRAM (`4000-7fff`), non-repeated scanlines
- `VM4`: 32K VRAM, even/odd scan split across lower and upper 16K, repeated scanlines
- `VM5`: 32K VRAM, even/odd scan split across lower and upper 16K, non-repeated scanlines
- `VM6`: 32K VRAM, 640x400-style high-resolution layout without duplicated display data

These documented control bits are especially important:

- `03CEh` bit 7 `CM/EX`: `0 = 16K`, `1 = 32K`
- `03CEh` bit 6 `A/B`: `0 = 0000-3fff`, `1 = 4000-7fff`
- `03CEh` bit 5 `G400/G200`: controls repeated-line 400-line style output versus 200-line output
- `03D8h/03B8h` bit 4 `HGR`: selects high-resolution graphics mode
- `03D8h/03B8h` bit 1 `GR`: selects graphics mode

## Sample Mode Table

The table labeled `APX-ICRT Sample Graphic Display Modes` is useful as a concrete checkpoint for register programming. These values should be treated as known-good targets when comparing software behavior with the renderer.

### Low-Res (`LCH`)

- CRT type: `200 / 400`
- Display size: `320 x 200`
- VRAM/pages: `8K`
- `03CEh` bit 5 `G640/G200`: `1 / 0`
- `03D4h` R1: `28h (40)`
- `03D4h` R6: `64h (100)`
- `03D4h` R9: `07h (8) / 0Fh (16)`
- `03D8h` bit 0 `HCH`: `0`
- `03D8h` bit 1 `GR`: `0`
- `03D8h` bit 4 `HGR`: `0`
- `03D8h` bit 5 `BL.EN`: `1`

### Modified Low-Res (`LLCH`)

- CRT type: `200`
- Display size: `160 x 100`
- VRAM/pages: `16K`
- `03CEh` bit 5 `G640/G200`: `0`
- `03D4h` R1: `50h (80)`
- `03D4h` R6: `64h (100)`
- `03D4h` R9: `0Fh (16)`
- `03D8h` bit 0 `HCH`: `0`
- `03D8h` bit 1 `GR`: `0`
- `03D8h` bit 4 `HGR`: `0`
- `03D8h` bit 5 `BL.EN`: `1`

### High-Res (`HCH`)

- CRT type: `200 / 400`
- Display size: `640 x 200`
- VRAM/pages: `16K`
- `03CEh` bit 5 `G640/G200`: `1 / 0`
- `03CEh` bit 6 `A/B`: `-`
- `03CEh` bit 7 `CM/EX`: `- / 0`
- `03D4h` R1: `28h (40)`
- `03D4h` R6: `64h (100)`
- `03D4h` R9: `07h (8) / 0Fh (16)`
- `03D8h` bit 0 `HCH`: `1`
- `03D8h` bit 1 `GR`: `0`
- `03D8h` bit 4 `HGR`: `0`
- `03D8h` bit 5 `BL.EN`: `1`

### Modified High-Res (`HHCH`)

- CRT type: `400`
- Display size: `640 x 400`
- VRAM/pages: `32K`
- `03CEh` bit 5 `G640/G200`: `1`
- `03CEh` bit 6 `A/B`: `1`
- `03CEh` bit 7 `CM/EX`: `1`
- `03D4h` R1: `28h (40)`
- `03D4h` R6: `64h (100)`
- `03D4h` R9: `07h (8)`
- `03D8h` bit 0 `HCH`: `1`
- `03D8h` bit 1 `GR`: `0`
- `03D8h` bit 4 `HGR`: `0`
- `03D8h` bit 5 `BL.EN`: `1`

## Monitor Behavior Notes

The documentation distinguishes low-resolution and high-resolution monitor behavior, and we should preserve that distinction in future work:

- On a high-resolution monitor, some 200-line source modes are displayed by repeating lines to fill a 400-line display.
- For low-resolution displays, the same source mode may remain a native 200-line presentation.
- The table notes that in high-resolution monitor mode the displayed data may be duplicated vertically rather than changing the underlying VRAM layout.
- Future renderer changes should avoid conflating monitor line-doubling behavior with CPU-visible VRAM banking.

Table footnotes worth preserving:

- LLR graphics data is deduced from HCR display page data.
- LLR uses 16-color graphics derived from HCR mode.
- In `HHCH` mode, display data is not duplicated. The documentation points back to `VM6` for that layout.

## Known Implemented Changes

- Plantronics extension register handling at `3BDh/3DDh`
- CGA-style palette LUT for 2bpp graphics
- VRAM map/register decode for `03CEh` and `03CFh`
- Wider mono VRAM aperture handling inside the device

## Open Questions

- Whether all documented ICRT display modes are fully represented in the renderer
- Whether any QX-11 and QX-16 specific differences still need to live outside the common device
- Whether IMD or other image/media interactions reveal additional ICRT-side assumptions in software
- Whether Sierra and other software rely on edge-case palette or memory alias behavior not yet modeled
- Why newer Sierra SCI graphics still diverge while older Sierra AGI graphics now render correctly

## Test Cases To Keep Repeating

- QX-16 boot and graphics software with the ICRT enabled
- Sierra title switching between 640x200 color and CGA 4-color graphics
- Sierra AGI title in working mode as a regression baseline
- Sierra SCI title in failing mode as the primary graphics regression target
- Accesses through both `B0000h` and `B8000h` apertures
- Cases where `03CFh` enables only one aperture
- Cases where both apertures are enabled and should mirror

## Git Tracking

Recommended workflow for this Epson work:

1. Keep this file updated when behavior or assumptions change.
2. Stage Epson-related files together so the history stays readable.
3. Use small commits with messages that describe one behavior change at a time.

Suggested file set to review when touching ICRT work:

- `src/mame/epson/epson_icrt.cpp`
- `src/mame/epson/epson_icrt.h`
- `src/mame/epson/qx11.cpp`
- `src/mame/epson/qx16.cpp`
- `src/mame/epson/ICRT_WORKLOG.md`

## Change Notes

- 2026-04-17: Restored active development tracking with this worklog.
- 2026-04-17: Reinstated Plantronics support and CGA-style palette handling.
- 2026-04-17: Honored VRAM aperture and bank control via `03CEh` and `03CFh`.
- 2026-04-18: Set project priority to CGA-faithful behavior first, with Epson-specific VRAM mapping layered afterward.
- 2026-04-18: Recorded current working/failing Sierra regressions and the bit-depth rule of `1bpp` high-res, `2bpp` low-res.
