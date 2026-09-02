# Linux Process Memory Model & Cgroups v2 on Embedded ARM

Understanding how the Linux kernel allocates, accounts, and reclaims memory is critical for operating multi-daemon applications on a 4GB single-board computer without risking Out-Of-Memory (OOM) killer terminations.

---

## 1. Virtual Memory (VSZ) vs. Resident Set Size (RSS)

When inspecting processes via `top` or `ps`, developers often confuse memory metrics:

- **VSZ (Virtual Memory Size):** The total address space a process has mapped, including allocated heap, loaded shared libraries, and memory-mapped files (`mmap`). A Go runtime or Rust binary may map 1GB of virtual address space, but this does *not* represent physical RAM consumption.
- **RSS (Resident Set Size):** The actual number of physical RAM pages (4KB pages) currently held in hardware memory for that process. This is the true metric of memory consumption.
- **SHR (Shared Memory):** Memory shared with other processes (e.g., `glibc` libraries, shared memory segments).

```
Target RSS Budget for sdrive Appliance (4GB Total Pool):
[ Linux Kernel + Systemd: ~120MB ]
[ PostgreSQL 16 Daemon:   ~60MB  ]
[ Museum Go Backend:      ~40MB  ]
[ Garage Rust S3 Daemon:  ~50MB  ]
[ Tailscale WireGuard:    ~30MB  ]
----------------------------------
Total Core System RSS:    ~300MB
Available for Page Cache: ~3.7GB
```

---

## 2. Cgroups v2 & Systemd Resource Limits

`sdrive` utilizes **Linux Control Groups (cgroups v2)** via systemd service units to enforce hard resource boundaries.

### Key Sandboxing Parameters:
- **`MemoryMax=512M`**: Enforces an absolute upper bound on physical memory. If a service exceeds this limit, the Linux kernel invokes the OOM killer *strictly within that cgroup*, killing the rogue child process without destabilizing the host OS.
- **`MemoryHigh=384M`**: Throttles process allocation and triggers aggressive asynchronous page reclaim before hitting `MemoryMax`.
- **`CPUQuota=50%`**: Restricts the service to a maximum of 50% of a single CPU core during background maintenance tasks.

---

## 3. OOM Score Adjustments (`oom_score_adj`)

When physical RAM and ZRAM swap are completely exhausted, the Linux kernel OOM killer scans processes and computes an `oom_score` (ranging from 0 to 1000) based on memory usage percentage.

To ensure critical system services (like OpenSSH and Tailscale) are never killed before user daemons:
- **OpenSSH Daemon (`sshd`):** `oom_score_adj = -1000` (Immune to OOM kill).
- **Tailscale Daemon (`tailscaled`):** `oom_score_adj = -500` (Protected remote access).
- **User Upload Handlers:** `oom_score_adj = 200` (Killed first to protect kernel integrity).
