# Epson QX-11 Research Archive

This repository documents the technical details, discoveries, ROM dumps, schematics, and experimental work related to the **Epson QX-11** computer, also known in Japan as the **QC-11** and in Latin America (Venezuela) as the **Abacus**.

The QX-11 is a little-known MS-DOS-compatible system produced by Epson in the early 1980s, featuring a unique architecture, proprietary video and floppy systems, and a ROM cartridge slot used primarily for kanji fonts or application software.

---

## 🧠 Purpose of This Project

This archive aims to:

- Preserve knowledge about the QX-11, its hardware, and firmware
- Reverse-engineer undocumented components like the **GAFDDC** floppy gate array
- Share ROM dumps and tools for analysis or emulation
- Provide schematics and documentation for modern upgrades and repairs
- Assist other retrocomputing enthusiasts in understanding and working with this rare system

---

## 📁 Repository Structure

```plaintext
epson-qx11-research/
├── README.md               # This file
├── /photos/                # High-resolution photos of boards and internals
├── /roms/                  # System ROM and cartridge ROM dumps (BIN format)
├── /schematics/            # PDF and KiCad files for subsystems
├── /experiments/           # RAM expansions, Pico-based video card, PSU mods
├── /disassembly/           # Disassembled ROM code and memory maps
├── LICENSE                 # MIT License (for code/hardware files)
└── LICENSE-CC-BY.txt       # Creative Commons License (for media & docs)
```

---

## 🛠️ Current Highlights

### ✅ ROM Dumps
- `system_rom_high.bin` and `system_rom_low.bin` – Original QX-11 MS-DOS 2.11 ROM
- `cartridge_flappy_game.bin` – Cartridge dump of the Flappy game

### ✅ Reverse Engineering
- GAFDDC to uPD765 FDC signal mapping
- Address decoding for ROM cartridge slot
- DRAM bank emulation and memory upgrades

### ✅ Experiments
- **RAM Expansion** up to 1MB using Raspberry Pi Pico
- **PSU Replacement** using modern switching supplies
- **Custom VGA Output** interfaced via GPIO (Pico-based)

---

## 📷 Gallery

See `/photos/` for high-res images of:
- QX-11 motherboard (front and back)
- GAFDDC chip and FDC region
- Power supply area with TL494s
- Expansion slots and video port

---

## 📚 Related Systems

This work relates to:
- Epson QX-10 and QX-16
- NEC µPD765 floppy controllers
- Early MS-DOS machines with cartridge support

---

## 📄 License

- 🧩 All **code** (scripts, tools, KiCad files) is licensed under the [MIT License](LICENSE).
- 📸 All **images**, **ROM dumps**, **text documentation**, and **diagrams** are licensed under the [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) license.

Please credit this repository when reusing content.

---

## 🙌 Contributions

Pull requests are welcome for:
- Additional photos or ROMs
- Hardware mods and writeups
- Documentation or translations

---

## 💾 Disclaimer

ROM dumps and photos are shared for **educational and preservation purposes only**. The copyright of any original software belongs to its respective owners.

---

## 🔗 External Links

- [Retrocomputing Wiki](https://wiki.retrocomputing.net/)
- [Datasheet: uPD765AC](https://archive.org/details/nec-upd765-datasheet)
- [GAFDDC Analysis (WIP)](LINK_TO_YOUR_WRITEUP_HERE)
