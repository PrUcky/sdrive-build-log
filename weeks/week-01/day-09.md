# Day 09 — First Login and The First Service

**Week:** 01 · **Date:** 2026-08-30 · **Hours:** ~6.0

Yesterday, the board woke up on serial console. Today, the serial cable took a backseat and the network took over. The goal for Day 09 was to transition the Radxa ROCK 3C from a benchtop circuit board into a hardened, networked Linux server that I can administer seamlessly over SSH, complete with our first custom systemd service surviving a reboot.

## What I actually did

I started by finding the board’s newly leased IPv4 address on my home network. I opened my workstation terminal and ran `ip neighbor` alongside a quick scan of my router’s active DHCP table. The device appeared immediately at `192.168.1.150`, broadcasting its hostname `sdrive-node1` and its Realtek MAC address prefix.

Before doing anything else, I deployed our administrative cryptographic key. Back on Day 03, I had generated our dedicated Ed25519 keypair with 100 bcrypt KDF rounds (`~/.ssh/id_ed25519`). I pushed the public key to the board using `ssh-copy-id`:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub sdrive-admin@192.168.1.150
```

I tested the connection:
```bash
ssh sdrive-admin@192.168.1.150
```

The response was instantaneous. The terminal negotiated the Curve25519 key exchange, verified the signature, and dropped me straight into a clean Bash prompt without asking for a password. It felt remarkably fast—no password latency, no interactive keyboard-interactive delays.

### The SSH Lockdown
Next came the most critical security task of the bring-up phase: permanently locking down the OpenSSH daemon. Leaving password authentication enabled on any networked machine—even inside a home LAN—is an unacceptable liability. 

I authored a dedicated drop-in hardening configuration at `/etc/ssh/sshd_config.d/01-sdrive-hardening.conf`:
- **`PasswordAuthentication no`** and **`PermitEmptyPasswords no`**: Completely shuts down all password-based authentication vectors.
- **`PermitRootLogin no`**: Forces all administrative sessions to authenticate through the unprivileged `sdrive-admin` account, requiring explicit `sudo` elevation for root tasks.
- **`AuthenticationMethods publickey`**: Enforces cryptographic public key authentication as the sole accepted authentication mechanism.
- **Cryptographic Cipher Restrictions**: Restricted key exchanges strictly to `curve25519-sha256` and symmetric ciphers to `chacha20-poly1305@openssh.com` and `aes256-gcm@openssh.com`, completely disabling legacy Diffie-Hellman groups and CBC-mode ciphers.

Here, I adhered to the **Golden Rule of SSH Hardening**: *never disconnect your active session before testing.* I kept my primary SSH terminal and my hardware UART serial console active on my left monitor. On my right monitor, I reloaded the SSH daemon (`sudo systemctl reload ssh`) and opened a completely fresh terminal window to test logging in. 

I verified that attempting to log in without a key immediately failed with `Permission denied (publickey)`. Only then did I know the configuration was secure and working properly.

### Writing Our First Custom Systemd Service
With remote access secured, I moved on to the second major milestone: writing a custom `systemd` background service from scratch. 

Rather than creating a dummy "hello world" service, I wrote a functional hardware health telemetry watchdog: `sdrive-health-watchdog.sh`. The script runs in a continuous loop, querying the Linux kernel's `sysfs` thermal subsystem (`/sys/class/thermal/thermal_zone0/temp`), the CPU dynamic frequency scaling governor (`/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq`), and memory statistics from `/proc/meminfo`. Every 60 seconds, it writes a structured JSON telemetry line into `/var/log/sdrive-health.log` and emits a warning if the SoC temperature exceeds 75°C.

I encapsulated the script inside a production-grade systemd unit file at `/etc/systemd/system/sdrive-health-watchdog.service`, applying strict process sandboxing directives:
- `ProtectSystem=strict`: Mounts the entire OS filesystem as read-only to the service process.
- `ProtectHome=yes`: Denies the service access to `/root` and `/home`.
- `ReadWritePaths=/var/log`: Explicitly carves out write access only for the telemetry log file.
- `NoNewPrivileges=yes`: Prevents privilege escalation.
- `MemoryMax=64M` and `CPUQuota=5%`: Places hard resource caps on the watchdog.

I enabled and started the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sdrive-health-watchdog.service
```

I checked the live output via `journalctl -u sdrive-health-watchdog -f`:
```json
{"timestamp":"2026-08-30T03:12:00Z","soc_temp_c":36.4,"cpu_freq_mhz":408,"mem_used_pct":5,"mem_avail_mb":3812,"disk_used_pct":6}
```

The passive aluminum heatsink we mounted yesterday is doing its job flawlessly—the RK3566 SoC is idling at a cool 36.4°C while the quad cores downclock to 408MHz in power-saving mode.

Finally, I executed the ultimate validation test: `sudo reboot`. I watched the serial console stream the shutdown sequence, trigger hardware reset, reload U-Boot, decompress the Linux 6.6 kernel, and re-enter multi-user mode. Within 7.2 seconds of reboot, the watchdog service was active, running, and appending fresh JSON telemetry lines to `/var/log/sdrive-health.log`.

## What confused me

I encountered an interesting quirk with Armbian's default filesystem layout during the service implementation: Armbian mounts `/var/log` onto a compressed in-memory RAM disk using `zram` (`/dev/zram1`). 

When I first created the service, I wondered whether log entries written to `/var/log/sdrive-health.log` would vanish on every power cycle. After reading through Armbian's internal log management scripts, I discovered that Armbian uses `armbian-ramlog` to periodically sync in-memory logs to persistent storage (`/var/log.hdd`) on clean shutdown and at hourly intervals. This is a brilliant embedded design choice—it absorbs high-frequency log writes in RAM, protecting our SanDisk Max Endurance microSD card from unnecessary write wear.

The second area of friction was systemd's `ProtectSystem=strict` directive. When I first started the service with `ProtectSystem=strict` without specifying `ReadWritePaths=/var/log`, the script immediately crashed with `Permission denied: /var/log/sdrive-health.log`. Understanding that `strict` enforces a completely immutable root filesystem unless write paths are explicitly allowlisted gave me a much deeper appreciation for systemd’s sandboxing capabilities.

## Tomorrow

Tomorrow is Day 10: **The Network Laboratory**. We will begin mapping our network boundaries, profiling raw TCP and UDP throughput with `iperf3` over Gigabit Ethernet, analyzing socket states with `ss`, and executing deliberate network failure experiments (firewall blocks, MTU fragmentation, and DNS disruption) to build our diagnostic instincts before setting up Docker.
