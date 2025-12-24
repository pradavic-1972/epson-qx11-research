Booting ELKS on the Epson QX-11 (8088, No PIC, No PIT)
Background
My first computer, nearly 35 years ago, was an Epson QX-11.
It is an 8088-based system with MS-DOS 2.11 stored in ROM, and a hardware architecture that differs substantially from the IBM PC.

After extensive reverse engineering of the QX-11 BIOS, memory map, boot process, and gate-array-based I/O subsystem, I developed:

a custom MAME driver for the Epson QX-11
a complete understanding of how the QX-11 boots from ROM cartridges and diskette images
With that knowledge, I attempted to boot ELKS (Linux-8086) on the QX-11.

This document describes what was required, what failed, why it failed, and the kernel fix needed to make ELKS usable on a machine without a PIC or PIT.

1. Booting constraints of the Epson QX-11
1.1 Memory map differences vs IBM PC
The QX-11 is not IBM-PC compatible at the hardware level:

Low memory contains BIOS, video, and gate-array windows not present on IBM PCs
ELKS’ default kernel relocation target collides with these regions
Video RAM is mapped at segment 0x8000, not 0xB800
The machine uses custom Epson gate arrays instead of:
8259 PIC
8253/8254 PIT
CGA/MDA video
Because of this:

ELKS cannot safely relocate the kernel to low memory
Direct console drivers (CGA/MDA) do not work
2. Booting ELKS from ROM
ELKS supports a boot-from-ROM configuration, which was the only viable initial approach.

Steps taken:

Built ELKS using ROM boot support
Placed kernel and filesystem at segment C000
Adjusted kernel text and data segments to avoid overwriting BIOS and video memory
Used BIOS console output instead of a direct console driver
Result:

ELKS successfully booted from ROM
Kernel messages appeared
Login prompt appeared
However, the keyboard did not work.

3. Keyboard did not work
Despite a visible login prompt, no keyboard input was accepted.

Investigation showed:

kbd_init() was running
kbd_poll_init() was running
A keyboard poll timer was being successfully armed
jiffies was advancing
But the keyboard poll timer callback never fired
4. Why the keyboard poll timer never fired
4.1 ELKS keyboard polling model
On ELKS/8088, the BIOS keyboard driver uses polling:

A periodic timer fires
The timer callback calls conio_poll()
conio_poll() invokes BIOS INT 16h
Returned keystrokes are injected into the tty layer
This polling depends on kernel timers, which depend on:

timer_tick()
mark_bh(TIMER_BH)
timer_bh() -> run_timer_list()
4.2 The QX-11 has no PIC and no PIT
The Epson QX-11 does not have an 8259 PIC or an 8253/8254 PIT.

Instead, it provides BIOS-generated periodic ticks delivered via INT 1Ch.

ELKS provides a configuration option for this:

CONFIG_TIMER_INT1C
This option was enabled.

4.3 The critical bug / omission in ELKS
In irq.c, ELKS initializes the timer bottom-half only when IRQ0 is used:

request_irq(TIMER_IRQ, timer_tick, INT_GENERIC);
init_bh(TIMER_BH, timer_bh);
However, when INT 1Ch is used as the timer source:

request_irq(7, timer_tick, INT_GENERIC);
/* init_bh(TIMER_BH, timer_bh) is missing */
As a result:

timer_tick() runs
jiffies increments
mark_bh(TIMER_BH) is called
but TIMER_BH has no registered handler
timer_bh() never runs
run_timer_list() never runs
keyboard poll timers never fire
5. The fix
In irq.c, inside the CONFIG_TIMER_INT1C path, add:

init_bh(TIMER_BH, timer_bh);
Full context:

#if defined(CONFIG_TIMER_INT0F) || defined(CONFIG_TIMER_INT1C)
    if (request_irq(7, timer_tick, INT_GENERIC))
        panic("Unable to get timer");

    init_bh(TIMER_BH, timer_bh);
#endif
6. Result
After this change:

timer_bh() runs
run_timer_list() executes
kbd_timer() fires
conio_poll() executes BIOS INT 16h
Keyboard input works correctly
For the first time, an operating system other than MS-DOS 2.11 successfully booted and accepted keyboard input on an Epson QX-11.

7. Open questions for the ELKS community
Is the omission of init_bh(TIMER_BH, timer_bh) in the CONFIG_TIMER_INT1C path intentional?
Has anyone attempted to boot ELKS on systems without a PIC or PIT?
Are additional timing or scheduling issues expected when using INT 1Ch instead of IRQ0?
Closing
Booting ELKS on the Epson QX-11 required understanding both the machine’s unique hardware and a subtle assumption inside the ELKS timer subsystem.

I am happy to share patches, emulator work, and documentation if useful.

Best regards,
Victor
