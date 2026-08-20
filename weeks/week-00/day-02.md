# Day 02 — The Stack and the Secret

**Week:** 00 · **Date:** 2026-08-20 · **Hours:** 6

## What I Did & Learned
- **Deep-read the Ente architecture:** Understood how sdrive's server (`museum`) works: it handles accounts and metadata in Go but never receives a raw photo. The phone encrypts the photo locally before upload, then pushes the ciphertext blob directly to MinIO using a pre-signed URL that `museum` issues. The server is blind to the content by design.
- **Why this changes the hardware requirement:** Because the server stores only ciphertext and never generates thumbnails, transcodes video, or runs face detection, the compute requirement drops dramatically. That's why an LPDDR4 board with 4–8 GB RAM is sufficient for a household library that would choke a comparable self-hosted Immich stack.
- **Component roles mapped out:**
  - `museum` — Go application server. Accounts, sharing metadata, pre-signed URLs. Never sees a photo.
  - `PostgreSQL` — Metadata DB only. Stays small even for large libraries because it stores IDs and keys, not blobs.
  - `MinIO` — S3-compatible object store. Holds the encrypted blobs. The only component that grows with storage.
  - `Caddy` — Reverse proxy and automatic TLS. Terminates HTTPS so nothing else has to.
  - `Tailscale` — WireGuard mesh daemon. Makes the box reachable from the internet without a static IP or port forwarding.
- **Git and GitHub as a daily habit:** Created the `sdrive-build-log` repository, initialised it with the structure from the roadmap (all week folders, `.gitignore`, `.gitleaks.toml`), and pushed the first real commit. Understood the commit → push loop, what a remote is, and why public commits create accountability.
- **Why never commit secrets:** Even a token pushed for one second and then deleted is compromised — it lives in reflog, in any mirror that cloned it in that window, and in GitHub's own audit log. `gitleaks` is configured as a pre-commit hook to catch this before it leaves the machine.
- **Accounts created:** GitHub (already had), Tailscale (free personal tier), Hashnode (for weekly articles), Twitter/X (for daily posts).

## What Broke & What Confused Me
- **Why does `museum` issue the pre-signed URL if it can't see the photo?** Took a while to get this right. `museum` doesn't need to see the content — it just needs to tell MinIO "let this client write to this key for the next 5 minutes." It's an authorization token, not a data pipe. The photo bytes go phone → MinIO directly; `museum` only learns that an upload happened when the client calls back to confirm.
- **Git push hanging via HTTPS:** The push from the local machine stalls because the Windows credential manager didn't have a stored GitHub token. Resolved by pushing via the GitHub API instead. Will set up a PAT in the credential store properly during Week 1.

## Benchmark Answers
1. **Why can't `museum` read photos?** It only ever receives pre-signed URL requests and metadata. The actual photo bytes travel directly from the phone to MinIO, encrypted. `museum` has no route to the MinIO bucket contents.
2. **Why does PostgreSQL stay small?** It stores metadata (file IDs, encrypted keys, sharing relationships) — not the blobs themselves. Blobs live in MinIO.
3. **What is a pre-signed URL?** A time-limited URL that grants one specific HTTP operation (PUT/GET) to a specific object in object storage, without requiring the requester to have permanent credentials.
4. **Why does Caddy handle TLS instead of the app?** TLS termination is complex and security-critical. Caddy does it correctly by default and renews certificates automatically via ACME. Mixing TLS logic into application code is a known trap.
5. **Why is a public commit log valuable beyond the code itself?** It creates a dated, immutable record of what was done and when. Investors and technical reviewers can verify the build timeline independently.
