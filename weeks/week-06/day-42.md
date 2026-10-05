# Day 42: Week 06 Retrospective — The Appliance Goes Dark

*October 8, 2026*

Week 06 is finished. The infrastructure phase of the sdrive project is officially complete. 

Six weeks ago, this was a bare ROCK 3C board flashing Armbian to an SD card. Today, it is an end-to-end encrypted, zero-trust, globally reachable photo backup appliance that sits entirely invisible on my local network.

This week was all about sealing the perimeter. Caddy was deployed to terminate TLS. Museum was stripped of its public port. UFW was forced to ignore Docker's dangerous iptables overrides, locking down the physical `end0` interface so strictly that the server doesn't even respond to a local `curl`. 

The only way in is through the Tailnet. 

I spent this morning writing the formal Week 06 retrospective and the weekly article. The article focuses on a massive pitfall that catches almost every self-hoster: the fact that Docker silently punches through UFW. Fixing that was the most satisfying architectural win of the week.

Gate B is October 25. That's 17 days away. The requirement is a "complete one-app upload/retrieval proof." Since the backend and network are completely finished, the remaining time is dedicated to:
1. Long-term reliability (ensuring the cron backups and watchdogs run without intervention)
2. UI/UX coordination with the teammate (ensuring the Ente app rebranding matches our `ui-ux-brief.md` requirements)
3. Polishing the demo script for the Gate B presentation.

Week 07 starts tomorrow. We shift from building the engine to polishing the car.
