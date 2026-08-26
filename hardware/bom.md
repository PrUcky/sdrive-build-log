# Bill of Materials (BOM) — sdrive Appliance

This document tracks the complete hardware bill of materials, cost breakdown, component datasheets, and sourcing links for the `sdrive` home photo backup appliance.

---

## 1. Prototype Revision (v1)

The prototype build prioritizes rapid iteration, low upfront cost, and standard off-the-shelf components.

| Item | Component Description | Manufacturer / Model | Interface / Form Factor | Power / Spec | Unit Cost (INR) | Unit Cost (USD) |
|---|---|---|---|---|---|---|
| **SBC** | Radxa ROCK 3C (4GB LPDDR4) | Radxa / RK3566 | Single-Board Computer | Quad Cortex-A55 @ 1.8GHz | ₹4,500 | $54.00 |
| **Boot Flash** | Max Endurance 64GB MicroSD | SanDisk / SDSQQVR-064G | MicroSDXC (UHS-I, U3, V30) | Up to 15,000 hrs write endurance | ₹1,100 | $13.20 |
| **Cooling** | Passive Anodized Aluminum Heatsink | Generic / 20x20x10mm | Thermal Adhesive (3M 8810) | Passive Convection ($\Delta T \approx 12^\circ\text{C}$) | ₹250 | $3.00 |
| **Power Supply** | Regulated 5V/3A DC Adapter | Raspberry Pi / Official 15W | USB Type-C Fixed 5.1V Rail | 15.3W Max, Low Ripple (<50mV) | ₹600 | $7.20 |
| **Ethernet** | Cat6 UTP Patch Cable (1.0m) | AmazonBasics | RJ-45 (1000BASE-T) | 250MHz Bandwidth | ₹150 | $1.80 |
| **Debug Tool** | CP2102 USB-to-UART Bridge | Silicon Labs / CP2102 | USB 2.0 to 3.3V TTL | 300 to 1.5M Baud Support | ₹250 | $3.00 |
| **Total v1 BOM** | — | — | — | — | **₹6,850** | **$82.20** |

---

## 2. Target Production Revision (v2)

The production build introduces hardened industrial storage, onboard eMMC durability, and a custom 3D-printed enclosure.

| Item | Component Description | Sourcing / Form Factor | Target Spec | Estimated Cost (USD) |
|---|---|---|---|---|
| **SBC** | Radxa ROCK 3C (4GB / 8GB) | Radxa Store / ALLNET | RK3566, eMMC socket, M.2 M-key | $55.00 |
| **OS Storage** | 32GB eMMC 5.1 Module | Radxa eMMC / Kingston | High-P/E Cycle pSLC/MLC Flash | $12.00 |
| **Blob Storage** | 500GB NVMe M.2 2280 SSD | WD Blue SN580 / Crucial P3 | PCIe 3.0 / PCIe 4.0 (x1 mode) | $42.00 |
| **Storage Adapter** | M.2 2230/2280 Extender Bracket | Custom PCB / Standoff | Secures 2280 drive beneath board | $4.00 |
| **Enclosure** | Custom 3D-Printed Chassis | PETG Filament / MJF Nylon | Optimized chimney convection airflow | $15.00 |
| **Total v2 BOM** | — | — | — | **~$128.00** |

---

## 3. Power Rail & Electrical Budget

- **Target Idle Power:** $1.8\text{W}$ to $2.5\text{W}$ ($5.1\text{V} @ 350\text{mA} - 490\text{mA}$).
- **Target Ingestion Power:** $4.2\text{W}$ to $5.5\text{W}$ (CPU @ 1.8GHz, GbE PHY active, NVMe write stream).
- **Absolute Peak Power:** $< 8.0\text{W}$ (Cold boot transient spike).
- **Annual Operating Electricity (24/7):**
  $$\text{Energy} = 2.5\text{W} \times 24\text{ h/day} \times 365\text{ days} = 21.9\text{ kWh/year}$$
  $$\text{Annual Cost (@ ₹8 / kWh)} \approx ₹175.20\text{ / year} \quad (\approx \$2.10\text{ USD/year})$$
