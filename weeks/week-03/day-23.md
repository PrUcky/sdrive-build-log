# Day 23: The First Account, the Trial Trap, and Locking Down the Stack

*September 13, 2026*

The sdrive stack has been running for two days now. PostgreSQL, Garage, and Museum — three containers, all healthy, all communicating over Docker's bridge network. Today we cross the threshold from infrastructure to product: registering the first user account, promoting it to admin, and then hardening every container against the failure modes that kill appliances in long-running deployments.

## First Account Registration

The Ente mobile app has a hidden self-hosted configuration option. You tap the version number seven times on the login screen (the same pattern Android uses for Developer Options), and a server URL field appears. I pointed it at `http://192.168.1.150:8080` and registered a new account with a test email.

The app displayed a verification screen asking for a 6-digit code. Since SMTP is not configured — and deliberately so, because we don't want the appliance to depend on external mail services — the verification code is written to Museum's container log:

```bash
root@sdrive:~# docker logs sdrive-stack-museum-1 2>&1 | grep -i "verification"
2026-09-13 10:14:22 INFO  Sending verification code 847291 to testuser@sdrive.local
```

There it is: `847291`. I entered it in the app, and the account was created. The app connected, showed an empty gallery, and prompted me to start backing up photos. But we're not there yet — first, the account needs admin privileges and unlimited storage.

## The Trial Trap

This is the trap the roadmap explicitly warns about. A fresh self-hosted Ente account starts with a trial storage quota. The exact limit varies, but it's typically around 1 GB. If you don't remove this limit, everything seems fine during initial testing — a few test photos upload successfully. But when you try to import your real photo library in Week 05, the upload silently fails partway through with an error that looks like an upload bug, a network timeout, or a Garage disk issue. It's none of those. It's a storage quota.

I found the numeric user ID by querying PostgreSQL directly:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c "SELECT user_id, email FROM users;"
  1847291 | testuser@sdrive.local
```

User ID `1847291`. I added it to the `internal.admins` list in the board's local `museum.yaml`:

```yaml
internal:
  admins:
    - 1847291
```

Restarted Museum to pick up the config change:

```bash
root@sdrive:~# docker compose restart museum
[+] Restarting 1/1
 ✔ Container sdrive-stack-museum-1  Started   4.2s
```

Then removed the trial quota:

```bash
root@sdrive:~# docker exec sdrive-stack-museum-1 \
  museum admin update-subscription --no-limit --user-id 1847291
Subscription updated successfully.
```

Verified in the database:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c \
  "SELECT user_id, storage_limit FROM subscriptions WHERE user_id = 1847291;"
  1847291 | -1
```

`storage_limit = -1`. Unlimited. The trial trap is disarmed. This account can now store the full 458 GB capacity of the USB SSD without hitting an artificial ceiling.

## Container Hardening

With the first account proven, I spent the afternoon hardening the container stack. The roadmap says to timebox this to one day — it's hygiene, not differentiation — so I focused on the measures that matter most for a long-running embedded appliance.

### Memory Limits

The most dangerous failure mode on a 4 GB board is memory exhaustion. Without limits, a single container can consume all available RAM, triggering the kernel's OOM killer. The OOM killer doesn't politely ask which container to sacrifice — it kills the process with the highest memory score, which might be a completely innocent container, or even a host process like `sshd`.

I set explicit memory limits:

```yaml
postgres:  512 MB limit / 64 MB reservation
garage:    256 MB limit / 32 MB reservation  
museum:    512 MB limit / 128 MB reservation
```

Total: 1,280 MB maximum. That leaves 2,508 MB for the kernel, page cache, and SSH. Generous headroom. The reservation values tell the Docker runtime how much memory to guarantee under contention — they prevent one container from starving another during burst workloads.

### no-new-privileges

Every container gets `security_opt: no-new-privileges:true`. This kernel-level flag prevents any process inside the container from gaining additional privileges through `setuid` binaries, `sudo`, or capability escalation. Even if an attacker achieves remote code execution inside Museum (via a Go deserialization bug, for example), they cannot escalate to root within the container, and the container itself is already running with a restricted capability set.

### Read-Only Root Filesystem

Garage and Museum now run with `read_only: true`. Their container root filesystem is mounted read-only — no process can write to the image layers. Any transient writes (temp files, Unix sockets) go to a size-capped `tmpfs` mount. This blocks the most common post-exploitation technique: dropping a persistent backdoor into the container's filesystem.

PostgreSQL can't use a read-only rootfs because it needs to write to `/var/run/postgresql/` for its Unix socket. This is a known limitation of the official Postgres Docker image.

### Volume Backup Script

I wrote `scripts/sdrive-stack-backup.sh` to create timestamped tar.gz snapshots of the metadata volumes (Postgres data, Garage metadata, Museum data). It intentionally excludes `garage-data` — the encrypted photo blobs — because that can be multi-gigabytes. Blob backup strategy is a Week 04 problem.

The script:
- Uses a temporary Alpine container to read volumes (works even if the stack is stopped)
- Writes a `manifest.txt` with timestamp, hostname, and Docker version
- Retains only the last 5 backups, automatically pruning older ones
- Warns if the stack is running (crash-consistent but not app-consistent)

```bash
root@sdrive:~# ./scripts/sdrive-stack-backup.sh
======================================================================
 sdrive — Volume Backup
 2026-09-13 15:42:18 IST
======================================================================
[WARN] Stack is running. Backups are crash-consistent but not app-consistent.

Backing up: sdrive-stack_postgres-data
[OK] /mnt/data/backups/20260913-154218/postgres-data.tar.gz (2.1M)

Backing up: sdrive-stack_garage-meta
[OK] /mnt/data/backups/20260913-154218/garage-meta.tar.gz (184K)

Backing up: sdrive-stack_museum-data
[OK] /mnt/data/backups/20260913-154218/museum-data.tar.gz (12K)

======================================================================
 Backup complete: /mnt/data/backups/20260913-154218 (2.3M)
======================================================================
```

2.3 MB for the entire metadata state. That's the user account, the encryption key bundles, the album structure, the Garage cluster layout, and the subscription records. This is the data that's truly irreplaceable — photos can be re-uploaded, but if you lose the key bundles, the encrypted blobs become unrecoverable.

## Post-Hardening Verification

I ran the Golden Signals to verify nothing broke:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 352 MB / 3788 MB (9%)
  Disk:   15G / 58G (26%)
  Load:   0.18 0.14 0.09
  CPU:    49°C
```

Stable. The hardening added zero measurable overhead. The memory limits are ceilings, not allocations — they only engage if a container tries to exceed them.

I also verified the container health dashboard:

```bash
root@sdrive:~# sdrive-container-health
NAME                  STATE      HEALTH       RESTARTS  UPTIME
sdrive-stack-garage   running    healthy      0         2h 14m
sdrive-stack-museum   running    healthy      0         0h 48m
sdrive-stack-postgres running    healthy      0         2h 14m
```

Zero restart counts across all containers. Museum's uptime is shorter because we restarted it for the admin config change, but that was intentional.

The sdrive appliance now has its first registered user, unlimited storage, and a hardened container stack with memory limits, privilege restrictions, read-only filesystems, log rotation, and automated volume backups. The infrastructure work for Week 03 is essentially complete. Tomorrow and Sunday we'll do the Compose deep-read and the Week 03 retrospective.
