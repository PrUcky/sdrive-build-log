# Day 31: Week 04 Retrospective — The Data Is Real Now

*September 23, 2026*

Week 04 is done. I'm looking at the Ente app on my phone showing 1,060 photos and 10 videos, all backed up to the ROCK 3C sitting on my desk. The gallery thumbnail grid loads in under 200 ms. Tapping a photo brings up the full resolution in 400 ms. Every one of those photos traveled through the encryption pipeline — XChaCha20-Poly1305 on the phone, JWT authentication at Museum, S3 PUT to Garage, Blake2-hashed block files on the SSD — and every one of them comes back intact.

This week transformed the appliance from an empty container stack that returned `{"status":"ok"}` to a running photo backup service with real data, real performance numbers, and real automated backups. The difference between Week 03 and Week 04 is the difference between "the server is up" and "the server is doing its job."

The storage architecture document I wrote yesterday is the most important artifact of this week. It's the single reference that explains where every byte lives, how it got there, and what happens if it disappears. If I got hit by a bus tomorrow, someone could reconstruct the entire system from that document, the Compose files, and the scripts.

Two things surprised me this week. The first was Ente's 5-objects-per-photo structure — I had assumed one S3 object per photo, but the separation of original, thumbnail, metadata, key bundle, and collection reference is architecturally elegant. It means the app can browse your gallery (thumbnails only) without downloading full-resolution originals, which matters enormously on mobile data. The second surprise was how little the system cared about the stress test. 500 photos, two concurrent phones, mixed media with video — the board's load average never exceeded 2.14, temperature never exceeded 62°C, and memory usage peaked at 13.7% of available RAM. The ROCK 3C is dramatically overpowered for a family photo backup server.

The one concern I carry forward is Museum's in-memory blob buffering. A 4K video at 500 MB would push Museum to its 512 MB container memory limit. This isn't a problem for the demo or for most family usage, but it needs addressing before any production deployment with video-heavy users.

Today I wrote the formal retrospective and the weekly article. Week 05 starts the Tailscale overlay network — the piece that makes the appliance accessible from outside the local network.
