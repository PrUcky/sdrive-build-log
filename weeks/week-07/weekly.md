# Week 07: Reliability and The Client

*Dates: October 9 – October 13, 2026*

## Objective
The infrastructure is built and sealed. Now, we must ensure it can run silently for months without manual intervention. We also begin the final transition toward the user experience by integrating the UI/UX rebranding fork prepared by the teammate. The ultimate goal is Gate B (October 25).

## Daily Plan

- **Day 43:** **Active Alerting.** Solve the "silent failure" problem by building a webhook notification system for cron jobs, backup scripts, and watchdogs.
- **Day 44:** **The Restore Drill.** We have automated backups, but an untested backup is just a liability. Run a full disaster recovery drill to restore Garage metadata and PostgreSQL from the tarballs.
- **Day 45:** **UI/UX Client Sync.** Review the teammate's custom Ente Android fork (applying the `ui-ux-brief.md` requirements). Connect the custom rebranded app to the Tailscale endpoint and verify functionality.
- **Day 46:** **Background Sync Tuning.** Test how the custom Android app behaves when backgrounding massive media uploads on mobile data over the WireGuard tunnel.
- **Day 47:** **Retrospective.** Week 07 Retro and the weekly engineering article.

## Exit Criteria

1. Automated webhook alerts configured for container failures and backup errors.
2. Successful bare-metal restore of the Garage metadata and PostgreSQL database documented.
3. Custom rebranded Android app successfully connected to the appliance and authenticated.
4. Background upload resilience verified.
