# Radxa ROCK 3C — Hardware Specifications & Pinout

This document serves as the core technical reference for the Radxa ROCK 3C single-board computer utilized in the `sdrive` appliance.

---

## 1. System-on-Chip (SoC) Architecture

- **SoC Model:** Rockchip RK3566
- **CPU:** Quad-core ARM Cortex-A55 @ up to 1.8GHz (64-bit ARMv8.2-A architecture, 32KB L1 instruction cache, 32KB L1 data cache, 512KB unified L3 cache).
- **GPU:** ARM Mali-G52 2EE (Bifrost architecture, supports OpenGL ES 1.1/2.0/3.2, Vulkan 1.1, OpenCL 2.0). *Unused by sdrive headless stack.*
- **NPU:** 0.8 TOPS @ INT8. *Unused by sdrive zero-knowledge stack.*
- **System Memory:** 4GB LPDDR4 @ 2112 MT/s.

---

## 2. Storage & I/O Interfaces

- **MicroSD Slot:** Standard MicroSDXC slot supporting SD 3.0 (UHS-I SDR104 mode, up to 104 MB/s bus speed).
- **eMMC Socket:** High-speed eMMC 5.1 connector on the underside of the PCB.
- **M.2 Slot:** M.2 M-Key socket on underside (PCIe 2.1 x1 interface, theoretical maximum bandwidth of ~500 MB/s).
- **Networking:** Gigabit Ethernet RJ45 port driven by a Realtek RTL8211F transceiver supporting 10/100/1000 Mbps with Hardware Flow Control and IEEE 802.3az Energy Efficient Ethernet.
- **Wireless:** Onboard Wi-Fi 5 (802.11ac 1x1) and Bluetooth 5.0 (Realtek RTL8821CS). *Disabled in sdrive production build to minimize RF interference and security attack surface.*
- **USB Host Ports:**
  - 1x USB 3.0 Type-A (blue, up to 5Gbps, powered by RK3566 native USB 3.0 controller).
  - 1x USB 2.0 Type-A (white/black, 480Mbps).
  - 2x USB 2.0 Type-A (dual stack, 480Mbps).
- **Power Input:** USB Type-C port (fixed 5V input, minimum 3.0A recommended).

---

## 3. 40-Pin GPIO Header & Serial Debug Pinout

The Radxa ROCK 3C features a Raspberry Pi-compatible 40-pin GPIO expansion header (2.54mm pitch).

```
                            Radxa ROCK 3C GPIO Header
                                (Top-Down View)
                             +3.3V  [ 1] [ 2]  +5V Power
              (I2C2_SDA)    GPIO_A2  [ 3] [ 4]  +5V Power
              (I2C2_SCL)    GPIO_A3  [ 5] [ 6]  GND (Ground)
                            GPIO_A7  [ 7] [ 8]  GPIO_A0 (UART2_TXD_M0)  <-- Debug TX
                                GND  [ 9] [10]  GPIO_A1 (UART2_RXD_M0)  <-- Debug RX
                            GPIO_C6  [11] [12]  GPIO_B0
                            GPIO_C7  [13] [14]  GND
                            GPIO_D0  [15] [16]  GPIO_B1
                              +3.3V  [17] [18]  GPIO_B2
              (SPI3_MOSI)   GPIO_C0  [19] [20]  GND
              (SPI3_MISO)   GPIO_C1  [21] [22]  GPIO_B3
              (SPI3_CLK)    GPIO_C2  [23] [24]  GPIO_B4 (SPI3_CS0)
                                GND  [25] [26]  GPIO_B5 (SPI3_CS1)
              (I2C3_SDA)    GPIO_A4  [27] [28]  GPIO_A5 (I2C3_SCL)
                            GPIO_C4  [29] [30]  GND
                            GPIO_C5  [31] [32]  GPIO_B6
                            GPIO_D1  [33] [34]  GND
                            GPIO_D2  [35] [36]  GPIO_B7
                            GPIO_D3  [37] [38]  GPIO_C3
                                GND  [39] [40]  GPIO_D4
```

### Serial Debug UART Pins (UART2)
- **Pin 6 or Pin 9:** GND (Connect to USB-to-UART Adapter Ground)
- **Pin 8 (GPIO_A0):** UART2_TXD (Connect to USB-to-UART Adapter **RXD**)
- **Pin 10 (GPIO_A1):** UART2_RXD (Connect to USB-to-UART Adapter **TXD**)
- **Logic Level:** **3.3V TTL** (*Do NOT connect 5V TTL directly without level shifting!*)
- **Baud Rate:** **1,500,000 baud** (8-N-1, No Flow Control).
