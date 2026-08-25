# Day 06 — Whiteboards and Cardboard

**Week:** 00 · **Date:** 2026-08-25 · **Hours:** ~3.0

I skipped yesterday. I needed a break from staring at a screen, but today I got back into it. The roadmap demanded that I prove I actually understand what I'm building before I touch a single line of code or flash an OS. 

## What I actually did

I closed my laptop, grabbed a marker, and drew the entire `sdrive` architecture on the whiteboard in my office. Then I erased it and drew it again. 

It sounds silly, but it exposed a gap in my thinking almost immediately. The first time I drew it, I routed the data flow from the phone, into the Go server (`museum`), and then into the object store (`Garage`). But that's wrong. I remembered my realization from yesterday: the phone hits the object store *directly* using pre-signed URLs. The second time I drew it, the lines went to the right places. 

I transcribed that whiteboard session into a formal `docs/architecture.md` file, detailing the five core components and the exact upload data flow. I also started a `docs/glossary.md` file. There’s a lot of jargon in this space — CGNAT, pre-signed URLs, E2EE — and writing out the definitions in my own words is the only way I actually retain them. I cross-posted these updates to the new social accounts to act as my first official public daily posts.

And then, the doorbell rang.

The hardware arrived! A tiny cardboard box containing the Radxa ROCK 3C, a power supply, and a high-endurance microSD card. I unboxed it and laid it out on the desk. It’s wild to think that this tiny piece of silicon, barely the size of a credit card, is going to replace a multi-billion dollar Google data center for my personal life.

## What confused me

Nothing explicitly technical today, but I did struggle with explaining the architecture out loud. I tried to explain the concept of pre-signed URLs to my partner in three minutes, and I completely lost her at "S3-compatible bucket." Note to self: when explaining this to non-technical people, just say "the app asks the server for a temporary parking pass, and then the app parks the car itself."

## Tomorrow

The Week 00 retro. And then, we finally plug this board into the wall.