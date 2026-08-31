# Systemd Service Architecture & Self-Healing Watchdogs

In a headless home appliance that operates 24/7/365 with zero manual human maintenance, software processes must be resilient to network transient drops, memory leaks, and process deadlocks.

This document details the service isolation model, sandboxing directives, and self-healing watchdog architecture utilized on the `sdrive` single-board computer.

---

## 1. The Principle of Process Isolation & Sandboxing

Traditional Linux system administration frequently runs background services as `root` without filesystem or capability restrictions. A single buffer overflow in a daemon can lead to full host compromise.

On `sdrive`, all custom daemons and background services (`sdrive-health-watchdog`, `sdrive-network-watchdog`, `garage`, `museum`) enforce strict systemd sandboxing:

```ini
# Core Security Directives in /etc/systemd/system/*.service
[Service]
ProtectSystem=strict        # Mounts /usr, /boot, /etc as read-only
ProtectHome=yes             # Denies access to /home and /root
PrivateTmp=yes              # Assigns isolated, private /tmp namespace
ProtectKernelTunables=yes   # Denies modification of /proc/sys, /sys
ProtectKernelModules=yes    # Denies loading/unloading kernel modules
ProtectControlGroups=yes    # Denies modification of cgroup hierarchies
NoNewPrivileges=yes         # Prevents setuid binary privilege escalation
MemoryMax=64M               # Enforces hard OOM ceiling per service
CPUQuota=5%                 # Caps maximum CPU utilization
```

---

## 2. Watchdog Daemons & Self-Healing Loops

`sdrive` implements two complementary tiers of automated health recovery:

### Tier 1: Hardware & Thermal Telemetry (`sdrive-health-watchdog.service`)
- Continuously polls `/sys/class/thermal/thermal_zone0/temp` and `/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq`.
- Emits structured JSON telemetry to `/var/log/sdrive-health.log`.
- Triggers syslog warnings if the SoC temperature rises above $75^\circ\text{C}$ or if root filesystem capacity exceeds $90\%$.

### Tier 2: Network Liveness & Stack Reset (`sdrive-network-watchdog.service`)
- Periodically pings the local default gateway and external DNS endpoints.
- If connectivity fails for 3 consecutive intervals (90 seconds), the daemon logs a critical event and triggers an automated restart of the physical networking stack and Tailscale daemon (`systemctl restart tailscaled`).
- Restores remote mesh connectivity automatically without requiring a physical power-cycle.
