# Day 01 — The Machine and the Network

**Week:** 00 · **Date:** 2026-08-19 · **Hours:** ~5.5

Started later than I wanted. Spent the first hour just finding where I'd put the board after it arrived last week.

## What I actually did

Pulled out the Radxa ROCK 3C and laid everything on the desk — board, heatsink, the USB-C power supply I bought, and the SD card. First impression: it's smaller than I expected. The SoC sits in the middle under where the heatsink goes, LPDDR4 chips flanking it. Ethernet port on one end, a row of USB-A and a single USB-C on the other. There's an M.2 slot on the underside which I didn't notice until I flipped it over looking for something else.

Didn't try to boot it today. The plan for day 1 was understanding, not doing — so I put it aside and spent most of the afternoon just reading.

The main thing I worked through: what "the cloud" actually is. I've been using the phrase for years and never really stopped to think about it. It's just someone else's server in a warehouse. That's it. Google Photos is a very large Radxa ROCK 3C somewhere in a Google datacenter, except Google's version has a lot more RAM and they're reading your photos to sell ads. sdrive is the same thing, smaller, in your house, and they can't read anything because it's encrypted before it leaves your phone.

That framing helped a lot. Once I thought of it that way the client/server split made sense immediately — phone is client (it wants to store something), board is server (it waits and accepts). The only thing that trips it up is NAT: the board is inside the home network and normally unreachable from outside. That's what Tailscale solves later. Didn't go deep on that today, just noted it as the problem Week 6 addresses.

Drew the upload path on paper — phone to cell tower to ISP to home router to the board. Drew it again without looking. Second time was messier but faster.

## What confused me

The power supply thing. I assumed any USB-C charger would work. Turns out USB-PD negotiation is weirder than I thought — a lot of modern chargers prioritise 9V or 20V for laptops and might not reliably deliver 5V at 3A for a board that expects exactly that. Spent probably 40 minutes going down a forum rabbit hole about this. Ended up deciding the dedicated 5V/3A supply I bought is fine and I'll just use that.

Also kept second-guessing whether the M.2 slot would actually work for an NVMe drive or only SATA. Couldn't get a straight answer from the first two pages I found. Left it as an open question — don't need it yet anyway.

## Tomorrow

Setting up the repository properly and reading through the Ente architecture so I understand what I'm actually building before the board boots for the first time.
