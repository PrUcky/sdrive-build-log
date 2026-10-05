# Day 43: Solving the Silent Failure Problem

*October 9, 2026*

The appliance is running flawlessly. The Tailscale tunnel is active, Caddy is proxying TLS, the backups are running nightly. But sitting here on Day 43, looking at a terminal that hasn't thrown an error in a week, I realized something terrifying: 

If the appliance *did* fail, I wouldn't know.

Right now, the nightly cron jobs dump their output to `/var/log/sdrive/`. If the `sdrive-blob-backup.sh` script exits with an error because the SSD is full, it just writes a line to a text file that I have to manually SSH in to read. In a production environment, silence doesn't mean health. Silence often means the cron daemon died, the disk filled up, or the network dropped.

I need the server to scream when it hurts.

## The Alerting Script

To solve the "No notification system for alerts" issue carried forward from the Week 05 Retro, I wrote `scripts/sdrive-notify.sh`. 

It is intentionally dead simple:
1. It takes two arguments: a severity level (`INFO`, `WARN`, `ERROR`, `SUCCESS`) and a message.
2. It looks for a webhook URL in the environment (`SDRIVE_WEBHOOK_URL`).
3. It POSTs a JSON payload to that webhook.

```bash
root@sdrive:~# export SDRIVE_WEBHOOK_URL="https://discord.com/api/webhooks/..."
root@sdrive:~# ./scripts/sdrive-notify.sh ERROR "Garage container is down!"
Alert dispatched: ERROR
```

Two seconds later, a red siren emoji and the error message pop up on my phone. 

If the `SDRIVE_WEBHOOK_URL` isn't set, the script degrades gracefully and just writes the alert to a local log file. It also uses `curl -m 5` to enforce a 5-second timeout, ensuring that if Discord/Slack is down, the alerting script won't hang the parent cron job that called it.

## Hooking the Cron Jobs

With the script in place, I spent the afternoon modifying the existing operational scripts to actually use it.

In the `sdrive-container-health.sh` script (which runs every 15 minutes), I added:
```bash
if [ "$UNHEALTHY_COUNT" -gt 0 ]; then
    /opt/sdrive/scripts/sdrive-notify.sh "CRITICAL" "$UNHEALTHY_COUNT containers are offline!"
fi
```

In the `sdrive-blob-backup.sh` script (runs nightly at 3:30 AM):
```bash
if rsync ... ; then
    /opt/sdrive/scripts/sdrive-notify.sh "SUCCESS" "Nightly blob backup completed successfully."
else
    /opt/sdrive/scripts/sdrive-notify.sh "ERROR" "Nightly blob backup FAILED! Exit code $?"
fi
```

I injected the `SDRIVE_WEBHOOK_URL` directly into the crontab header:
```text
SDRIVE_WEBHOOK_URL=https://...
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# ... jobs ...
```

## The Value of Push Notifications

This changes the entire operational dynamic of the appliance. 

I no longer have to open a terminal, SSH into the Tailscale IP, and `tail -f /var/log/syslog` just to check if the backup ran. The server pushes its state to me. I'll get a green checkmark every morning at 3:35 AM confirming my photos are safe on the secondary drive, and I'll get a red siren immediately if a container crashes.

The infrastructure phase was about building the engine. Week 07 is about operational maturity. The machine is now self-reporting.

Tomorrow, we test disaster recovery. We have the backups. But can we restore them?
