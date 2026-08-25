# Day 02 — The Stack and the Secret

**Week:** 00 · **Date:** 2026-08-20 · **Hours:** ~6.0

Today was an intensive deep dive into software architecture. I spent nearly six uninterrupted hours reading documentation, inspecting Go source code, and sketching state machines. By late afternoon, my eyes were burning from staring at high-contrast terminal windows and GitHub diffs, but the conceptual breakthrough I had today was worth every minute of screen fatigue.

## What I actually did

Going into this project, my mental model of a self-hosted photo backup system was essentially the standard monolithic web application model: the mobile app connects to a REST API, streams the photo over HTTP POST directly to an application server, and the server saves the file to disk while generating thumbnails, extracting EXIF tags, and updating a relational database. That is how traditional applications like Nextcloud and Photoprism operate.

After digging through the official Ente architecture whitepapers and examining the source code for `museum` (Ente’s Go-based backend service), I realized that model is fundamentally incompatible with true zero-knowledge privacy.

In Ente's architecture, `museum` never touches, buffers, or inspects a single byte of raw image data. The application server is deliberately blind. 

Here is the exact technical pipeline that happens when an image is ingested:
1. When a user captures a photograph, the mobile handset generates a cryptographic key locally, derived from the user’s master passphrase using the memory-hard `Argon2id` password hashing algorithm.
2. The phone extracts all metadata (GPS coordinates, capture timestamps, camera settings, color profiles), creates compressed thumbnail previews, and runs any machine-learning facial recognition locally on the phone's dedicated Neural Processing Engine (Apple Neural Engine on iOS or Android NNAPI).
3. The phone encrypts the raw photo, the thumbnails, and the JSON metadata payload locally using `XChaCha20-Poly1305` (an authenticated symmetric cipher with a 192-bit nonce that prevents nonce-reuse collisions).
4. The mobile app establishes a TLS connection to `museum` over the network and requests permission to store a new encrypted object by providing its file size and ciphertext hash.
5. `museum` validates the user's authentication token against PostgreSQL and communicates with the underlying S3-compatible storage backend (MinIO or Garage) to generate an HMAC-SHA256 authenticated **pre-signed PUT URL** with a strict 5-to-15-minute expiration window.
6. `museum` returns this pre-signed URL to the mobile client and immediately drops the connection.
7. The mobile client opens a direct HTTP PUT stream to the storage backend endpoint using the pre-signed URL, pushing the multi-megabyte ciphertext blob directly into the storage bucket without routing a single packet through the Go server runtime memory.
8. Once the storage engine responds with an HTTP 200 OK confirming disk write, the mobile client makes a secondary lightweight API call back to `museum` to commit the encrypted file metadata and album relationships into PostgreSQL.

The implications of this design are enormous for hardware sizing. In a traditional photo server, the host machine requires massive CPU power and gigabytes of RAM to handle concurrent image decoding, OpenCV face detection, and video transcoding whenever multiple devices back up simultaneously. With Ente's client-first architecture, all heavy computational work is distributed to the high-performance smartphone processors already sitting in our pockets. The server’s only responsibility is executing simple SQL queries and issuing cryptographic pre-signed URLs. This means the entire backend stack—PostgreSQL, the Go API daemon, and the object storage engine—can comfortably operate inside 300MB to 500MB of RAM on our modest 4GB Radxa ROCK 3C without ever threatening to invoke the Linux Out-Of-Memory (OOM) killer.

After wrapping up the architectural research, I focused on establishing the public repository footprint. I initialized the Git repository, established the 12-week directory layout, committed a comprehensive `.gitignore` tailored for Go, Rust, and embedded Linux artifacts, and configured `.gitleaks.toml`.

Setting up automated secret scanning before writing a single configuration file felt like a mandatory discipline. I've seen too many post-mortems where a developer accidentally commits a private key or API token, realizes the mistake three minutes later, and attempts to fix it by running `git rm` or `git commit --amend`. What people forget is that Git is an append-only directed acyclic graph (DAG). Unless you perform an aggressive repository history purge and force-push over remote refs, that sensitive string remains forever discoverable in the packfiles. Even worse, automated scanning bots continuously monitor public GitHub event streams; a credential committed publicly is often scraped, validated, and exploited within thirty seconds of the push. Adding a local Gitleaks pre-commit configuration ensures that the Git hook halts any commit containing high-entropy strings or credential patterns before the ref is ever created.

Finally, I established the external publishing accounts needed to document the build in public over the next twelve weeks: Tailscale (for mesh VPN testing), Hashnode (for long-form weekly technical retrospectives), and a dedicated Twitter/X developer handle.

## What confused me

The pre-signed URL flow caused some serious cognitive friction when I first stepped through the sequence diagrams. I kept asking myself: if `museum` never acts as a proxy for the upload stream, how does it maintain transactional integrity? What prevents orphaned records in PostgreSQL if the client crashes halfway through uploading a 50MB video directly to the S3 bucket?

The answer lies in Ente's two-phase commit protocol. `museum` does not record the existence of a file in the active album hierarchy when it generates the pre-signed URL. It only logs an uncommitted, pending upload record with a strict time-to-live (TTL). Only after the client receives an HTTP 200 OK from the storage layer and successfully submits the final confirmation payload does `museum` execute the SQL transaction that officially indexes the photo. If an upload fails midway, the orphaned blob in S3 is cleaned up by background garbage collection routines without corrupting the database state.

I also ran into a frustrating local development issue on my Windows workstation. When I attempted to run `git push origin main` from PowerShell, the command hung indefinitely without returning an error or showing a progress bar. After debugging process explorer, I discovered that the Windows Git Credential Manager was failing to display its OAuth modal in the background, causing the terminal process to wait forever on an invisible stdin prompt. I worked around the hang by pushing directly via the GitHub API tools, but I made a note to reconfigure my local SSH agent and credential helper once we transition to Linux in Week 01.

## Tomorrow

Tomorrow is all about cryptographic primitives and administrative access. I will generate the dedicated Ed25519 SSH keypair that will authenticate all administrative sessions to the board, analyze why Edwards-curve cryptography is superior to RSA for embedded systems, and test the Gitleaks detection engine with canary tokens.
