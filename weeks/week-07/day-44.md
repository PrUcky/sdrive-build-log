# Day 44: The Panic of `rm -rf`

*October 10, 2026*

You don't have a backup strategy until you have a restore strategy. Today was the Disaster Recovery (DR) drill. I wrote a formal DR playbook (`docs/disaster-recovery.md`) and built two automated restore scripts. Then, to prove they worked, I intentionally destroyed the database.

## The Destruction

My phone was synced. It had 1,060 photos successfully uploaded to the ROCK 3C. I SSH'd into the board, stopped the stack, and did the unthinkable:

```bash
root@sdrive:~# docker compose stop
root@sdrive:~# mv /mnt/data/docker/volumes/sdrive-stack_postgres-data \
                  /mnt/data/docker/volumes/sdrive-stack_postgres-data.corrupt
```

I completely severed the PostgreSQL volume. The database was gone. All users, all authentication hashes, all metadata tying the encrypted Garage blobs together... vanished.

I started the stack back up. Museum immediately started throwing connection errors. The phone app logged me out and threw a generic 500 error on the login screen. The appliance was dead.

## The Restoration

If this were a real failure, this is where the panic sets in. But because the automated `sdrive-stack-backup.sh` script runs every night at 3:00 AM, I had a tarball from 7 hours ago.

I ran the new restore script:

```bash
root@sdrive:~# ./scripts/sdrive-restore-metadata.sh /mnt/data/backups/20261010-030000
======================================================================
 sdrive - METADATA RESTORE DRILL
======================================================================
WARNING: This will overwrite existing metadata volumes!
Backup to restore: /mnt/data/backups/20261010-030000
Are you sure you want to proceed? (y/N) y

Stopping containers...
Restoring postgres-data...
[OK] Restored postgres-data
Restoring garage-meta...
[OK] Restored garage-meta
Restoring museum-data...
[OK] Restored museum-data
======================================================================
Restore complete.
Run 'docker compose up -d' to restart the stack.
```

The script cleanly extracted the metadata tarballs into the precise Docker volume paths. It took 4 seconds.

## The Moment of Truth

I brought the stack back up:

```bash
root@sdrive:~# docker compose up -d
```

I opened the Ente app on my phone. The login screen prompted me. I entered my credentials, and the SRP protocol executed.

*Authentication successful.*

The gallery loaded instantly. All 1,060 photos were there. The thumbnails rendered. I tapped a video, and it streamed perfectly. The PostgreSQL database had successfully reattached to the Garage S3 blobs on the disk. The data was not trapped in a black box.

## Hooking the Alerts

While I was working on the backup scripts, I fully integrated the webhook alerting I built yesterday. `sdrive-blob-backup.sh` and `sdrive-stack-backup.sh` now push notifications directly to my phone. If the nightly backup fails, I'll know instantly. If it succeeds, I get a silent green checkmark notification in the morning.

The infrastructure is resilient. It survives reboots. It survives network drops. And now, I have proven it survives total database destruction with an RTO (Recovery Time Objective) of under 2 minutes.

Tomorrow, the focus shifts completely away from the server. Tomorrow, we review the custom Android app fork.
