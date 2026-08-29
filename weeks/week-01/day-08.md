# Day 08 — The Board Wakes Up

**Week:** 01 · **Date:** 2026-08-29 · **Hours:** ~6.5

Today is August 29, 2026. According to the original roadmap schedule drawn up over a week ago, today was the target date for the physical hardware phase to officially begin. Week 00 was all theory, architecture records, and mental models; today, the project made contact with silicon, copper traces, and live current. 

Sitting down at my desk with the bare Radxa ROCK 3C, a serial debug cable, and a freshly unpacked microSD card was equal parts exhilarating and nerve-wracking. 

## What I actually did

I broke today’s bring-up session into four rigorous, sequential steps: thermal prep, serial instrumentation, OS flashing, and first-power capture.

### 1. Thermal Preparation (Cooling Before Current)
The roadmap’s first rule for Week 1 is non-negotiable: *cooling goes on before the board ever sees power.* Modern ARM SoCs, even power-efficient Cortex-A55 clusters like the RK3566, experience rapid localized thermal spikes during unthrottled boot sequences and rootfs expansion.

I cleaned the plastic packaging residue off the RK3566 package using a drop of 99% isopropyl alcohol on a lint-free swab. Once the die surface dried completely, I peeled the blue backing off the pre-applied 3M 8810 thermally conductive adhesive tape on the black grooved aluminum heatsink. Because thermal adhesive tape is strictly one-shot (repositioning introduces trapped micro-air bubbles that drastically degrade thermal transfer), I aligned the heatsink square with the SoC perimeter and applied firm, steady downward thumb pressure for forty-five seconds. 

### 2. Wiring the Serial Ground Truth (UART2)
Before plugging in Ethernet or power, I wired up the hardware debug line. Relying on network discovery or HDMI during initial bring-up is flying blind; if the bootloader fails to initialize DDR timing or the kernel panics on rootfs mount, a serial console is the only tool that tells you why.

Using the pinout map I documented in `hardware/rock-3c-specifications.md`, I connected my Silicon Labs CP2102 USB-to-UART adapter to the ROCK 3C’s 40-pin GPIO header:
- **GND** connected to **Pin 6** (Ground).
- Adapter **RXD** connected to **Pin 8** (`GPIO_A0` / `UART2_TXD_M0`).
- Adapter **TXD** connected to **Pin 10** (`GPIO_A1` / `UART2_RXD_M0`).
- **VCC Left Disconnected:** I double-checked with a multimeter that no 3.3V/5V power pin was bridged to avoid back-powering the board through the USB bridge.

I plugged the CP2102 into my workstation, verified that `/dev/ttyUSB0` appeared in `dmesg`, and launched our serial console script:
```bash
./scripts/serial-console.sh
```
The terminal opened at **1,500,000 baud (8-N-1)**, waiting quietly on a blank screen for the first serial byte.

### 3. Flashing Armbian Bookworm (Linux 6.6 LTS Mainline)
I inserted the SanDisk Max Endurance 64GB card into my workstation’s card reader. Using our `scripts/flash-sd.sh` utility with `bmaptool` acceleration, I flashed the Armbian 24.5 Bookworm headless image (built on the mainline Linux 6.6.x kernel track).

The flashing script wrote the 2.4GB uncompressed raw disk image, executed a hardware `sync` to flush write buffers, and verified block checksums in just under 45 seconds. I ejected the card, slotted it into the ROCK 3C’s spring-loaded microSD tray, and plugged in a Cat6 Ethernet cable connected directly to my gigabit switch.

### 4. The First Power-Up
With `picocom` listening on the serial line, I plugged the dedicated 5V/3A USB-C power supply into the board.

Within 200 milliseconds, the serial console erupted with life:

```text
DDR Version V1.10 20210810
In
LPDDR4 X-PHY Version V1.05 20210729
channel 0
CS0 BW: 32 Col: 10 Bk: 8 CS0 Row: 16 CS: 1 Die BW: 16 Size: 4096MB
change to: 1056MHz
...
U-Boot SPL 2024.01-armbian (Aug 15 2024 - 10:22:15 +0000)
Trying to boot from MMC1
Card did not respond to voltage select! : -110
Trying to boot from MMC0
...
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x412fd050]
[    0.000000] Linux version 6.6.31-current-rockchip64 (root@armbian)
[    0.000000] Machine model: Radxa ROCK 3 Model C
...
[    4.120512] rk_gmac-dwmac fe010000.ethernet eth0: Link is Up - 1Gbps/Full
[    6.852109] systemd[1]: Reached target Multi-User System.
```

Seeing the U-Boot SPL transition into the Linux 6.6 kernel, enumerate the 4096MB LPDDR4 memory pool, bring up the Realtek Gigabit PHY at 1000Mbps Full Duplex, and hit `Multi-User System` in 6.8 seconds was pure engineering joy. 

I completed the initial Armbian first-boot setup directly over the serial TTY: configured the initial root password, created the dedicated administrative user (`sdrive-admin`), and let Armbian execute its automatic root partition resize across the remaining 58GB of flash storage.

I captured the entire raw boot sequence into `docs/first-boot-dmesg.log` for future kernel regression comparisons.

## What confused me

During the very first three seconds of boot, I saw the following warning flash across U-Boot:
`Card did not respond to voltage select! : -110` followed by `Trying to boot from MMC0`.

My heart skipped a beat—I thought the SanDisk Max Endurance card had failed UHS-I voltage negotiation. After checking the Rockchip RK3566 technical reference manual, I realized that `MMC1` on the SoC corresponds to the unpopulated onboard eMMC connector. When U-Boot tries and fails to find an eMMC module at `MMC1`, it gracefully falls back to `MMC0` (the microSD card slot). It is completely normal behavior for a board booting from SD without an eMMC module attached.

The second minor headache was Ethernet link negotiation. When the kernel first initialized the `fe010000.ethernet` controller, the green link LED on the RJ45 jack blinked intermittently for about four seconds before stabilizing at a solid 1Gbps. It turned out to be standard Energy Efficient Ethernet (EEE) auto-negotiation between the Realtek RTL8211F PHY and my managed switch.

## Tomorrow

Tomorrow is Day 09: **First-Boot Hardening & Network Baseline**. We will log in over SSH for the first time, deploy our Ed25519 public key, completely disable SSH password authentication, configure a static DHCP reservation, and set up our custom systemd service.
