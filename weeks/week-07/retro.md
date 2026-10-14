# Week 07 Retrospective: Reliability and The Client

*October 9 – October 13, 2026*
*Author: Pratyush Chaudhary*

---

## Summary

Week 07 marked the decisive transition from infrastructure engineering to product readiness. With the server stack fully sealed behind Tailscale, Caddy, and the Docker firewall in Week 06, this week focused on two critical questions: (1) Can the appliance recover from catastrophic failure? and (2) Can a non-technical user actually use this thing?

Both questions were answered with evidence.

---

## Exit Criteria Scorecard

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Automated webhook alerts for container failures and backup errors | ✅ Met | `sdrive-notify.sh` dispatches to Discord/Slack/Ntfy; integrated into both backup scripts and crontab v3 |
| 2 | Successful bare-metal restore of Garage metadata and PostgreSQL | ✅ Met | Day 44 drill: destroyed Postgres volume, restored from nightly tarball in 4 seconds, gallery loaded with all 1,060 photos |
| 3 | Custom rebranded Android app connected and authenticated | ✅ Met | RC1 APK sideloaded; branding, no-billing UI, hardcoded Tailnet endpoint all verified (docs/ui-ux-review.md) |
| 4 | Background upload resilience verified | ✅ Met | Day 46: 1.2 GB 4K video uploaded from pocket on 4G LTE in 13m42s with screen locked, zero drops |

**Result: 4/4 exit criteria met.**

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Recovery Time Objective (RTO) | < 2 minutes (metadata restore + stack restart) |
| Recovery Point Objective (RPO) | ≤ 24 hours (nightly backup cadence) |
| Background upload throughput (4G) | 1.49 MB/s effective (1.2 GB in 13m42s) |
| Android Doze survival | Confirmed with Foreground Service + Unrestricted battery |
| Total operational scripts | 23 (added: notify, restore-metadata, restore-blobs, tail-client) |
| ADRs documented | 6 total (added: ADR-006 Custom Android Client) |

---

## What Went Well

1. **The DR drill was visceral.** Deliberately destroying the database and watching the restore script bring everything back in seconds was the most confidence-building exercise of the entire project. An untested backup is just a liability.

2. **The custom APK transformed the UX.** When the app opened without subscription nags, without a "Custom Server" input field, and with the sdrive logo on the splash screen — it stopped feeling like a hacked-together self-hosted workaround and started feeling like a real product.

3. **Caddy's timeout tuning paid off.** The `read_body 10m` timeout we set in Week 06 was critical. A 1.2 GB video over a fluctuating 4G connection takes 13+ minutes to upload. Default timeouts would have killed it.

## What Went Wrong

1. **Android Doze Mode was initially invisible.** The first background upload test died silently at the 6-minute mark. No error, no timeout, no TCP reset — just silence. It took an hour of staring at Caddy logs to realize the OS had severed the network socket from the app side. This failure mode is completely invisible to the server.

2. **Foreground Service promotion threshold was too high.** The upstream Ente client only promotes to a Foreground Service for 5+ queued items. A single 1.2 GB video fell through. We patched it to promote any file >50 MB immediately.

## Lessons Learned

- **Test with the screen locked.** Any demo or test done with the screen awake is invalid for mobile background sync. Android's power management is adversarial to background network activity by design.
- **Push notifications beat pull monitoring.** The webhook alerting system (`sdrive-notify.sh`) fundamentally changed the operational experience. The server tells me when it's sick — I no longer have to SSH in to check.
- **Document the client requirements.** Battery optimization, Always-On VPN, and Split Tunneling are invisible prerequisites. Without `docs/client-configuration.md`, a new user would never figure out why uploads fail after 6 minutes.

---

## Artifacts Produced This Week

| File | Type |
|------|------|
| `weeks/week-07/roadmap.md` | Planning |
| `weeks/week-07/day-43.md` through `day-46.md` | Daily Logs |
| `scripts/sdrive-notify.sh` | Webhook alerting script |
| `scripts/sdrive-restore-metadata.sh` | DR metadata restore |
| `scripts/sdrive-restore-blobs.sh` | DR blob restore |
| `scripts/sdrive-tail-client.sh` | Real-time client traffic monitor |
| `config/cron/sdrive-crontab` (v3) | Updated with webhook env var |
| `scripts/sdrive-blob-backup.sh` (v2) | Integrated alerting |
| `scripts/sdrive-stack-backup.sh` (v2) | Integrated alerting |
| `docs/disaster-recovery.md` | DR playbook (3 scenarios) |
| `docs/ui-ux-review.md` | Client APK review |
| `docs/client-configuration.md` | Android setup guide |
| `docs/adr/006-custom-android-client.md` | Architecture decision |
| `diagrams/system-context.mermaid` | C4 system context diagram |

---

## Gate B Status (October 25)

**13 days remaining.** All technical prerequisites are now in place:
- ✅ Server stack sealed and resilient
- ✅ Automated backups with push alerting
- ✅ Disaster recovery tested and documented
- ✅ Custom Android app connected, branded, and background-sync verified
- ⬜ Multi-device retrieval proof (Phone A uploads → Phone B views)
- ⬜ Account isolation proof (User A cannot see User B's photos)
- ⬜ Demo video recording

Week 08 will focus on the remaining Gate B evidence: multi-device sync, account isolation, and preparing the demo recording.
