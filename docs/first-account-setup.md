# First Account Setup Guide

*Reference: weeks/week-03/day-23.md*

This guide walks through registering the first user account on a fresh sdrive installation, reading the verification code from container logs (no SMTP required), promoting the account to admin, and removing the trial storage quota.

---

## Prerequisites

- All three containers healthy: `docker compose ps` shows `(healthy)` for postgres, garage, and museum
- Museum API reachable: `curl -s http://192.168.1.150:8080/health` returns `{"status":"ok"}`
- Garage layout initialized: `scripts/garage-init-layout.sh` has been run

---

## Step 1: Register an Account

Using the Ente mobile app or web client, point the server URL at your sdrive instance:

```
Server: http://192.168.1.150:8080
```

Register with an email address. Since SMTP is not configured, the verification email won't be delivered — that's expected. The verification code is logged to museum's container stdout.

## Step 2: Read the Verification Code

```bash
root@sdrive:~# docker logs sdrive-stack-museum-1 2>&1 | grep -i "verification\|OTP"
2026-09-13 10:14:22 INFO  Sending verification code 847291 to user@example.com
```

The 6-digit code appears in the log output. Enter it in the app to complete registration.

> **Security Note:** These logs are capped at 10 MB with 3 rotations (configured in `daemon.json`). Old verification codes are automatically purged when logs rotate.

## Step 3: Find Your Numeric User ID

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c "SELECT user_id, email FROM users;"
  1234567 | user@example.com
```

Note the numeric `user_id` (e.g., `1234567`).

## Step 4: Promote to Admin

Edit the `museum.yaml` on the board (not the repo copy) and uncomment the `internal` section:

```yaml
internal:
  admins:
    - 1234567
```

Restart museum to pick up the config change:

```bash
root@sdrive:~# docker compose restart museum
```

## Step 5: Remove the Trial Storage Quota

This is the step the roadmap warns about. A fresh self-hosted account is capped at a trial quota. If you skip this, Week 05's photo import will fail partway through with an error that looks like an upload bug but is actually a storage limit.

Install the `ente` CLI and run:

```bash
# On your desktop (not the board):
$ ente account login --server http://192.168.1.150:8080
$ ente admin update-subscription --no-limit --admin-user user@example.com
```

Alternatively, from the board directly:

```bash
root@sdrive:~# docker exec -it sdrive-stack-museum-1 \
  /bin/sh -c 'museum admin update-subscription --no-limit --user-id 1234567'
```

## Step 6: Verify

Confirm the account has unlimited storage:

```bash
root@sdrive:~# docker exec sdrive-stack-postgres-1 \
  psql -U pguser -d ente_db -t -c \
  "SELECT user_id, storage_limit FROM subscriptions WHERE user_id = 1234567;"
  1234567 | -1
```

A `storage_limit` of `-1` means unlimited. The account is ready for photo imports.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No verification code in logs | Museum not logging at INFO level | Check `log.level: info` in museum.yaml |
| `{"status":"error"}` on health | Database connection failed | Check postgres healthcheck: `docker compose ps` |
| Upload fails at ~1 GB | Trial quota not removed | Run `update-subscription --no-limit` (Step 5) |
| "Key not found" from Garage | Layout not initialized | Run `./scripts/garage-init-layout.sh` |
