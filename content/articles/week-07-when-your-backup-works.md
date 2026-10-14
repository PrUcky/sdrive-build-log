---
title: "When Your Backup Works But Your Restore Doesn't"
author: Pratyush Chaudhary
date: 2026-10-13
week: 7
tags: [disaster-recovery, android, doze-mode, background-sync, resilience]
---

# When Your Backup Works But Your Restore Doesn't

Every SRE knows the mantra: *"An untested backup is not a backup."* But knowing it and living it are two very different things.

For six weeks, my self-hosted photo backup appliance dutifully ran `sdrive-stack-backup.sh` every night at 3:00 AM. The tarballs accumulated in `/mnt/data/backups/`, quietly growing by a few hundred kilobytes each day as the PostgreSQL metadata and Garage object indices expanded. Every morning I'd SSH in, run `ls -lh /mnt/data/backups/`, see the latest timestamped directory, and feel a warm glow of operational competence.

But I had never actually tried to *use* one.

## The Controlled Demolition

This week, I decided to stop admiring the backup tarballs and start depending on them. I SSH'd into my ROCK 3C, stopped the Docker stack, and deliberately severed the PostgreSQL data volume.

For a brief, stomach-dropping moment, the appliance was dead. The Museum API threw connection errors. The Ente app on my phone logged me out and showed a blank 500 screen. Every piece of metadata—the user accounts, the SRP authentication hashes, the encrypted key references that tied the Garage blobs together—was gone.

Then I ran the restore script.

Four seconds later, the tarballs were unpacked. I brought the stack back up. I opened the app, logged in, and my entire gallery appeared. All 1,060 photos. Thumbnails, videos, everything. Four seconds.

The relief wasn't just emotional. It was *epistemic*. Before the drill, I *believed* my backups worked. After the drill, I *knew* they did. That's a fundamentally different level of confidence, and it's the difference between a resume bullet point and an engineering capability.

## The Silent Assassin in Your Pocket

The second revelation of the week came from the other end of the stack: the Android client.

I'd been testing the custom `sdrive` app with the screen awake, watching upload progress bars fill up on home WiFi. Everything worked beautifully. Then I tried what a real human would do: I took a 4K video, locked the screen, and put the phone in my pocket.

Six minutes and forty seconds later, the uploads stopped. No error. No crash. Just silence.

Welcome to Android Doze Mode—the operating system's aggressive power management system that suspends network access for background apps when the device is stationary with the screen off. It's designed to save battery. It's also designed to make background sync apps fail silently in exactly the scenario they're supposed to handle.

The fix required two layers: convincing Android that our upload worker is a Foreground Service (not an expendable background task), and manually exempting the app from battery optimization. Neither of these is intuitive. Neither produces an error message when misconfigured. The app just... stops uploading. And unless you're tailing your reverse proxy logs from an SSH session, you'd never know.

This is the kind of bug that doesn't appear in integration tests, doesn't show up in staging environments, and doesn't crash your CI pipeline. It only appears when a human puts a phone in a pocket and walks away. It's a reminder that the hardest bugs in distributed systems aren't in the distributed system—they're in the last mile, where your software meets the user's operating system.

## Alerting: Making the Server Talk Back

The third piece of the week was solving a problem I didn't realize I had: silent cron failures.

For weeks, my backup scripts, health monitors, and storage watchers had been logging their output to `/var/log/sdrive/`. If a backup failed at 3:30 AM because the USB SSD was full, the error would sit in a log file until I manually SSH'd in and read it. Which might be days later.

The fix was embarrassingly simple: a 50-line bash script (`sdrive-notify.sh`) that POSTs a JSON payload to a webhook URL. Now, every backup script calls it on success or failure. Every morning at 3:35 AM, I get either a green checkmark or a red siren on my phone. The server doesn't wait for me to ask how it's feeling. It tells me.

This is the operational maturity gap that separates "I built a thing" from "I run a thing." Building is a one-time act of creation. Running is an ongoing act of attention. And attention doesn't scale unless you automate it.

## The Client Changes Everything

The most satisfying moment of the week had nothing to do with bash scripts or Docker containers. It was opening the custom `sdrive` Android app for the first time.

My teammate had delivered the rebranded APK. The Ente cloud logo was gone, replaced by the sdrive vault icon. The splash screen said "Your Private Vault." The Settings menu had no "Billing" tab, no "Upgrade to Premium" banner, no subscription nags. The storage display showed the actual capacity of the SSD sitting on my desk: `6.4 GB / 458 GB`.

For seven weeks, this project felt like a backend engineering exercise—containers, certificates, firewalls. But when the custom app loaded with the right branding, the right endpoint pre-configured, and the right UI stripped of irrelevant cloud-service artifacts... it stopped being a self-hosted workaround and started being a product.

That's the lesson of Week 07. The infrastructure is necessary but insufficient. The backup scripts, the TLS certificates, the WireGuard tunnels—they're the foundation. But the product is the moment a family member opens an app, sees their photos, and never thinks about the server sitting in a closet.

Thirteen days until Gate B.
