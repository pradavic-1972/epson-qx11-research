# Epson QX-11 Keyboard Cable: DIN-8 to Mini-DIN-8 Adapter

The Epson QX-11 uses an **8-pin mini-DIN** connector for the keyboard. This is different from the QX-10 and QX-16, which use the larger DIN-style keyboard connector.

Electrically, the QX-11 keyboard interface appears to use the **same signal assignments on the same pin numbers** as the QX-10/QX-16 keyboard connection. Because of that, I was able to build a **DIN-8 to mini-DIN-8 adapter cable** and use an Epson QX-16 keyboard with the QX-11.

The keyboard I tested is the [**Epson Q603A**](/photos/20250823_130528.jpg) keyboard, which is the same keyboard model used with the QX-11 and QX-16. The QX-11 could also use the compact [**Epson Q604A**](https://github.com/GigaBajcior/Epson_Q601A_aka_QX-11_aka_QC-11/blob/main/Photos/Keyboard/01.%20Keyboard.jpg) keyboard. The Japanese version of the system also had two Japanese JIS-layout keyboard options: a compact keyboard and an extended keyboard.

## QX-11 Keyboard Pinout

Signal names in this table are from the **computer / CPU side** of the connection.

| Pin | Signal | Notes |
|---:|---|---|
| 1 | RXD | Serial data received by the QX-11 from the keyboard |
| 2 | Clock | Keyboard clock line |
| 3 | +12 V | Keyboard power from the computer |
| 4 | TXD | Serial data transmitted by the QX-11 to the keyboard |
| 5 | Ground | Signal / power ground |
| 6 | Not used in this cable | Leave unconnected unless verified |
| 7 | Not used in this cable | Leave unconnected unless verified |
| 8 | Not used in this cable | Leave unconnected unless verified |

I measured the clock line with an oscilloscope. On my QX-11, the keyboard clock measured approximately **1.2 kHz**.

## Mini-DIN-8 Pin Numbering

Be careful with connector views. A male plug and a female socket are mirror images of each other. The diagram you use depends on whether you are looking into the computer's socket, looking at the front of the cable plug, or looking at the rear solder side of the plug.

### QX-11 mini-DIN-8 socket

This is the view looking directly into the **female mini-DIN-8 keyboard socket on the QX-11**.

```text
Front view of QX-11 female mini-DIN-8 socket
Looking into the computer's keyboard port

          key / notch
             ___
        .-----------.
       /             \
      |   8   7   6   |
      |    5   4   3  |
      |      2   1    |
       \             /
        '-----------'
```

Using this view of the QX-11 port:

```text
Pin 1 = RXD
Pin 2 = Clock
Pin 3 = +12 V
Pin 4 = TXD
Pin 5 = Ground
Pins 6, 7, 8 = unused by this adapter cable
```

### Male mini-DIN-8 cable plug, front view

This is the view looking at the **front of the male mini-DIN-8 plug**, the side that plugs into the QX-11.

```text
Front view of male mini-DIN-8 plug
Looking at the pins on the plug

          key / notch
             ___
        .-----------.
       /             \
      |   6   7   8   |
      |    3   4   5  |
      |      1   2    |
       \             /
        '-----------'
```

### Male mini-DIN-8 cable plug, solder side

When soldering a male plug, you are usually looking at the rear of the connector. That rear/solder view is mirrored compared with the front plug view.

```text
Rear / solder side of male mini-DIN-8 plug
Typical view while soldering the cable

          key / notch
             ___
        .-----------.
       /             \
      |   8   7   6   |
      |    5   4   3  |
      |      2   1    |
       \             /
        '-----------'
```

If your connector has molded pin numbers, trust the molded numbering and verify everything with a continuity meter before plugging it into the computer.

## Adapter Cable Wiring

Because the QX-11 and QX-16 keyboard connections use the same signal assignments by pin number, the adapter cable is wired straight-through by pin number/signals:

| QX-16 keyboard DIN-8 side | Signal | QX-11 mini-DIN-8 side |
|---:|---|---:|
| 1 | RXD | 1 |
| 2 | Clock | 2 |
| 3 | +12 V | 3 |
| 4 | TXD | 4 |
| 5 | Ground | 5 |
| 6 | Not used | Leave unconnected |
| 7 | Not used | Leave unconnected |
| 8 | Not used | Leave unconnected |

This is not wired as a serial null-modem cable. The important part is to keep the keyboard signals on the same pin numbers between the DIN-8 keyboard side and the mini-DIN-8 QX-11 side.

## Practical Build Notes

Use a cable with at least five conductors. A shielded cable is preferable, especially because the cable carries power, serial data, and a clock signal.

Before connecting the keyboard:

1. With the QX-11 powered off, verify continuity from each DIN pin to the matching mini-DIN pin.
2. Verify that there are no shorts between +12 V and ground.
3. With the keyboard disconnected, confirm that pin 3 on the QX-11 side is +12 V relative to pin 5.
4. Leave pins 6, 7, and 8 disconnected unless you have verified a reason to use them.

The most important pins to double-check are **pin 3 (+12 V)** and **pin 5 (ground)**. Accidentally swapping power and ground could damage the keyboard or the computer.

## Summary

For the Epson QX-11 keyboard adapter:

```text
DIN-8 keyboard side        mini-DIN-8 QX-11 side
-------------------        ---------------------
Pin 1  RXD          ----->  Pin 1  RXD
Pin 2  Clock        ----->  Pin 2  Clock
Pin 3  +12 V        ----->  Pin 3  +12 V
Pin 4  TXD          ----->  Pin 4  TXD
Pin 5  Ground       ----->  Pin 5  Ground
Pins 6-8            ----->  Not connected
```

This adapter allowed me to connect an **Epson Q603A** keyboard from a QX-16 to the **Epson QX-11** mini-DIN keyboard port.
