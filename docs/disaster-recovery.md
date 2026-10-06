# Disaster Recovery (DR) Playbook

*Reference: weeks/week-07/day-44.md*

This document provides the step-by-step procedures for recovering the `sdrive` appliance from catastrophic failure. It assumes the automated backups (`sdrive-stack-backup.sh` and `sdrive-blob-backup.sh`) have been running successfully.

## Recovery Objectives
- **Recovery Point Objective (RPO):** Up to 24 hours of data loss (backups run nightly).
- **Recovery Time Objective (RTO):** < 1 hour from hardware replacement.

## Scenario 1: Complete SSD Failure (Total Data Loss)

If the external SSD fails, you lose the active Garage blobs, Garage metadata, PostgreSQL database, and Museum data.

**Requirements:**
- A new formatted SSD mounted at `/mnt/data`
- The off-site backup drive containing the metadata tarballs and the rsync blob mirror

### Step 1: Halt the Stack
```bash
cd /opt/sdrive/compose
docker compose down
```

### Step 2: Restore Metadata Volumes
Use the automated restore script to unpack the latest metadata tarballs into the Docker volume paths.

```bash
cd /opt/sdrive
./scripts/sdrive-restore-metadata.sh /path/to/backups/YYYYMMDD-HHMMSS
```
*Note: This restores `postgres-data`, `garage-meta`, and `museum-data`.*

### Step 3: Restore Garage Blobs
Use the reverse-rsync script to pull the multi-gigabyte blob archive back to the SSD.

```bash
# This may take hours depending on network/USB speed
./scripts/sdrive-restore-blobs.sh /path/to/backup/blobs/
```

### Step 4: Restart and Verify
```bash
cd /opt/sdrive/compose
docker compose up -d
./scripts/sdrive-golden-signals.sh
```

---

## Scenario 2: Database Corruption

If PostgreSQL crashes unrecoverably but the SSD is healthy.

### Step 1: Halt the Stack
```bash
cd /opt/sdrive/compose
docker compose stop museum postgres
```

### Step 2: Wipe and Restore ONLY Postgres
```bash
# Move corrupted volume
mv /mnt/data/docker/volumes/sdrive-stack_postgres-data \
   /mnt/data/docker/volumes/sdrive-stack_postgres-data.corrupt

# Manually extract the specific tarball
mkdir -p /mnt/data/docker/volumes/sdrive-stack_postgres-data/_data
tar -xzf /path/to/backups/YYYYMMDD-HHMMSS/postgres-data.tar.gz \
    -C /mnt/data/docker/volumes/sdrive-stack_postgres-data/_data

# Start and verify
docker compose start postgres museum
```

---

## Scenario 3: SD Card (OS) Failure

If the ROCK 3C fails to boot due to Armbian/SD card corruption, but the USB SSD is healthy. Data is safe on the SSD.

1. Flash a new SD card using `scripts/flash-sd.sh`.
2. Boot the board and run `scripts/bootstrap-node.sh`.
3. Re-mount the SSD to `/mnt/data`.
4. Run `docker compose up -d`.
*No database or blob restoration is required. The containers will read the existing volumes on the SSD.*