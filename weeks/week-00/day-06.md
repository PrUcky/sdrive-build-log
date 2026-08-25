# Day 06 — Whiteboards and Cardboard

**Week:** 00 · **Date:** 2026-08-25 · **Hours:** ~4.0

I completely skipped yesterday. I didn't open a terminal, I didn't look at a markdown file, and I didn't read any documentation. I needed a complete disconnect from staring at a screen, because the roadmap for today was looming over me. Today’s task was to prove that I actually understand the beast I am trying to build before I touch a single piece of silicon. 

## What I actually did

I walked into the office, left my laptop closed on the desk, grabbed a dry-erase marker, and forced myself to draw the entire `sdrive` architecture on the whiteboard entirely from memory. 

Then, I wiped it completely clean and drew it a second time. 

It sounds like a tedious corporate exercise, but it was incredibly revealing. It exposed a massive, fundamental flaw in how I was visualizing the data flow. The very first time I drew the ingestion loop, I drew an arrow from the mobile phone, pointing to the Go API server (`museum`), and then another arrow pointing from the Go server to the object storage bucket (`Garage`). In my head, the server was a funnel. 

But as I stared at the whiteboard, I remembered my MinIO vs. Garage debate from Day 05. The whole reason MinIO was a bad fit is because it has to handle direct, aggressive client traffic. *Direct* client traffic. I realized my whiteboard drawing was entirely wrong. I erased the arrows. 

The phone talks to the Go server just to ask for permission. The Go server hands the phone a temporary "pre-signed URL" (basically a one-time VIP parking pass). Then, the phone turns around and uploads the massive, encrypted multi-megabyte blob *directly* into the object store, completely bypassing the Go server. That single realization fundamentally changes how I understand the network load on this machine. The Go server isn't a funnel; it's just a traffic cop.

I spent the next two hours transcribing that whiteboard session into a deeply detailed `docs/architecture.md` document, breaking down the hardware layer, the network layer, and the ingestion loop so I never forget it. I also spun up a `docs/glossary.md` file. I'm forcing myself to define all the jargon — CGNAT, E2EE, Pre-signed URLs — in my own words. If I can't explain it simply, I don't actually understand it. 

I cross-posted some of these architectural thoughts to Hashnode and Twitter. It feels good to finally have the "Why" and the "How" officially documented in public.

And then, just as I was finishing up, the doorbell rang. 

The hardware finally arrived. I spent twenty minutes just unboxing it and inventorying the parts on my desk. It is a tiny, unassuming cardboard box containing the Radxa ROCK 3C, a generic power supply, and a high-endurance microSD card. I held the board in my hand. It is barely the size of a credit card. It is entirely silent. It has no moving parts. And yet, this tiny little square of green fiberglass and silicon is going to replace a massive, multi-billion dollar Google data center for my entire digital life. The physical reality of the project just hit me.

## What confused me

I struggled heavily with explaining the architecture out loud. The roadmap demanded I explain it to someone non-technical in three minutes. I tried explaining the concept of pre-signed URLs to my partner over coffee, and I completely lost her the moment I said "S3-compatible bucket." 

I had to backtrack and come up with a real-world analogy on the fly. *Note to self: when explaining this to non-technical people, just say "the app asks the server for a temporary parking pass, and then the app parks the car itself."* That clicked instantly. 

## Tomorrow

Tomorrow is the official Week 00 retro. It’s time to look back at the orientation phase, write my first long-form article summarizing the vision, and mentally prepare for Week 01. We are finally plugging this tiny board into the wall.