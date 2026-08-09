# Epson QX-11 BIOS-Integrated ANSI Console Support

One interesting feature discovered while reverse engineering the Epson QX-11
is that the machine contains an ANSI/VT-style terminal control parser directly
in its BIOS.

Unlike the IBM PC, where ANSI escape-sequence support was normally provided
by a DOS device driver such as `ANSI.SYS`, the QX-11 implements the parser as
part of its native video BIOS.

## INT 10h AH=4Ah

The QX-11 provides the proprietary video BIOS function:

    INT 10h
    AH = 4Ah
    AL = character to process

Characters are passed to this function one at a time.

The BIOS maintains parser state between calls, allowing a program to send
complete terminal-control sequences character by character.

Reverse engineering of the BIOS shows recognition of characters including:

    ESC
    [
    ;
    0-9
    ?
    =
    "
    '

Numeric parameters are accumulated by the BIOS, including support for
multiple parameters separated by semicolons.

This makes sequences of the following form possible:

    ESC [ 10 ; 20 H

## ANSI/VT-Style Command Dispatch

The BIOS contains a dispatch table for the final character of a CSI sequence.

Several entries correspond directly with familiar ANSI/VT terminal commands:

| Character | Function |
|-----------|----------|
| A | Cursor up |
| B | Cursor down |
| C | Cursor forward |
| D | Cursor backward |
| H | Cursor position |
| J | Erase display |
| K | Erase line |
| f | Cursor position |
| h | Set mode |
| l | Reset mode |
| m | Select graphic rendition |
| n | Status/report function |
| s | Save cursor |
| u | Restore cursor |

Particularly interesting is that both `H` and `f` dispatch to the same BIOS
routine, consistent with their equivalent cursor-positioning roles in ANSI
terminal control.

The `m` command is also present, corresponding to the familiar
Select Graphic Rendition (SGR) mechanism.

Some commands and private forms still require further analysis, so the QX-11
implementation is best described as **ANSI/VT-style** rather than assumed to
be a complete ANSI implementation.

## Integration with DOS

The most interesting discovery is that this parser is connected to the normal
DOS console output mechanism.

MS-DOS provides `INT 29h` as its fast console-output interface. On the QX-11,
the BIOS handler for INT 29h is extremely small:

    push ax
    mov  ah,4Ah
    int  10h
    pop  ax
    iret

Therefore the path is:

    DOS application / COMMAND.COM
                |
                v
             DOS CON
                |
                v
             INT 29h
                |
                v
          INT 10h AH=4Ah
                |
                v
       Epson ANSI/VT-style parser
                |
                v
        QX-11 display routines
                |
                v
              GAVDP

This means the ANSI-style interpreter was not merely an obscure BIOS service
available to specially written Epson applications.

It was integrated into the QX-11's DOS console-output architecture.

## Comparison with the IBM PC

On an IBM PC, the BIOS INT 10h interface supplied relatively low-level video
operations such as cursor positioning, scrolling, character output and video
mode control.

ANSI escape-sequence interpretation was normally added at the DOS level by
loading `ANSI.SYS`.

Conceptually:

    IBM PC:

    Application
        |
        v
    DOS / CON
        |
        v
    ANSI.SYS
        |
        v
    BIOS INT 10h
        |
        v
    Video hardware


    Epson QX-11:

    Application
        |
        v
    DOS / CON
        |
        v
    INT 29h
        |
        v
    BIOS INT 10h AH=4Ah
        |
        v
    Built-in ANSI/VT-style parser
        |
        v
    Epson video hardware

In effect, functionality for which an IBM PC commonly required `ANSI.SYS`
was already present in the QX-11 firmware.

## Native Software Usage

This BIOS service is not merely theoretical.

Analysis of native QX-11 software shows applications calling
`INT 10h/AH=4Ah` directly and feeding strings through the parser one character
at a time.

This allowed software to use the same BIOS terminal-processing functionality
without having to implement its own escape-sequence parser.

## Why This Matters

This is another example of an important distinction between the Epson QX-11
and an IBM PC compatible.

The QX-11 runs MS-DOS, but underneath DOS it provides its own Epson hardware
and firmware architecture.

The built-in console parser provided applications with a relatively
hardware-independent way of performing cursor movement, screen erasing,
display attributes, mode control and other terminal-style operations while
the Epson BIOS handled the underlying QX-11 display hardware.

Further reverse engineering of the individual command handlers should allow
the complete QX-11 escape-sequence language to be documented.
