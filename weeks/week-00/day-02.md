# Day 02 — The Stack and the Secret

**Week:** 00 · **Date:** 2026-08-20 · **Hours:** ~6

Today was almost entirely reading. My eyes genuinely hurt by the end of it.

## What I actually did

The main goal today was to understand the Ente architecture before I even think about touching any code or software. I’ve been visualizing this whole project as "basically a cloud photo app running locally," but it turns out that mental model is completely wrong, and I wanted to fix it before it caused real confusion later down the line.

Here is the massive key takeaway: `museum` (the Go application server) never actually sees a photo. Not even once. 

What actually happens is wild. The phone encrypts the photo *on the device itself* before anything even hits the network. Then, the phone pings `museum` and basically asks for permission to upload. Museum says, "Fine, here is a pre-signed URL, you have 5 minutes to use it." The phone then takes that encrypted blob of ciphertext and pushes it directly to MinIO (the storage backend). Museum isn't in that data path at all. 

I kept reading that sentence over and over and not quite believing it. I spent maybe an hour just re-reading the Ente source README and a couple of old forum posts to make sure I had it right. The implication here is huge: because the server never decrypts anything, it also never needs to generate thumbnails, transcode video, or run heavy AI face detection. All of that compute-heavy lifting stays on the phone. That is exactly why this entire stack can comfortably fit under 1GB of RAM on a board that costs like ₹6k. 

I spent the rest of the afternoon setting up the git repository properly. I created all the week folders, pushed a `.gitignore`, and set up `.gitleaks.toml` (configured to run as a pre-commit hook). 

The gitleaks thing feels super important. I was reading a horror story on Reddit about someone who accidentally pushed a test API key, realized their mistake, and deleted the commit 10 minutes later. They still had their AWS account compromised for thousands of dollars because automated bots had already cloned the repo in that tiny 10-minute window. The key lives in the git history forever even after you "delete" the file. So I'd much rather have a hook that aggressively refuses to let me commit a secret in the first place.

I also went ahead and created the necessary accounts: Tailscale (I'm on the free tier for now, might switch to Headscale way later if I feel brave), Hashnode for my weekly long-form articles, and I finally forced myself to set up the Twitter/X account I've been putting off.

## What confused me

The pre-signed URL concept took way longer to click in my head than I expected. I kept thinking: if `museum` doesn't see the photo passing through, how does it know the upload actually succeeded? 

Turns out, the client just calls back after the upload is done with a confirmation, and *that* is the exact moment museum records that the object exists. So museum's entire model of the world is basically: "I know this encrypted blob exists at this MinIO path, but I have absolutely no idea what's inside it." Which is exactly the point of end-to-end encryption.

Also, doing a simple `git push` from my local Windows machine kept hanging endlessly. Turns out my Windows credential manager doesn't have a GitHub token stored for this specific repo, so it was just silently failing to authenticate. I bypassed it by pushing via the GitHub API for now. It's a minor annoyance, but I logged it here because I know I'll forget about it otherwise. I'll fix it properly during Week 1 when I'm setting up my real dev environment.

## Tomorrow

SSH keypair generation, and I need to start actually reading about Armbian before I try to boot this board. I also still need to figure out that M.2/NVMe question I left open yesterday. I found a forum post that suggests the slot is PCIe 2.0 x1, which means it should technically work for NVMe but at a heavily reduced speed. Honestly, that's probably good enough for v1.
