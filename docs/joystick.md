# 🎮 QC-11 / QX-11 Joystick Port Overview

This page documents technical findings about the joystick ports on the Epson QC-11 / QX-11, based on external research and visual inspection.

---

## 🧩 Summary of External Research

A detailed analysis of the QC-11 joystick ports was published by KTJ Dragon in Japanese:

🔗 [Original Article (Japanese)](https://ktjdragon.com/nb/misc/atari_qc11)  
📅 Accessed: August 2025  
🖋️ Author: KTJ Dragon

The article explores the compatibility of the QC-11 joystick ports with standard **Atari-style 9-pin joystick controllers**, as well as the internal signal handling.

### 📝 Key Points Summarized

- The QC-11 appears to support **two joystick ports**, accessible via DE-9 connectors on the front.
- These ports match the **Atari joystick wiring standard**, similar to the MSX system.
- Signals are processed by dedicated I/O ICs, which scan pin status using polling via MS-DOS software.
- The joystick functionality was intended for educational software and simple games (e.g., "Flappy").

---

## 📜 Credit & License

This information is based on KTJ Dragon’s article shared under publicly accessible web terms.  
Please visit their site for the full article and any updates:  
👉 [https://ktjdragon.com/nb/misc/atari_qc11](https://ktjdragon.com/nb/misc/atari_qc11)


