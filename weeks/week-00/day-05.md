# Day 05 — The Why

**Week:** 00 · **Date:** 2026-08-23 · **Hours:** ~4.5

Today was weirdly therapeutic. I spent the entire afternoon just writing text documents in the `docs/decisions/` folder. No code, no terminals, just forcing myself to write down exactly *why* I'm choosing this specific stack before the hardware actually gets here.

## What I actually did

I wrote five formal Architecture Decision Records (ADRs). I’ve read a million of these at work, but I've never actually sat down and written them for my own personal project. It felt a little overkill at first, but by the third one, I realized how incredibly useful it is. 

I wrote records for choosing Ente over Immich, picking the older ROCK 3C board over the shiny new AI boards, using Tailscale instead of Headscale (for now), swapping MinIO for Garage, and booting off an SD card for the prototype. 

The biggest realization I had while writing these is how much of an architectural domino effect the very first decision caused. The moment I committed to Ente — which forces end-to-end encryption and pushes all the heavy machine learning and thumbnail generation onto the phone — every other decision instantly became easier. 

Because the server doesn't do any heavy lifting, I don't need a massive RK3576 board with an NPU. Because I'm using a low-power board, running an enterprise object store like MinIO is a terrible idea, which naturally points me to a lightweight Rust binary like Garage. The architecture basically designed itself just by answering the privacy question first.

## What confused me

I struggled a bit with the MinIO vs. Garage decision while writing it up. I had to really dig into the Ente documentation to understand how the object storage actually behaves. I originally thought `museum` (the Go server) acted as a middleman, receiving the photo and passing it to the database. If that were true, the object store would just be a quiet internal drive. 

But because of how pre-signed URLs work, the phone bypasses the Go server entirely and slams the object store directly with the encrypted payload. That means the object store is taking the full brunt of the network traffic from the client. That realization was the final nail in the coffin for MinIO. It expects enterprise NVMe arrays to handle that kind of direct client traffic, and my poor little Radxa board would absolutely choke trying to keep up. Garage is going to be so much more forgiving of my cheap hardware.

## Tomorrow

The final day of Week 00. I need to physically draw the entire architecture out from memory until I can explain it to a five-year-old. Then I think I’m going to do my first real weekly recap post.