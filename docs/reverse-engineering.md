---
title: Reverse Engineering
layout: default
---

<link rel="stylesheet" href="{{ '/assets/css/site.css' | relative_url }}">

<div class="qx11-page">
  <div class="qx-kicker">Technical index</div>
  <h1>Reverse Engineering Notes</h1>
  <p>
    This page organizes the main technical writeups in the QX-11 research archive. Most of the deeper documents live in the repository's <code>Reverse Engineering</code> folder, so links here point back to the source files on GitHub.
  </p>

  <section class="qx-section">
    <h2>Core hardware</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>GAVDP — video gate array</h3>
        <p>Memory-mapped video system, column-oriented VRAM, hidden control registers, hardware scrolling, display profiles, and MAME notes.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVDP.md">Open GAVDP.md</a>
      </div>
      <div class="qx-card">
        <h3>GAVEMR — memory gate array</h3>
        <p>DRAM type jumpers, ROM decoding, clock input tracing, refresh investigation, RAM size behavior, and ROM chip selection.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVEMR.md">Open GAVEMR.md</a>
      </div>
      <div class="qx-card">
        <h3>Gate arrays overview</h3>
        <p>High-level map of Epson custom ICs used by the QX-11 and their suspected roles.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/gate-arrays.md">Open gate-arrays.md</a>
      </div>
      <div class="qx-card">
        <h3>GAVNIO and GAVNIT</h3>
        <p>Notes around I/O, interrupt routing, and related proprietary Epson glue logic.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/Reverse%20Engineering">Browse reverse-engineering folder</a>
      </div>
    </div>
  </section>

  <section class="qx-section">
    <h2>Firmware and boot behavior</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>ROM cartridge system</h3>
        <p>Confirmed cartridge signature, load segment byte, filesystem enable byte, executable offset, drive-letter mapping, and DOS boot integration.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Cartridge.md">Open Cartridge.md</a>
      </div>
      <div class="qx-card">
        <h3>ROM expansion</h3>
        <p>ROM size selection jumpers, expanded ROM work, and practical boot-ROM modification notes.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/rom_expansion.md">Open rom_expansion.md</a>
      </div>
      <div class="qx-card">
        <h3>Interrupt vector table</h3>
        <p>BIOS vector grouping and notes around Epson-specific interrupt handlers.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/QX11_IVT_Groups.md">Open QX11_IVT_Groups.md</a>
      </div>
      <div class="qx-card">
        <h3>INT 10h video BIOS</h3>
        <p>Extended video BIOS calls, rendering path notes, and how software reaches the QX-11 display hardware.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/INT10.md">Open INT10.md</a>
      </div>
    </div>
  </section>

  <section class="qx-section">
    <h2>Storage and I/O</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>HD-10 hard disk interface</h3>
        <p>Port 80h/81h/82h protocol, 6-byte CDBs, status phases, READ/WRITE behavior, and emulator lessons.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Hard%20Drive%20access%20EPSON%20HD-10.md">Open HD-10 notes</a>
      </div>
      <div class="qx-card">
        <h3>Floppy booting</h3>
        <p>Bootable disk notes, BIOS expectations, and real-hardware floppy behavior.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/qx11_floppy_boot.md">Open qx11_floppy_boot.md</a>
      </div>
      <div class="qx-card">
        <h3>Keyboard</h3>
        <p>Keyboard cable and signal notes, including QX-11 connector differences from related Epson systems.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/qx11_keyboard.md">Open qx11_keyboard.md</a>
      </div>
      <div class="qx-card">
        <h3>Joystick ports</h3>
        <p>Atari-style joystick compatibility notes and QX-11/QC-11 joystick references.</p>
        <a href="joystick.html">Open joystick page</a>
      </div>
    </div>
  </section>
</div>
