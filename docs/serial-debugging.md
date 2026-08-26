# Serial Console Debugging Guide (UART on Rockchip RK3566)

When bringing up a headless embedded Linux appliance, relying on SSH or HDMI output during early boot is unreliable. If the bootloader crashes, the device tree file (`.dtb`) fails to parse, or the kernel panics before initializing the Ethernet PHY, you will receive zero network feedback.

The **Serial UART Console** is the ground truth of hardware bring-up.

---

## 1. Physical Wiring

You will need a standard **USB-to-UART serial bridge** (CP2102, FT232RL, or CH340G) supporting 3.3V logic levels.

```
+--------------------------+                 +----------------------------+
|  USB-to-UART Adapter     |                 |  Radxa ROCK 3C GPIO Header |
|                          |                 |                            |
|                     GND  |================>|  Pin 6 or Pin 9 (GND)      |
|                     RXD  |<================|  Pin 8 (UART2_TXD)         |
|                     TXD  |================>|  Pin 10 (UART2_RXD)        |
|                     3V3  |  (NOT CONNECTED)|  (DO NOT CONNECT VCC!)     |
|                     5V   |  (NOT CONNECTED)|  (DO NOT CONNECT VCC!)     |
+--------------------------+                 +----------------------------+
```

> [!CAUTION]
> **DO NOT CONNECT THE VCC (+3.3V or +5V) PIN** from your USB serial adapter to the board. The Radxa ROCK 3C receives power exclusively through its USB Type-C power input port. Connecting an external VCC rail from a PC USB port can cause back-powering, ground loops, and permanently damage the SoC.

---

## 2. Rockchip 1,500,000 Baud Rate Nuance

Most standard microcontrollers (like Arduino or ESP32) and Raspberry Pi boards operate their debug UART at `115,200` baud. 

**Rockchip SoCs (including the RK3566) standard U-Boot firmware defaults to 1,500,000 baud (1.5 Mbps).**

If you attempt to connect at `115200` baud, you will see garbled garbage characters during the first 3 seconds of boot (during U-Boot SPL and stage 2 loading).

### Connection Parameters:
- **Baud Rate:** `1500000` (1.5M)
- **Data Bits:** `8`
- **Parity:** `None`
- **Stop Bits:** `1`
- **Flow Control:** `None` (RTS/CTS off, XON/XOFF off)

---

## 3. Terminal Connection Commands

### On Linux / macOS (via `picocom`):
```bash
# Find the serial device node
ls -l /dev/ttyUSB* /dev/ttyACM*

# Connect with 1.5M baud
picocom -b 1500000 /dev/ttyUSB0
```
*To exit picocom:* Press `Ctrl+A`, then `Ctrl+X`.

### On Linux / macOS (via `minicom`):
```bash
minicom -D /dev/ttyUSB0 -b 1500000 -8 -N
```

### On Windows (via PowerShell / PuTTY):
1. Open Device Manager and verify your COM port (e.g., `COM3`).
2. Open PuTTY $\rightarrow$ Select **Serial** connection type.
3. Set **Serial line** to `COM3` and **Speed** to `1500000`.
4. Under `Connection -> Serial`, verify Data bits: 8, Stop bits: 1, Parity: None, Flow control: None.
5. Click **Open**.

---

## 4. Expected Boot Log Signatures

When power is applied to the board, you should immediately observe the following boot stages across the serial stream:

```text
DDR Version V1.10 20210810
In
LPDDR4 X-PHY Version V1.05 20210729
channel 0
CS0 BW: 32 Col: 10 Bk: 8 CS0 Row: 16 CS: 1 Die BW: 16 Size: 4096MB
change to: 1056MHz
...
U-Boot SPL 2024.01 (Armbian)
Trying to boot from MMC1
Card did not respond to voltage select! : -110
Trying to boot from MMC0
...
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x412fd050]
[    0.000000] Linux version 6.6.x-rockchip64 (armbian@builder)
[    0.000000] Machine model: Radxa ROCK 3 Model C
...
[  OK  ] Started OpenBSD Secure Shell server.
[  OK  ] Reached target Multi-User System.
```
