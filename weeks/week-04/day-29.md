# Day 29: The Automated Backbone — Cron, Monitoring, and Unattended Reliability

*September 20, 2026*

The stress test proved the appliance can handle sustained uploads without breaking. But proving a system works when you're watching it isn't the same as proving it works when you're not. A photo backup appliance runs 24/7. Nobody monitors it. Nobody restarts it. Nobody checks whether the backup ran last night. If something goes wrong at 3 AM — the SSD fills up, a container crashes and doesn't recover, PostgreSQL's WAL grows unbounded — you find out when your phone shows "backup failed" three days later, and by then the damage is done.

Today I built the automation layer that makes the appliance self-monitoring. Five cron jobs, a storage health monitor, and a log rotation policy. After today, the board doesn't need me to babysit it.

## The Cron Schedule

I designed five automated jobs, each running at a different frequency based on its importance and computational cost:

| Schedule | Job | Purpose |
|---|---|---|
| `0 3 * * *` | `sdrive-stack-backup.sh` | Nightly metadata backup at 3 AM |
| `0 */6 * * *` | `sdrive-storage-monitor.sh --quiet` | Storage health every 6 hours |
| `0 * * * *` | `sdrive-golden-signals.sh` | System health snapshot every hour |
| `*/15 * * * *` | `sdrive-container-health.sh` | Container liveness every 15 minutes |
| `0 4 * * 0` | `docker system prune -f` | Weekly cleanup on Sundays |

The timing is deliberate. Backups run at 3 AM because that's the lowest-activity window for a home appliance — nobody is uploading photos at 3 AM. The storage monitor runs every 6 hours because disk usage changes slowly (a few hundred megabytes per day, not per minute). Container health checks run every 15 minutes because a crashed container should be detected within a quarter hour, not a quarter day.

I installed the crontab:

```bash
root@sdrive:~# mkdir -p /var/log/sdrive
root@sdrive:~# cp config/cron/sdrive-crontab /etc/cron.d/sdrive
root@sdrive:~# chmod 644 /etc/cron.d/sdrive
root@sdrive:~# cp config/logrotate/sdrive /etc/logrotate.d/sdrive
```

Then verified it loaded:

```bash
root@sdrive:~# crontab -l
# ... (5 sdrive jobs visible)

root@sdrive:~# systemctl status cron
● cron.service - Regular background program processing daemon
     Loaded: loaded (/lib/systemd/system/cron.service; enabled)
     Active: active (running)
```

## The Storage Monitor

The storage health monitor (`sdrive-storage-monitor.sh`) is the most important new script. It checks six things:

### 1. SSD Capacity with Three-Tier Thresholds

```bash
DISK_WARN=70    # Start planning expansion
DISK_CRIT=85    # Stop non-essential writes, alert
DISK_FATAL=95   # Risk of filesystem corruption
```

This isn't arbitrary. At 70%, ext4's block allocator starts struggling to find contiguous free space, leading to fragmentation. At 85%, the risk of allocation failures during large writes increases. At 95%, the filesystem can't guarantee space for its own journal writes, which means a crash during a write could leave the filesystem in an inconsistent state.

I tested the thresholds by temporarily creating a large file:

```bash
root@sdrive:~# fallocate -l 300G /mnt/data/test-fill
root@sdrive:~# ./scripts/sdrive-storage-monitor.sh
[WARN] SSD capacity at 72% (312G used, 124G free) — plan expansion
=== Exit code: 1 ===

root@sdrive:~# fallocate -l 380G /mnt/data/test-fill
root@sdrive:~# ./scripts/sdrive-storage-monitor.sh
[CRIT] SSD capacity at 87% (392G used, 44G free) — stop non-essential writes
=== Exit code: 2 ===

root@sdrive:~# rm /mnt/data/test-fill
```

The exit codes matter. A cron wrapper could check `$?` and send a notification (email, webhook, or even a push notification to the admin's phone) when the exit code crosses a threshold. For now, the log output is sufficient — I'll add notifications in Week 06 when Tailscale is running.

### 2. Inode Usage

This is the sneaky one. ext4 allocates a fixed number of inodes at filesystem creation time. Each file consumes one inode. With Garage storing 5 objects per photo, a 100,000-photo library creates 500,000 files in the data volume, plus SQLite WAL files, PostgreSQL data files, and Docker overlay layers.

```bash
root@sdrive:~# df -i /mnt/data
Filesystem       Inodes   IUsed   IFree  IUse%
/dev/sda1       30531584   4218  30527366    1%
```

30.5 million inodes. At 500,000 files per 100,000 photos, we can store **6 million photos** before running out of inodes. Inode exhaustion is not a concern for this deployment.

### 3. SMART Health Monitoring

The script reads the SSD's SMART attributes for early warning of hardware degradation:

```bash
root@sdrive:~# ./scripts/sdrive-storage-monitor.sh
[OK] SMART: PASSED, reallocated=0, pending=0
```

Reallocated sectors indicate the SSD's controller has marked bad NAND cells and remapped them to spare cells. A count above zero isn't immediately fatal, but it means the drive is aging. Pending sectors mean the controller has detected potential issues but hasn't confirmed them yet. Either metric rising above zero triggers a warning in the storage monitor.

### 4. Backup Freshness

The monitor checks the timestamp of the most recent backup in `/mnt/data/backups/`. If the latest backup is more than 48 hours old, it triggers a warning. This catches the scenario where the backup cron silently failed — maybe the Docker daemon was being upgraded, or the alpine container used for tar couldn't be pulled.

```bash
root@sdrive:~# ./scripts/sdrive-storage-monitor.sh
[OK] Latest backup: 2h ago (/mnt/data/backups/20260920-030001)
```

## The First Automated Run

I waited for the cron schedule to fire and checked the logs:

```bash
# After the first hourly Golden Signals run:
root@sdrive:~# cat /var/log/sdrive/golden-signals.log
========================================
 sdrive — Four Golden Signals
 2026-09-20 10:00:01 IST
========================================
[LATENCY] Health endpoint response time:
  museum /health: 18ms
[TRAFFIC] ...
[ERRORS] ...
[SATURATION]
  Memory: 356 MB / 3788 MB (9%)
  Disk:   5.1G / 458G (1%)
  Load:   0.08 0.06 0.03
  CPU:    48°C

# After the first 15-minute container health check:
root@sdrive:~# cat /var/log/sdrive/container-health.log
========================================
 sdrive — Container Health Dashboard
 2026-09-20 10:15:01 IST
========================================
Containers: 3 running / 3 total
...
NAME                  STATE      HEALTH       RESTARTS  UPTIME
sdrive-stack-garage   running    healthy      0         48h 12m
sdrive-stack-museum   running    healthy      0         48h 12m
sdrive-stack-postgres running    healthy      0         48h 12m
```

The automation is working. Every 15 minutes, the container health is logged. Every hour, the Golden Signals are captured. Every 6 hours, the storage monitor runs its full check. Every night at 3 AM, the metadata volumes are backed up. Every Sunday, Docker prunes unused resources.

## Log Rotation

Unbounded logs are the #1 cause of disk exhaustion in unattended Linux systems. I've seen production servers die because `syslog` grew to 50 GB while nobody was watching. The logrotate configuration keeps sdrive's monitoring logs capped:

```
/var/log/sdrive/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
}
```

Seven days of logs, compressed after the first day. With five cron jobs generating approximately 2 KB per run, the maximum log footprint is:

| Job | Runs/day | Size/run | 7-day total |
|---|---|---|---|
| Golden Signals | 24 | ~500 B | 84 KB |
| Container Health | 96 | ~400 B | 269 KB |
| Storage Monitor | 4 | ~600 B | 17 KB |
| Backup | 1 | ~300 B | 2 KB |
| Docker Prune | 0.14 | ~200 B | < 1 KB |
| **Total** | | | **~372 KB** |

372 KB of monitoring logs per week. Compressed, that's under 100 KB. The monitoring infrastructure has essentially zero storage overhead.

## The Reliability Model

With automation in place, the appliance's unattended reliability model is:

```
Failure Scenario                    Detection Time    Recovery
──────────────────────────────────────────────────────────────────
Container crash                     < 15 min          Docker auto-restart (~3s)
SSD capacity > 70%                  < 6 hours         Log alert
SSD SMART degradation               < 6 hours         Log alert
Backup silently failed              < 48 hours        Log alert (freshness check)
Docker image/layer bloat            < 7 days          Weekly prune
Log directory bloat                 Never             Logrotate (7-day cap)
Power failure / reboot              Immediate         Docker restart policy + fstab
```

Every failure mode is either automatically recovered (container restarts, power recovery) or automatically detected (monitoring logs) within a bounded time window. The appliance doesn't need human intervention for any common failure scenario.

Tomorrow: the blob-level backup strategy using rsync, and the final storage architecture documentation.
