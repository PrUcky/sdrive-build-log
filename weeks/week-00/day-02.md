# Day 02 — The Stack and the Secret

**Week:** 00 · **Date:** 2026-08-20 · **Hours:** ~6

Today was a lot of reading. My eyes hurt.

## What I actually did

The main goal was understanding the Ente architecture before I touch any software. I've been thinking of this as "basically a cloud photo app running locally" but that mental model isn't quite right, and I wanted to fix it before it caused confusion later.

The key thing: `museum` (the Go app server) never sees a photo. Not even once. What actually happens is the phone encrypts the photo *on device* before anything hits the network, then asks `museum` for permission to upload. Museum says "fine, here's a pre-signed URL, you have 5 minutes." The phone then uploads the ciphertext blob directly to MinIO. Museum isn't in that data path at all.

I kept reading that sentence and not quite believing it. Spent maybe an hour re-reading the Ente source README and a couple of old forum posts to make sure I had it right. The implication is significant though: because the server never decrypts anything, it also never needs to generate thumbnails, transcode video, do face detection, any of that. All the heavy compute stays on the phone. That's why this whole stack fits under 1GB of RAM on a board that costs ₹6k.

Spent the rest of the afternoon setting up the repository properly. Created all the week folders, pushed `.gitignore` and `.gitleaks.toml` (configured to run as a pre-commit hook). The gitleaks thing is important — I read a horror story about someone who pushed a test API key, deleted the commit 10 minutes later, and still had their account compromised because someone had already cloned the repo in that window. The key lives in git history even after you "delete" it. So I'd rather have a hook that refuses to commit it in the first place.

Also created accounts: Tailscale (free tier, will switch to Headscale later), Hashnode for weekly articles, and finally got around to setting up the Twitter/X account I've been putting off.

## What confused me

The pre-signed URL thing took longer to click than I expected. I kept thinking: if `museum` doesn't see the photo, how does it know the upload succeeded? Turns out the client calls back after the upload with a confirmation, and *that* is when museum records that the object exists. So museum's model of the world is: "I know this encrypted blob exists at this MinIO path, but I have no idea what's in it." Which is exactly the point.

Also the git push from my local machine kept hanging. Turns out my Windows credential manager doesn't have a GitHub token stored for this repo. Pushed via API for now, will fix this properly during Week 1 when I'm setting up the dev environment properly. Minor annoyance but logged it because I'll forget.

## Tomorrow

SSH keypair generation and starting to actually read about Armbian before the board boots. Also need to figure out the M.2/NVMe question I left open yesterday — found a forum post that suggests the slot is PCIe 2.0 x1 which should work for NVMe but at reduced speed. Good enough for v1.
