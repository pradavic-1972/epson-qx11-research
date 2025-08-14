# 🔩 QX-11 Integrated Circuit Inventory

This page lists all the integrated circuits (ICs) identified on the Epson QX-11 motherboard, based on direct inspection and documentation.

| Column Legend |
|---------------|
| **Part Number** – IC marking on the chip  
| **Manufacturer** – Chip maker or brand  
| **Function / Description** – Role in the system  
| **Package** – Physical chip format (e.g., DIP, QFP)  
| **Location / Notes** – Placement or additional info  

---

| Part Number                        | Description                                           |   Datasheet | QX-11 (Venus Board)   | QX-16 (APX Board)   | Equity I (Mars Board)   |
|:-----------------------------------|:------------------------------------------------------|------------:|:----------------------|:--------------------|:------------------------|
| GAVEMR (E01038EA)                  | Epson VEMR Gatearray                                  |         nan | YES                   | NO                  | nan                     |
| HM50256                            | RAM                                                   |         nan | YES                   | YES                 | NO                      |
| GAFDDC (E01037EA)                  | Epson Floopy Controller Gate Array                    |         nan | YES                   | YES                 | YES                     |
| HA16642MF                          | Hitachi Read and Write Circuit for FDD                |         [Download: HA16642MP Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/HA16642MP.pdf) | YES                   | NO                  | YES                     |
| GAVNIT (E01045EA)                  | Epson GAVNIT Gate Array (Memory Interrupt Handler ? ) |         nan | YES                   | ?                   | NO                      |
| GAVNIO (E01039EA)                  | Epson GAVNIO Gate array (I/O controller ? )           |         nan | YES                   | NO                  | NO                      |
| M27256 (EPSON M25140CA & M25141CA) | 32Kb EEPROM (64KB total ROM)                          |         nan | YES                   | YES                 | NO                      |
| 74HC373                            | Octal Transparent D-Type Latches                      |         [Download: SN74HC373 Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/sn74hc373.pdf) | YES                   | YES                 | YES                     |
| SN76489                            | Programmable Sound Generator                          |         [Download: SN76489 Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/SN76489.pdf) | YES                   | NO                  | NO                      |
| HD146818P                          | Realtime clock plur RAM                               |         nan | YES                   | YES                 | nan                     |
| 74ALS74                            | Dual Type Flip Flop                                   |         nan | YES                   | ?                   | ?                       |
| 40H004                             | Hex Inverter                                          |         nan | YES                   | nan                 | nan                     |
| 74HC27                             | Triple Input nor gates                                |         nan | YES                   | ?                   | ?                       |
| 74HC245                            | Octal bus transceiver                                 |         nan | YES                   | ?                   | ?                       |
| 74LS05                             | Hex inverter                                          |         nan | YES                   | ?                   | ?                       |
| SN74ALS02N                         | Quadruple NOR gates                                   |         nan | YES                   | ?                   | ?                       |
| 74HC00                             | Quad NAN gates                                        |         nan | YES                   | ?                   | ?                       |
| SN75189AN                          | Quadruple Line receivers                              |         [Download: SN75189 Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/sn75189.pdf) | YES                   | ?                   | ?                       |
| 74LS541                            | Octal buffer and line driver                          |         nan | YES                   | ?                   | ?                       |
| D765AC                             | Single/Double Density Floppy-Disk Controller          |         [Download: uPD765AC Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/UPD765B.PDF)| YES                   | YES                 | YES                     |
| MB3763                             | Bi-Directional motor driver                           |         nan | YES                   | ?                   | NO                      |
| IJM2903                            | Precision voltage comparator                          |         nan | YES                   | ?                   | NO                      |
| TL494C                             | PWM Controller                                        |         [Download: TL494 Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/tl494.pdf) | YES                   | ?                   | NO                      |
| TC4584BP                           | Hex Schmitt Trigger                                   |         nan | YES                   | ?                   | ?                       |
| SED9421C0B                         | CMOS DATA SEPARATOR FOR FDD                           |         [Download: SED9420CAC Datasheet (PDF)](https://github.com/pradavic-1972/epson-qx11-research/blob/main/Datasheets/SED9420CAC.PDF) | YES                   | YES                 | YES                     |
| KCC 16.000                         | Crystal                                               |         nan | YES                   | nan                 | nan                     |
| KCC 14.31818                       | Crystal                                               |         nan | YES                   | ?                   | ?                       |
| 74LS188N                           | Line transmitter 300kbp RS-232                        |         nan | YES                   | ?                   | ?                       |
| GAVDP (E02032EA)                   | Gate Array Video Display Processor ?                  |         nan | YES                   | NO                  | NO                      |
| HM48416                            | 4-bit Dynamic RAM (48KB VRAM)                         |         nan | YES                   | ?                   | ?                       |

---

📘 This list is subject to revision as more chips are identified or verified.  
If you have corrections, please [open an issue](https://github.com/your-repo/issues) or submit a pull request.
