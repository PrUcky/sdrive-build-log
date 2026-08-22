# Day 04 — The Empty House

**Week:** 00 · **Date:** 2026-08-22 · **Hours:** ~3.5

Today was basically nesting. The hardware arrives next week, but I wanted the "house" for the project to be completely built and furnished before it gets here. 

## What I actually did

I spent the afternoon fleshing out the `sdrive-build-log` repository. Up until today, it was just a loose collection of the first three daily logs. I finally sat down and built out the actual skeletal structure that is going to hold this entire 12-week project. 

I created all the blank directories: `docs/` for my architecture notes and decision records, `diagrams/`, `scripts/`, `benchmarks/`, `hardware/` (where the 3D models for the case will eventually live), `app/` for the customized mobile client, `content/`, and `assets/`. 

The most interesting one I created was `config/garage/`. If you look back at my Day 02 log, I spent a lot of time talking about how the phone pushes the encrypted blob directly to MinIO. That *was* the plan. But after spending last night reading through some storage benchmarks and overhead requirements, I'm already pivoting. I'm going to use **Garage** instead of MinIO for the object storage layer. I won't go deep into the "why" right now — tomorrow's entire goal is writing up the formal decision records — but the short version is that MinIO is designed for enterprise data centers, and Garage is designed to run quietly on a potato. My Radxa board is much closer to a potato than a data center.

Once the folder skeleton was up, I went ahead and wrote a proper `README.md` that acts as the front door for anyone stumbling across this project. It outlines the 12-week schedule and explains what all these empty folders are actually for.

I also finally slapped an AGPL-3.0 license file into the root. I went with AGPL because this is fundamentally a networked server application, and AGPL ensures that if anyone takes this stack, modifies it, and hosts it as a service over a network, they still have to share their source code. It feels like the right fit for a self-hosted cloud replacement.

## What confused me

I had a moment of paralysis trying to decide if I should put the mobile app source code directly inside this repository (in the `app/` folder) as a monorepo, or if I should fork the Ente app repo entirely and keep it separate. 

I decided to just keep it in here as a monorepo approach for now. The reality is that having my infrastructure scripts, my configuration files, and my client app code drifting out of sync across multiple repositories sounds like a nightmare for a single developer. If it gets too bloated in Week 8, I can always split it out. 

## Tomorrow

Decision records. I need to formally write down *why* I'm making some of these architectural choices (like Ente over Immich, ROCK 3C over RK3576, and Garage over MinIO). Writing them down now forces me to justify the tech stack before I'm waist-deep in bash scripts and regretting my life choices.
