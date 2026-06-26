---
title: Epson QX-11 Research Archive
layout: default
---

<link rel="stylesheet" href="{{ '/assets/css/site.css' | relative_url }}">

<div class="qx11-page">
  <section class="qx-hero">
    <div>
      <div class="qx-kicker">Reverse engineering · preservation · repair</div>
      <h1 class="qx-title">Epson QX-11 Research Archive</h1>
      <p class="qx-subtitle">
        Technical notes, ROM dumps, board photos, hardware discoveries, and emulator research for the Epson QX-11 — also known as the Japanese QC-11 and the Venezuelan Abacus.
      </p>
      <div class="qx-actions">
        <a class="qx-button primary" href="reverse-engineering.html">Start with reverse engineering</a>
        <a class="qx-button" href="photos.html">View hardware photos</a>
        <a class="qx-button" href="https://github.com/pradavic-1972/epson-qx11-research">Open repository</a>
      </div>
    </div>
    <div>
      <img src="https://raw.githubusercontent.com/pradavic-1972/epson-qx11-research/main/photos/QX11-Front.jpg" alt="Epson QX-11 front view">
    </div>
  </section>

  <section class="qx-section">
    <h2>What this project preserves</h2>
    <div class="qx-stat-grid">
      <div class="qx-stat"><strong>8088-class</strong><span>Early MS-DOS compatible architecture</span></div>
      <div class="qx-stat"><strong>QX-11 / QC-11</strong><span>Japanese, export, and Abacus variants</span></div>
      <div class="qx-stat"><strong>Gate arrays</strong><span>Video, memory, floppy, I/O, and interrupt logic</span></div>
      <div class="qx-stat"><strong>Real hardware</strong><span>Findings validated with repair, probing, and experiments</span></div>
    </div>
    <p>
      This archive focuses on the parts of the QX-11 that are poorly documented elsewhere: Epson custom gate arrays, ROM cartridge behavior, floppy and hard-disk interfaces, video memory layout, BIOS behavior, expansion ideas, and practical repair notes.
    </p>
  </section>

  <section class="qx-section">
    <h2>Featured research areas</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>GAVDP video system</h3>
        <p>Column-oriented VRAM, memory-mapped control registers, high-resolution display behavior, hardware scrolling, and QX-11 text rendering.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVDP.md">Read GAVDP notes</a>
      </div>
      <div class="qx-card">
        <h3>GAVEMR memory logic</h3>
        <p>DRAM configuration jumpers, ROM decoding, clock input tracing, memory mapping, and repair discoveries around the memory gate array.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/GAVEMR.md">Read GAVEMR notes</a>
      </div>
      <div class="qx-card">
        <h3>ROM cartridge boot path</h3>
        <p>Executable ROM modules, cartridge signatures, BIOS detection, DOS filesystem exposure, and boot-time integration.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Cartridge.md">Read cartridge notes</a>
      </div>
      <div class="qx-card">
        <h3>HD-10 hard disk protocol</h3>
        <p>Reverse-engineered Epson HD-10 behavior, SASI-like phases, strict BIOS status polling, and emulator implementation notes.</p>
        <a href="https://github.com/pradavic-1972/epson-qx11-research/blob/main/Reverse%20Engineering/Hard%20Drive%20access%20EPSON%20HD-10.md">Read HD-10 notes</a>
      </div>
    </div>
  </section>

  <section class="qx-section">
    <h2>Repository map</h2>
    <table class="qx-table">
      <thead>
        <tr><th>Area</th><th>What is inside</th></tr>
      </thead>
      <tbody>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/Reverse%20Engineering">Reverse Engineering</a></td><td>Gate-array notes, cartridge behavior, INT 10h work, keyboard, floppy booting, IVT grouping, and hard-disk analysis.</td></tr>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/roms">roms</a></td><td>Original and expanded ROM images for preservation and analysis.</td></tr>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/mame">mame</a></td><td>Emulation work and source-level experiments used to model QX-11 behavior.</td></tr>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/photos">photos</a></td><td>High-resolution photos of the machine, motherboard, chips, ports, power supply, and related hardware.</td></tr>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/Datasheets">Datasheets</a> / <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/ICs">ICs</a></td><td>Reference material for chips and board-level component identification.</td></tr>
        <tr><td><a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/software">software</a> / <a href="https://github.com/pradavic-1972/epson-qx11-research/tree/main/games">games</a></td><td>Software, tests, and game-related material useful for real hardware and emulation experiments.</td></tr>
      </tbody>
    </table>
  </section>

  <section class="qx-section">
    <h2>Important discoveries</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>Cartridge as a boot participant</h3>
        <p>The cartridge mechanism is more than a simple ROM disk. It can expose a DOS filesystem, participate in boot processing, and execute code during startup.</p>
      </div>
      <div class="qx-card">
        <h3>Video is not IBM CGA/MDA</h3>
        <p>The QX-11 writes directly into a proprietary, memory-mapped video system with a column-oriented VRAM layout and hidden control registers.</p>
      </div>
      <div class="qx-card">
        <h3>Hard disk protocol is Epson-specific</h3>
        <p>The HD-10 interface behaves like a host-driven, SASI-derived protocol exposed through Epson-specific I/O ports and strict BIOS phase checks.</p>
      </div>
      <div class="qx-card">
        <h3>Real hardware first</h3>
        <p>The notes prioritize measurements, ROM disassembly, logic analysis, oscilloscope work, repairs, and validation on original machines.</p>
      </div>
    </div>
  </section>

  <section class="qx-section">
    <h2>Start here</h2>
    <div class="qx-grid">
      <div class="qx-card">
        <h3>For hardware repair</h3>
        <p>Begin with the photo archive, IC inventory, GAVEMR notes, ROM expansion notes, and keyboard documentation.</p>
        <a href="getting-started.html#hardware-repair">Repair path</a>
      </div>
      <div class="qx-card">
        <h3>For emulation</h3>
        <p>Start with GAVDP, HD-10 protocol notes, INT 10h notes, floppy boot research, and MAME experiments.</p>
        <a href="getting-started.html#emulation">Emulation path</a>
      </div>
      <div class="qx-card">
        <h3>For ROM work</h3>
        <p>Review ROM dumps, cartridge boot behavior, ROM size selection, and expanded ROM experiments.</p>
        <a href="getting-started.html#rom-and-cartridge-work">ROM path</a>
      </div>
    </div>
  </section>

  <section class="qx-section">
    <h2>License and reuse</h2>
    <p>
      Code and schematics are published under the MIT License. Images, ROM dumps, text documentation, and diagrams are published under CC BY 4.0 unless otherwise noted. Please credit the repository when reusing material.
    </p>
    <div class="qx-callout">
      ROM dumps and original software material are shared for education, preservation, interoperability, and historical research. Copyright remains with the respective owners.
    </div>
  </section>
</div>
