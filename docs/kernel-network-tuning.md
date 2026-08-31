# Linux Kernel & Network Buffer Tuning Guide (ARM64 / RK3566)

When operating high-throughput photo and video ingestion over encrypted WireGuard tunnels and Gigabit Ethernet on a resource-constrained single-board computer, default Linux kernel socket buffer parameters can artificially throttle network performance.

This document details the mathematical models and kernel parameters configured on the `sdrive` appliance.

---

## 1. Bandwidth-Delay Product (BDP) & Socket Buffer Math

The **Bandwidth-Delay Product** represents the maximum volume of unacknowledged in-flight data that can exist on a network path at any given millisecond:

$$\text{BDP} = \text{Link Bandwidth (bits/sec)} \times \text{Round-Trip Time (RTT in seconds)}$$

### Example Scenarios:

1. **Local Gigabit Home LAN:**
   - Bandwidth: $1\text{ Gbps} = 125\text{ MB/s}$
   - RTT: $0.5\text{ ms} = 0.0005\text{ s}$
   - $\text{BDP} = 125\text{ MB/s} \times 0.0005\text{ s} = 62.5\text{ KB}$

2. **Remote Cellular 5G (across city / coffee shop):**
   - Bandwidth: $100\text{ Mbps} = 12.5\text{ MB/s}$
   - RTT: $60\text{ ms} = 0.060\text{ s}$
   - $\text{BDP} = 12.5\text{ MB/s} \times 0.060\text{ s} = 750\text{ KB}$

3. **High-Latency Remote Cellular (Inter-state / Roaming):**
   - Bandwidth: $50\text{ Mbps} = 6.25\text{ MB/s}$
   - RTT: $180\text{ ms} = 0.180\text{ s}$
   - $\text{BDP} = 6.25\text{ MB/s} \times 0.180\text{ s} \approx 1.125\text{ MB}$

### Kernel Buffer Sizing:
If the Linux TCP receive buffer (`net.ipv4.tcp_rmem` max) is smaller than the BDP, the sender’s TCP congestion window (CWND) will stall waiting for ACKs, artificially capping upload throughput regardless of available bandwidth.

To guarantee that the ROCK 3C can absorb continuous high-bandwidth streams without TCP window exhaustion:
- `net.core.rmem_max = 16777216` (16MB maximum receive buffer)
- `net.core.wmem_max = 16777216` (16MB maximum send buffer)
- `net.ipv4.tcp_rmem = 4096 87380 16777216` (min, default, max)
- `net.ipv4.tcp_wmem = 4096 65536 16777216` (min, default, max)

---

## 2. CPU Frequency Scaling Governor (`schedutil`)

The Rockchip RK3566 SoC features dynamic voltage and frequency scaling (DVFS) managed by the Linux kernel `cpufreq` subsystem.

Available frequency steps on RK3566 Cortex-A55:
- `408 MHz` (Low power idle, ~1.95W board draw)
- `600 MHz`
- `816 MHz`
- `1104 MHz`
- `1416 MHz`
- `1800 MHz` (Maximum compute peak, ~4.35W board draw)

### Governor Selection: `schedutil`
We utilize the **`schedutil`** governor (`/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`). Unlike legacy `ondemand` or `conservative` governors that compute CPU load via periodic timer ticks, `schedutil` hooks directly into the Linux Completely Fair Scheduler (CFS) runqueue metrics (PELT — Per-Entity Load Tracking). 

When an S3 upload stream begins, `schedutil` instantly ramps CPU clock to 1.8GHz within microseconds, and immediately steps down to 408MHz the moment the transfer finishes, minimizing total energy consumption.

---

## 3. Network Interrupt Affinity & Backlog Queues

The Gigabit Ethernet MAC (`rk_gmac-dwmac`) generates hardware interrupts whenever frames arrive at the Realtek RTL8211F transceiver.

To prevent packet drops during burst uploads:
```text
# /etc/sysctl.d/99-sdrive-tuning.conf
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 5000
```
- **`netdev_max_backlog = 5000`**: Increases the maximum number of incoming packets queued on the network interface before being processed by the kernel protocol stack.
- **`somaxconn = 4096`**: Expands the listen queue for socket connections, ensuring multiple concurrent mobile clients never experience connection timeouts.
