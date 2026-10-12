# Day 46: Surviving Android Doze — Background Sync Under Real-World Conditions

*October 12, 2026*

With the custom `sdrive` Android client installed and talking to Caddy, today was about the most brutal test in mobile engineering: background media uploads with the screen off, running on battery, over a fluctuating cellular connection.

If you test a photo backup app while holding the phone with the screen awake on home WiFi, everything looks heroic. But that's not how humans use phones. You shoot a 3-minute 4K video at a family gathering, lock the screen, slide the phone into your pocket, and get into the car. If the upload silently dies 3 minutes later because Android put the radio to sleep, the product has failed.

Gate B is in 13 days. Today I stress-tested background sync until it broke, figured out why, and fixed it.

## The Test Setup

- **Device:** Google Pixel 7 (Android 14).
- **Network:** 4G LTE carrier connection (behind carrier CGNAT, ~18 Mbps uplink).
- **Transport:** Tailscale WireGuard tunnel connected to `sdrive.tail12345.ts.net`.
- **Payload:** A 1.2 GB 4K/60fps video recorded specifically for this test (`PXL_20261012_142010.mp4`).
- **Condition:** Phone unplugged, battery at 68%, screen locked immediately after tapping "Back up now".

I left the board running with `sdrive-tail-client.sh` streaming Caddy's access logs to a terminal session so I could observe the transfer remotely over SSH.

## Test 1: The Doze Mode Trap

I triggered the upload, locked the phone, put it on my desk, and watched the log output.

For the first 5 minutes, chunked `PUT` requests rolled in steadily at ~1.5 MB/s:

```text
[2026-10-12T14:26:02Z] PUT /api/v1/objects/chunk - 200 (1.12s)
[2026-10-12T14:26:15Z] PUT /api/v1/objects/chunk - 200 (1.08s)
```

Then, at exactly the 6-minute 40-second mark, the terminal went dead. No errors. No TCP resets. Just silence.

I waited 5 minutes. Nothing. 

I picked up the phone and pressed the power button to wake the lock screen. The instant the display lit up, the Caddy logs exploded with activity again:

```text
[2026-10-12T14:38:12Z] PUT /api/v1/objects/chunk - 200 (1.45s)
```

This is Android Doze Mode. Introduced back in Android 6 and tightened in every release since, Doze detects when an unplugged device is stationary with the screen off. It aggressively enters a deep sleep state:
1. Network access is completely disabled for background apps.
2. Wake locks are ignored.
3. Standard `WorkManager` background jobs are deferred until the next periodic "maintenance window" (which can be 15 to 30 minutes away).

Because the stock Ente build had default battery restrictions, Android classified the upload worker as an ordinary background task and severed its network socket the moment the OS entered deep sleep.

## The Two Fixes

To guarantee uninterrupted multi-gigabyte uploads when the phone is locked, two independent configurations are required:

### 1. Client-Side: Enforcing a Foreground Service
In Android, the only mechanism guaranteed to retain network access and CPU wake locks during deep sleep is an **Active Foreground Service** paired with an ongoing user-visible notification.

I pinged my teammate to verify how the fork handles this. In upstream Ente, the background sync can run as an opportunistic `WorkManager` worker or promote itself to a Foreground Service (`SyncService`) with a persistent status bar notification (`"Backing up 1 item..."`). 

We confirmed that in our fork, `SyncService` was properly declaring `foregroundServiceType="dataSync"` in `AndroidManifest.xml`, but the auto-promotion threshold was only firing if more than 5 items were queued. For a single massive 1.2 GB video, it was falling back to the standard opportunistic worker. 

My teammate pushed a patch to our client repository: any single file larger than 50 MB now immediately promotes the worker to a Foreground Service with an active notification.

### 2. OS-Level: Battery & Data Optimization
On the physical phone, two Android settings had to be manually toggled:
- **App Battery Usage:** Changed from `Optimized` to `Unrestricted`. This exempts the app's process from aggressive OS task-killing and eliminates Doze-induced socket closures.
- **Unrestricted Data Usage:** Toggled ON under Mobile Data settings. This prevents Android's "Data Saver" mode from throttling background uploads when not on WiFi.

## Test 2: The Pocket Walk Re-Test

With the client patch installed and battery optimization set to `Unrestricted`, I set up the real test.

I queued the same 1.2 GB 4K video, locked the phone, put it in my pocket, and went for a 15-minute walk around the neighborhood. During the walk, the phone transitioned across cell towers, briefly dipped from 4G to 3G and back to 4G, and remained in my pocket with the display off the entire time.

When I got back to my desk, I inspected the Caddy logs and Garage disk metrics:

```bash
root@sdrive:~# ./scripts/sdrive-golden-signals.sh
[TRAFFIC] Storage metrics:
  Garage objects: 5,545 (+5 objects for new video)
  SSD used: 6.7G (increased by 1.2 GB)

root@sdrive:~# docker compose logs caddy --since 20m | grep "status\":2" | wc -l
128
```

128 successful chunk uploads logged. The entire 1.2 GB video transferred from my pocket in 13 minutes and 42 seconds (average effective throughput: 1.49 MB/s). 

The persistent notification in the status bar had cleanly dismissed itself upon completion. When I opened the `sdrive` app, the video thumbnail was rendered, the duration was indexed, and playback streamed smoothly from the appliance over the Tailnet.

## What This Proves for Gate B

Gate B requires: *"Complete one-app upload/retrieval proof."*

Today proved that the mobile experience is not brittle:
- The Tailscale WireGuard socket survives cellular handoffs and tower switches without dropping.
- Caddy's 10-minute timeout buffer (`timeouts { read_body 10m }`) handled the slow chunk stream without dropping a single packet.
- Android does not kill the process or freeze network I/O when the screen is locked, provided the foreground service and unrestricted battery permissions are set.

The stack handles real human behavior now: shoot, lock, pocket, forget.

Tomorrow is Sunday: Week 07 Retrospective and the weekly engineering article.
