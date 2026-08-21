# Day 01 — The Machine and the Network

**Week:** 00 · **Date:** 2026-08-19 · **Hours:** ~5.5

Started way later than I wanted today. Spent the first hour literally just trying to find where I had put the Radxa board after it arrived in the mail last week. It was buried under a pile of other mail. 

## What I actually did

Finally pulled the Radxa ROCK 3C out of its box and laid everything on my desk. Board, heatsink, the USB-C power supply I bought separately, and the SD card. First impression? It is so much smaller than I expected in person. The SoC sits right in the middle (where the heatsink will eventually go), with LPDDR4 chips flanking it. Ethernet port on one end, a row of USB-A ports and a single USB-C on the other. I didn't even notice the M.2 slot on the underside until I flipped the board over trying to find the SD card slot.

I didn't even try to boot it today. The plan for Day 1 was purely about understanding the concepts, not breaking things yet. So I pushed the hardware aside and spent most of the afternoon just reading.

The main concept I tried to wrap my head around was what "the cloud" actually physically *is*. I've been using that phrase for years and never really stopped to think about the physical infrastructure. It finally clicked: it's literally just someone else's computer sitting in a warehouse somewhere. Google Photos is just a very large Radxa ROCK 3C running in a Google datacenter, except Google's version has massive amounts of RAM and they are scanning your photos to sell ads. sdrive is the exact same concept, just scaled down, sitting in my house, and nobody can read my stuff because it's encrypted before it even leaves my phone.

That framing helped so much. Once I started thinking about it that way, the client/server split made total sense. The phone is the client (it generates the photo and wants to store it), the board is the server (it just waits and accepts it). The only real gotcha is NAT: the board sits inside my home network, which means it's normally completely unreachable from the outside world. That’s the exact problem Tailscale is supposed to solve later. I didn't go deep into that today, just mentally bookmarked it as a future headache for Week 6.

I ended the day by drawing the upload path on paper. Phone -> cell tower -> ISP -> home router -> the board. Then I flipped the page and drew it again without looking. The second time was messier, but faster.

## What confused me

The power supply situation. I completely assumed any random USB-C laptop charger would work. Turns out, USB-PD (Power Delivery) negotiation is way weirder than I thought. A lot of modern chargers prioritize pushing 9V or 20V for laptops, and they might not reliably step down to deliver a clean 5V at 3A for a single board computer that expects exactly that baseline. 

I spent probably 40 minutes going down a deep forum rabbit hole about this, reading horror stories about brownouts under load. Ended up deciding to just stick to the dedicated 5V/3A supply I bought specifically for this. Better safe than sorry.

I also kept second-guessing whether that M.2 slot on the bottom of the board would actually work for an NVMe drive, or if it was SATA only. I couldn't get a straight answer from the first two wiki pages I found. I left it as an open question for now since I don't actually need it yet anyway.

## Tomorrow

The goal is to set up the repository properly and read through the Ente architecture so I actually understand the software stack I'm building before the board even boots for the first time.
