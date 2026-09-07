# Day 17: Logs as the Primary Signal and the Four Golden Signals

*September 7, 2026*

Sunday. I made tea, sat down at the desk, and stared at the ROCK 3C for a long minute. The board has been online for over a week now. Armbian's uptime counter reads eight days, fourteen hours. Not a single crash, not a single kernel panic, not a single OOM kill. But here's the uncomfortable truth: I only know that because I've been watching it. If I walked away for a month and came back to a dead board, how would I figure out what happened?

The answer is logs. And today I'm going to learn to read them properly.

Linux has a unified logging daemon called `journald`, part of the `systemd` ecosystem. Every service, every kernel message, every authentication attempt, every cron job — they all feed into a single binary journal stored in `/var/log/journal/` (or on Armbian's ZRAM tmpfs at `/var/log.hdd/`). The tool to query this journal is `journalctl`, and learning to wield it fluently is the difference between diagnosing a failure in thirty seconds and staring at a dead terminal for three hours.

I started with the most basic query: what happened recently?

```bash
root@sdrive:~# journalctl --since "1 hour ago" --no-pager | tail -20
Sep 07 10:42:01 sdrive systemd[1]: Starting Cleanup of Temporary Directories...
Sep 07 10:42:01 sdrive systemd[1]: systemd-tmpfiles-clean.service: Deactivated successfully.
Sep 07 10:42:01 sdrive systemd[1]: Finished Cleanup of Temporary Directories.
Sep 07 10:45:00 sdrive sdrive-health-watchdog[1204]: {"timestamp":"2026-09-07T10:45:00+05:30","cpu_temp_c":47.2,"cpu_freq_mhz":1416,"mem_used_pct":14.3,"disk_used_pct":22.1}
Sep 07 10:50:00 sdrive sdrive-health-watchdog[1204]: {"timestamp":"2026-09-07T10:50:00+05:30","cpu_temp_c":47.1,"cpu_freq_mhz":408,"mem_used_pct":14.2,"disk_used_pct":22.1}
Sep 07 10:55:00 sdrive sdrive-health-watchdog[1204]: {"timestamp":"2026-09-07T10:55:00+05:30","cpu_temp_c":46.8,"cpu_freq_mhz":408,"mem_used_pct":14.3,"disk_used_pct":22.1}
```

There it is. Our health watchdog from Week 01, dutifully emitting structured JSON telemetry every five minutes. The CPU frequency oscillates between 408 MHz (idle governor) and 1416 MHz (load). Temperature is holding steady at 47°C. Memory at 14%. Disk at 22%. The board is bored.

But the real power of `journalctl` isn't in reading recent logs — it's in filtering. Every journal entry is tagged with metadata: the unit name, the priority level, the process ID, the boot session. You can slice the journal along any of these dimensions.

```bash
# Show only SSH authentication events
root@sdrive:~# journalctl -u ssh --since "24 hours ago" --no-pager
Sep 06 21:14:02 sdrive sshd[4821]: Accepted publickey for root from 192.168.1.100 port 52341 ssh2: ED25519 SHA256:...
Sep 06 21:14:02 sdrive sshd[4821]: pam_unix(sshd:session): session opened for user root(uid=0) by root(uid=0)
Sep 07 10:02:14 sdrive sshd[5102]: Accepted publickey for root from 192.168.1.100 port 53892 ssh2: ED25519 SHA256:...
```

Two logins in the last 24 hours, both from my desktop, both via Ed25519 public key. No failed attempts. No password guessing. No brute force probes from the internet. The SSH hardening from Week 01 is holding — the board is invisible behind the router's NAT, and even if someone found it, password authentication is disabled entirely.

I wanted to see what the kernel itself has been saying:

```bash
root@sdrive:~# journalctl -k --since "24 hours ago" --no-pager | grep -i -E "error|warn|fail|panic|oom"
```

Empty. Not a single kernel error, warning, failure, panic, or out-of-memory event in 24 hours. This is what a healthy, well-configured embedded Linux system looks like. No runaway processes, no memory leaks, no I/O errors on the SD card.

But I don't want to rely on manually grepping logs to know the system is healthy. This is where the **Four Golden Signals** come in. Google's Site Reliability Engineering book defines four fundamental metrics that capture the health of any service:

1. **Latency** — How long does it take to serve a request?
2. **Traffic** — How many requests are we handling?
3. **Errors** — What fraction of requests fail?
4. **Saturation** — How close are we to resource exhaustion?

These four signals are the entire observability framework for the sdrive appliance. Everything else — CPU temperature, disk IOPS, network throughput — is implementation detail that feeds into one of these four categories. Let me map them to our system:

### Latency

For the sdrive appliance, "latency" means: how long does it take from the moment the phone sends an encrypted photo chunk to the moment the storage daemon acknowledges the write? In Week 03 when the stack is running, we'll measure this with `curl -v` timing breakdowns and `tcpdump` packet deltas. For now, our proxy metric is DNS resolution latency (8ms to Cloudflare) and TCP handshake time (0.89ms on LAN).

```bash
# Measure DNS latency as a proxy signal
root@sdrive:~# dig @1.1.1.1 ente.io +stats 2>&1 | grep "Query time"
;; Query time: 7 msec
```

### Traffic

"Traffic" for us is measured in bytes ingested per second and concurrent connections. Right now, traffic is effectively zero — no services are running. But the infrastructure to measure it is already in place:

```bash
# Current network counters
root@sdrive:~# cat /proc/net/dev | grep eth0
  eth0: 847291632  612840    0    0    0     0          0       0  42819476  301247    0    0    0     0       0          0

# Bytes received: 847 MB, Bytes transmitted: 42 MB (over 8 days uptime)
# That's mostly SSH sessions and apt updates
```

### Errors

Error rate is the fraction of operations that fail. For networking, we track this with interface error counters:

```bash
root@sdrive:~# ip -s link show eth0 | grep -A 1 "RX errors"
    RX errors: 0  dropped: 0  overruns: 0  frame: 0
    TX errors: 0  dropped: 0  carrier: 0  collisions: 0
```

Zero errors across every category. Zero drops. Zero collisions. The RTL8211F PHY and the Cat5e cabling are performing flawlessly. When the Garage storage daemon starts handling thousands of concurrent S3 PUT requests in Week 05, these counters will be our canary. A non-zero drop count means the kernel's network buffer is overflowing, and we need to tune `net.core.rmem_max` or `net.core.netdev_max_backlog` in sysctl.

### Saturation

Saturation answers: how full is the system? For our appliance, the critical saturation signals are memory pressure, disk capacity, and CPU utilization:

```bash
root@sdrive:~# free -h
               total        used        free      shared  buff/cache   available
Mem:           3.7Gi       142Mi       3.2Gi       8.0Mi       370Mi       3.5Gi
Swap:          1.9Gi          0B       1.9Gi

root@sdrive:~# df -h /
Filesystem      Size  Used Avail Use%  Mounted on
/dev/mmcblk0p1   58G   13G   43G  23%  /

root@sdrive:~# uptime
 11:02:14 up 8 days, 14:22,  1 user,  load average: 0.08, 0.03, 0.01
```

142 MB of RAM used out of 3.7 GB. 23% disk. Load average of 0.08. The system is running at approximately 4% of its total capacity. We have enormous headroom for the container stack — but that headroom will evaporate quickly once PostgreSQL, Garage, and `museum` are all running simultaneously. I'm setting a mental tripwire: if memory usage exceeds 60% or disk exceeds 70%, we need to investigate before adding more services.

I wrote a quick `journalctl` filter that combines all four golden signals into a single diagnostic snapshot — something I can run in thirty seconds when something feels wrong:

```bash
root@sdrive:~# cat > /usr/local/bin/sdrive-golden-signals << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "========================================"
echo " sdrive — Golden Signals Snapshot"
echo " $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================"

echo -e "\n[LATENCY] DNS resolution to Cloudflare:"
dig @1.1.1.1 ente.io +stats 2>&1 | grep "Query time"

echo -e "\n[TRAFFIC] Network counters (eth0):"
RX=$(cat /sys/class/net/eth0/statistics/rx_bytes)
TX=$(cat /sys/class/net/eth0/statistics/tx_bytes)
printf "  RX: %s MB  TX: %s MB\n" "$((RX / 1048576))" "$((TX / 1048576))"

echo -e "\n[ERRORS] Interface error counters:"
ip -s link show eth0 | grep -A 1 "RX errors"

echo -e "\n[SATURATION] Resource utilization:"
printf "  Memory: %s\n" "$(free -h | awk '/^Mem:/{printf "%s / %s (%s used)", $3, $2, $3/$2*100"%"}')"
printf "  Disk:   %s\n" "$(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"
printf "  Load:   %s\n" "$(cut -d' ' -f1-3 /proc/loadavg)"
printf "  Uptime: %s\n" "$(uptime -p)"

echo -e "\n[JOURNAL] Last 5 errors/warnings:"
journalctl -p warning --since "24 hours ago" --no-pager -q | tail -5 || echo "  (none)"

echo -e "\n========================================"
EOF
chmod +x /usr/local/bin/sdrive-golden-signals
```

Now I can run `sdrive-golden-signals` from any SSH session and get a complete health check in under two seconds. Latency, traffic, errors, saturation, and the last five journal warnings. This is the kind of operational tooling that separates a hobby project from a production appliance.

The final lesson of the day was about log retention. Armbian runs journald with storage on ZRAM — a compressed RAM disk. This means journal entries survive across service restarts but are lost on reboot. For a production appliance that might crash and reboot, we need persistent journal storage:

```bash
root@sdrive:~# mkdir -p /var/log/journal
root@sdrive:~# systemd-tmpfiles --create --prefix /var/log/journal
root@sdrive:~# systemctl restart systemd-journald

# Verify persistent storage is active
root@sdrive:~# journalctl --disk-usage
Archived and active journals take up 24.1M in the file system.
```

Now journal entries survive reboots. When the board crashes at 3 AM in Week 08, I'll be able to read the exact sequence of events that led to the failure — even if the crash was a kernel panic that prevented graceful shutdown. The journal is written with `fsync` semantics, so everything up to the last few seconds before power loss is preserved.

I also capped the journal size to prevent it from eating the SD card over months of operation:

```bash
root@sdrive:~# cat /etc/systemd/journald.conf.d/01-sdrive-caps.conf
[Journal]
SystemMaxUse=100M
SystemKeepFree=500M
MaxRetentionSec=30day
Compress=yes
```

One hundred megabytes maximum. Thirty days retention. Compressed. This is the log rotation strategy for a 64GB SD card — generous enough to preserve a month of operational history, aggressive enough to never threaten available storage.

Today I learned that observability isn't about dashboards or fancy monitoring tools. It's about knowing which four numbers to check, knowing where to find them, and having a script that shows them to you in two seconds flat. The Golden Signals framework is now burned into this machine — and into my thinking. Every service we deploy from this point forward will be evaluated against these four dimensions: how fast, how much, how broken, and how full.

Tomorrow we circle back to the physical layer one last time: documenting the complete network architecture diagram and writing the formal Week 02 reference guide that ties all six days of learning together.
