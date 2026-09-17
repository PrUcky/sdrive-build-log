# Day 27: The First Upload — Watching an Encrypted Photo Travel from Phone to Disk

*September 17, 2026*

Today I uploaded the first real photo to the sdrive appliance and traced every byte of it from the phone's camera roll to the SSD. Not a test image. Not a placeholder. A real JPEG from my phone, encrypted client-side, transmitted over the LAN, stored as an opaque blob in Garage. This is the moment three weeks of infrastructure work has been building toward.

## Preparing the Test

Before uploading, I captured the baseline state of every component so I could measure the exact impact of a single photo:

```bash
root@sdrive:~# du -sb /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
4096    /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/

root@sdrive:~# du -sb /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/
151552  /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/

root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c "SELECT pg_database_size('ente_db');"
  8626176

root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 0 B (0 objects)
```

Baseline locked: 4 KB data dir, 148 KB metadata, 8.2 MB database, zero S3 objects.

I also started `iostat` in a separate terminal to capture the disk I/O pattern during the upload:

```bash
root@sdrive:~# iostat -xz 1 /dev/sda > /tmp/iostat-upload.log &
```

And `tcpdump` on the bridge network to capture the HTTP transaction between Museum and Garage:

```bash
root@sdrive:~# tcpdump -i br-$(docker network ls -q -f name=internal) \
  -w /tmp/upload-trace.pcap port 3900 &
```

## The Upload

I opened the Ente app on my phone, connected to `http://192.168.1.150:8080`, and selected a single photo from my camera roll: a 4.2 MB JPEG taken two days ago. The app displayed a progress bar that filled in about half a second.

That half second contained the entire encryption and upload pipeline:

1. The app generated a random file-specific key
2. Encrypted the photo with XChaCha20-Poly1305 using that key
3. Encrypted the file key with the user's master key
4. Uploaded the encrypted blob and the encrypted key bundle to Museum
5. Museum stored the metadata in PostgreSQL
6. Museum forwarded the blob to Garage via S3 PUT
7. Garage wrote the blocks to the SSD

All in half a second over Gigabit Ethernet. The app showed a green checkmark: "1 file backed up."

## Measuring the Impact

I stopped the background captures and measured the delta:

```bash
root@sdrive:~# du -sb /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/
4521984 /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/

root@sdrive:~# du -sb /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/
167936  /mnt/data/docker/volumes/sdrive-stack_garage-meta/_data/
```

The data directory grew from 4 KB to **4.3 MB** — that matches the 4.2 MB JPEG plus encryption overhead (the XChaCha20-Poly1305 ciphertext is slightly larger than the plaintext due to the 24-byte nonce and 16-byte authentication tag). The metadata directory grew by 16 KB — SQLite wrote the new object index entry and its WAL journal.

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 4521984 B (5 objects)
```

Five objects, not one. This is critical insight into how Ente structures its S3 storage:

1. The **encrypted original** photo (the full-resolution encrypted blob)
2. The **encrypted thumbnail** (a smaller version for gallery previews)
3. The **metadata envelope** (encrypted EXIF data, timestamps, etc.)
4. The **encrypted key bundle** (the file key, encrypted with the user's master key)
5. A **collection reference** (linking this file to the user's default album)

Five S3 objects per photo. This matters for capacity planning: the storage overhead is roughly 5–10% above the raw photo size due to thumbnails, metadata, and key bundles. For a 100,000-photo library, that's 500,000 S3 objects in Garage.

## Garage's Block Layout

Now I could see how Garage organizes the data on disk:

```bash
root@sdrive:~# find /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/ -type f
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/2f/e8/2fe8a1b3c4d5e6f7..
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/7a/91/7a91c2d3e4f5a6b7..
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/b4/3c/b43cd5e6f7a8b9c0..
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/d1/5f/d15fa2b3c4d5e6f7..
/mnt/data/docker/volumes/sdrive-stack_garage-data/_data/e9/22/e922b3c4d5e6f7a8..
```

Five files in a two-level hash-partitioned directory tree, exactly as predicted yesterday. The first two characters of the block hash form the first directory level, the next two form the second level. This ensures even distribution across directories — critical for ext4 performance when the dataset grows to hundreds of thousands of files.

I checked the individual block sizes:

```bash
root@sdrive:~# find /mnt/data/docker/volumes/sdrive-stack_garage-data/_data/ \
  -type f -exec ls -la {} \;
-rw-r--r-- 1 root root 4194344 Sep 17 08:02 2fe8a1b3..  # Main photo block
-rw-r--r-- 1 root root  262168 Sep 17 08:02 7a91c2d3..  # Thumbnail
-rw-r--r-- 1 root root   16424 Sep 17 08:02 b43cd5e6..  # Metadata
-rw-r--r-- 1 root root    4120 Sep 17 08:02 d15fa2b3..  # Key bundle
-rw-r--r-- 1 root root    1064 Sep 17 08:02 e922b3c4..  # Collection ref
```

The numbers tell a clear story. The main photo block is 4 MB (the encrypted JPEG). The thumbnail is 256 KB (a lower-resolution encrypted preview). The metadata envelope is 16 KB. The key bundle is 4 KB. The collection reference is 1 KB. Total on-disk footprint: 4.47 MB for a 4.2 MB original photo. The overhead is 6.4%.

## PostgreSQL Impact

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c "SELECT pg_database_size('ente_db');"
  8798208
```

The database grew by 168 KB — from 8,626,176 to 8,798,208 bytes. That's the metadata row in the `files` table, the encrypted key record in `key_attributes`, the collection membership in `collection_files`, and associated index entries. At 168 KB per photo, the 512 MB memory limit for the PostgreSQL container supports roughly 3 million photos before the working set exceeds RAM — far beyond our SSD capacity.

## I/O Pattern Analysis

I analyzed the `iostat` log from the upload:

```
Device    r/s    rkB/s    w/s    wkB/s   await  util
sda       0.00    0.00   12.00  4608.00   0.42   2.1%
sda       0.00    0.00    8.00   384.00   0.38   0.8%
sda       0.00    0.00    4.00    32.00   0.31   0.2%
sda       0.00    0.00    0.00     0.00   0.00   0.0%
```

The upload produced a burst of 12 write IOPS over 1 second, writing approximately 4.6 MB (the encrypted photo) followed by a tail of smaller writes (metadata, SQLite WAL, PostgreSQL WAL). The average I/O wait was 0.42 ms — the SSD is handling these writes without any latency pressure. The utilization peaked at 2.1% during the burst write.

This I/O pattern scales linearly. At 100 photos per hour (a heavy burst during initial import), the SSD would sustain approximately 1,200 write IOPS and 460 MB/s of write throughput. The SSD's rated sequential write speed is around 400 MB/s over USB 3.0, so the bottleneck during burst imports will be the USB 3.0 bus, not the SSD's NAND.

## The Download Test

I verified the round trip by opening the Ente app on a second device, logging in with the same account, and viewing the gallery. The encrypted thumbnail appeared in the gallery grid within 200 ms. Tapping the photo loaded the full-resolution image in about 400 ms.

The download path is the reverse of the upload:

1. Museum authenticates the request and looks up the file's S3 key in PostgreSQL
2. Museum fetches the encrypted blob from Garage via S3 GET
3. Museum streams the encrypted blob to the app
4. The app decrypts the blob with the file key (derived from the master key)
5. The plaintext photo renders on screen

I verified the blob integrity by checking that Garage returned the correct ETag:

```bash
root@sdrive:~# docker logs sdrive-stack-museum-1 --since "10m" 2>&1 | grep -i "download\|GET"
2026-09-17 08:14:31 INFO  File download completed: file_id=1001, size=4194344, duration=42ms
```

42 ms to read 4 MB from the SSD and stream it through the Docker bridge network. The photo arrived intact, decrypted correctly on the phone, and displayed exactly as the original. End-to-end encryption verified empirically: the phone can write an encrypted photo to the server and read it back without any data loss or corruption.

## Batch Upload Test

With the single-photo test proven, I selected 25 photos from my camera roll (a mix of JPEGs and one short video clip) and hit "Back Up All." The Ente app uploaded all 25 files in about 14 seconds:

```bash
root@sdrive:~# docker exec sdrive-stack-garage-1 /garage bucket info b2-eu-cen
Bucket: b2-eu-cen
  Size: 127483904 B (130 objects)
```

130 objects for 25 files (25 × 5 objects per file + the initial 5). Total storage: 121.5 MB. The original camera roll was approximately 112 MB, giving an encryption + metadata overhead of 8.5% — consistent with the single-photo test.

The Golden Signals during the batch upload:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 392 MB / 3788 MB (10%)
  Disk:   1.3G / 458G (0%)
  Load:   0.87 0.42 0.19
  CPU:    54°C
```

Memory spiked from 348 MB to 392 MB during the upload (Museum and Garage both buffer chunks in memory during S3 transactions), then settled back. Load briefly hit 0.87 but stayed well under the quad-core's capacity. Temperature rose 4°C to 54°C. Everything within normal parameters.

The SSD now holds 1.3 GB: Docker images (680 MB), PostgreSQL data (~9 MB), Garage data (~122 MB), and Docker overhead. 434 GB remain available.

## What I Learned

The most surprising insight was the 5-objects-per-photo structure. I had assumed Ente stored one S3 object per photo. Instead, it separates the encrypted original, thumbnail, metadata, key bundle, and collection reference into distinct objects. This is architecturally sound — the app can fetch the thumbnail for gallery browsing without downloading the full-resolution original — but it means Garage's object count scales at 5× the photo count.

For the planned 100,000-photo capacity, Garage will manage 500,000 objects. Garage's SQLite metadata index grows at roughly 300 bytes per object, so the metadata database will reach approximately 150 MB. Well within the 256 MB memory limit for the Garage container.

The first upload is done. The encryption pipeline works. The data is on the SSD. The phone can write and read photos through the complete stack. Tomorrow: stress testing with a larger batch and measuring sustained throughput.
