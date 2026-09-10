# Day 20: The SSD Mount and the Container Primer

*September 10, 2026*

Week 03 begins. The networking foundation is solid — ten days of uptime, zero errors, every packet observable. Now we build on top of it. The goal for this week is to get the full sdrive application stack running on the ROCK 3C: PostgreSQL for metadata, Garage for S3-compatible object storage, and Ente's `museum` backend for the API that the phone app talks to. All containerized. All on this one little board.

But the roadmap is explicit about the order of operations, and step one is not "install Docker." Step one is **mount the USB SSD**.

Here's why. The ROCK 3C boots from a 64GB microSD card. MicroSD cards are cheap, ubiquitous, and fundamentally unsuitable for sustained write workloads. They use NAND flash with minimal wear-leveling logic — the consumer-grade controllers in these cards don't come close to the endurance of an SSD controller. A container runtime writing image layers, database WAL files, and object storage blobs will annihilate a microSD card within months. I've seen it happen on Raspberry Pi deployments: the card silently develops bad sectors, the filesystem goes read-only, and the system dies in a way that looks like a software bug but is actually hardware death.

The USB SSD changes the equation completely. I connected a 500GB SATA SSD via a USB 3.0 to SATA bridge adapter. The ROCK 3C's USB 3.0 port connects to a dedicated xHCI controller on the RK3566 SoC, providing up to 5 Gbps of bus bandwidth — vastly more than the SSD's ~550 MB/s sequential capability.

```bash
root@sdrive:~# lsblk
NAME         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda            8:0    0 465.8G  0 disk
mmcblk0      179:0    0  59.5G  0 disk
├─mmcblk0p1  179:1    0  59.4G  0 part /
└─mmcblk0p2  179:2    0    64M  0 part
```

There it is. `sda` — 465.8 GB of beautiful, controller-managed NAND flash with proper wear leveling, TRIM support, and an endurance rating measured in hundreds of terabytes written. This is where all persistent application data will live.

I partitioned and formatted the drive with ext4, then mounted it at `/mnt/data`:

```bash
root@sdrive:~# parted /dev/sda mklabel gpt
root@sdrive:~# parted /dev/sda mkpart primary ext4 0% 100%
root@sdrive:~# mkfs.ext4 -L sdrive-data /dev/sda1
root@sdrive:~# mkdir -p /mnt/data
root@sdrive:~# mount /dev/sda1 /mnt/data
root@sdrive:~# df -h /mnt/data
Filesystem      Size  Used Avail Use%  Mounted on
/dev/sda1       458G   28K  435G   1%  /mnt/data
```

458 GB of usable space. That's enough for roughly 230,000 full-resolution smartphone photos at 2 MB each, or about 46,000 at 10 MB each (which covers RAW-quality phone camera output). Plenty for a personal backup appliance.

I made the mount persistent across reboots by adding it to `/etc/fstab` using the partition's UUID rather than the device path (because `/dev/sda` can change if other USB devices are connected at boot):

```bash
root@sdrive:~# blkid /dev/sda1
/dev/sda1: LABEL="sdrive-data" UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="ext4"

root@sdrive:~# echo 'UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890 /mnt/data ext4 defaults,noatime,discard 0 2' >> /etc/fstab
```

The `noatime` flag prevents the filesystem from updating the access timestamp on every read — a small but meaningful reduction in write amplification on flash media. The `discard` flag enables continuous TRIM, telling the SSD controller which blocks are no longer in use so it can optimize its internal garbage collection.

I verified the mount survives a reboot:

```bash
root@sdrive:~# reboot
# ... wait for board to come back up ...
root@sdrive:~# findmnt /mnt/data
TARGET     SOURCE    FSTYPE OPTIONS
/mnt/data  /dev/sda1 ext4   rw,noatime,discard
```

Clean. The SSD auto-mounted via fstab. Uptime counter reset to zero — our first intentional reboot since Day 09. But the journal survived because of Day 17's persistent storage configuration:

```bash
root@sdrive:~# journalctl --list-boots
 0 a1b2c3d4... Wed 2026-09-10 14:28:31 IST—Wed 2026-09-10 14:29:42 IST
-1 e5f6a7b8... Sat 2026-08-30 19:45:10 IST—Wed 2026-09-10 14:28:22 IST
```

Two boot sessions. The previous one lasted ten days. The persistent journal works exactly as configured.

Now, with the storage foundation laid, it's time to understand containers.

A container is not a virtual machine. A VM runs a complete operating system kernel inside an emulated hardware environment. A container shares the host kernel but runs in an isolated namespace — its own view of the process table, its own filesystem root, its own network stack, its own user space. The isolation isn't hardware-enforced; it's kernel-enforced via three Linux mechanisms:

1. **Namespaces** — isolate what a process can see (PID namespace, network namespace, mount namespace, UTS namespace)
2. **Cgroups** — limit what a process can use (CPU, memory, I/O bandwidth)
3. **Union filesystems** — layer read-only image layers with a writable overlay

This is crucial to understand because it determines the failure modes. A VM crash doesn't affect the host. A container crash doesn't necessarily crash the host either, but a container that exhausts memory *will* trigger the kernel's OOM killer, which might decide to kill a different container — or even a host process — to free memory. Containers are isolated, but they share a single kernel. That shared kernel is both the strength (near-zero overhead) and the weakness (shared failure domain).

I installed Docker Engine from the official Debian repository, not the Armbian package manager (which often lags behind):

```bash
root@sdrive:~# curl -fsSL https://get.docker.com | sh
root@sdrive:~# systemctl enable docker
root@sdrive:~# systemctl start docker
root@sdrive:~# docker --version
Docker version 27.2.1, build 9e34c9b
```

First thing I did: move Docker's data root off the microSD card and onto the SSD. By default, Docker stores everything — images, containers, volumes, build cache — in `/var/lib/docker`. That would murder the SD card. I created a dedicated directory on the SSD and pointed Docker at it:

```bash
root@sdrive:~# mkdir -p /mnt/data/docker
root@sdrive:~# cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/mnt/data/docker",
  "dns": ["1.1.1.1", "8.8.8.8", "192.168.1.1"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
root@sdrive:~# systemctl restart docker
```

Three critical settings in that daemon config:

1. **`data-root`** — All Docker data lives on the SSD, not the SD card. This is non-negotiable for any embedded Linux deployment.
2. **`dns`** — This is the fix for the `systemd-resolved` stub resolver issue we discovered on Day 18. Containers can't see `127.0.0.53`, so we inject our hardened DNS resolver chain directly into every container.
3. **`log-opts`** — Each container's stdout/stderr is capped at 10 MB across 3 rotated files. Maximum 30 MB of logs per container. On a 64 GB SD card (or even a 500 GB SSD), unbounded container logs are the number one cause of disk exhaustion in long-running deployments. This cap is a kill switch against log floods.

I verified Docker was using the SSD:

```bash
root@sdrive:~# docker info | grep "Docker Root Dir"
 Docker Root Dir: /mnt/data/docker
```

Perfect. Now let me demonstrate the fundamental container lifecycle. I pulled a tiny Alpine Linux image and ran it:

```bash
root@sdrive:~# docker pull alpine:3.20
3.20: Pulling from library/alpine
c6a83fedfae6: Pull complete
Digest: sha256:77726ef6b57ddf65bb551e3eb56e56c5c3a4ccf8a8c3e9c3c28e342b0cb5d8d1
Status: Downloaded newer image for alpine:3.20

root@sdrive:~# docker run --rm alpine:3.20 cat /etc/os-release
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.20.0
PRETTY_NAME="Alpine Linux v3.20"
```

That's the core mental model. The `pull` downloads an image — a read-only stack of filesystem layers. The `run` creates a container — an ephemeral, writable instance of that image. The `--rm` flag deletes the container when it exits. The image persists; the container is gone. This distinction is everything. Data that lives inside a container dies with the container. Data that needs to survive must live in a **volume**.

```bash
root@sdrive:~# docker volume create test-vol
test-vol
root@sdrive:~# docker run --rm -v test-vol:/data alpine:3.20 sh -c 'echo "persistent" > /data/test.txt'
root@sdrive:~# docker run --rm -v test-vol:/data alpine:3.20 cat /data/test.txt
persistent
```

The file survived across two separate container lifecycles because it lives in a Docker volume, which is stored on the SSD at `/mnt/data/docker/volumes/test-vol/`. The first container wrote it; the second container read it. Neither container exists anymore, but the data does. This is how PostgreSQL's data directory, Garage's block store, and the `museum` config will persist across container restarts, upgrades, and crashes.

I cleaned up the test volume and verified the socket audit:

```bash
root@sdrive:~# docker volume rm test-vol
root@sdrive:~# ss -tulnp
Netid  State   Recv-Q  Send-Q    Local Address:Port     Peer Address:Port  Process
tcp    LISTEN  0       128       0.0.0.0:22              0.0.0.0:*          users:(("sshd",pid=842,fd=3))
tcp    LISTEN  0       128       [::]:22                 [::]:*             users:(("sshd",pid=842,fd=4))
udp    UNCONN  0       0         127.0.0.53%lo:53        0.0.0.0:*          users:(("systemd-resolve",pid=614,fd=13))
```

Docker itself doesn't add any listening sockets. The Docker daemon communicates via a Unix socket at `/var/run/docker.sock`, which doesn't show up in `ss -tulnp` because it's not a TCP or UDP socket. The attack surface hasn't changed — still three listeners, same as Day 16's baseline.

The foundation is set. The SSD is mounted, Docker's data root is on the SSD, container DNS is configured to bypass the stub resolver, and log rotation is enforced. Tomorrow we pull the stock Ente quickstart and bring the entire application stack online for the first time. The unmodified baseline comes first — then we start changing things.
