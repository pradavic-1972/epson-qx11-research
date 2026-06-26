---
title: Getting Started
layout: default
---

<link rel="stylesheet" href="{{ '/assets/css/site.css' | relative_url }}">

<div class="qx11-page">
  <div class="qx-kicker">Suggested reading paths</div>
  <h1>Getting Started with the QX-11 Archive</h1>
  <p>
    The repository is a working research archive. Use these paths depending on whether you are repairing a machine, building emulation support, or experimenting with ROMs and expansion hardware.
  </p>

  <section id="hardware-repair" class="qx-section">
    <h2>Hardware repair</h2>
    <ol class="qx-code-list">
      <li>Use <a href="photos.html">the photo archive</a> for board orientation and component locations.</li>
      <li>Check the <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/ICs">IC inventory</a> and <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/Datasheets">datasheets</a> for chip identification.</li>
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVEMR.md">GAVEMR.md</a> for memory, ROM decode, and DRAM jumper behavior.</li>
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/rom_expansion.md">rom_expansion.md</a> for ROM size and boot-ROM experiments.</li>
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/qx11_keyboard.md">qx11_keyboard.md</a> for keyboard connector notes.</li>
    </ol>
  </section>

  <section id="emulation" class="qx-section">
    <h2>Emulation work</h2>
    <ol class="qx-code-list">
      <li>Start with <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVDP.md">GAVDP.md</a> for video architecture.</li>
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/INT10.md">INT10.md</a> for BIOS video entry points and extended functions.</li>
      <li>Review <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Hard%20Drive%20access%20EPSON%20HD-10.md">HD-10 hard disk notes</a> for storage behavior.</li>
      <li>Browse <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/mame">the MAME folder</a> for implementation experiments.</li>
      <li>Use <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/roms">the ROM folder</a> as the firmware source for analysis and testing.</li>
    </ol>
  </section>

  <section id="rom-and-cartridge-work" class="qx-section">
    <h2>ROM and cartridge work</h2>
    <ol class="qx-code-list">
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Cartridge.md">Cartridge.md</a> for confirmed boot and filesystem behavior.</li>
      <li>Read <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/rom_expansion.md">rom_expansion.md</a> for ROM chip-size selection and expanded ROM experiments.</li>
      <li>Compare original and expanded images in <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/roms">roms</a>.</li>
      <li>Use the reverse-engineering notes to validate drive-letter mapping, signature bytes, and boot-time execution behavior.</li>
    </ol>
  </section>

  <section class="qx-section">
    <h2>Local safety note</h2>
    <div class="qx-callout">
      Vintage power supplies, CRT displays, batteries, and old storage devices can be hazardous. Document measurements, avoid unnecessary live probing, and preserve original ROMs before modifying or replacing hardware.
    </div>
  </section>
</div>
