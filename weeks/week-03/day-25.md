# Day 25: Week 03 Retrospective — The Stack Lives

*September 15, 2026*

Monday evening. End of Week 03. I'm sitting at my desk looking at two terminal windows. The left one shows the board's Golden Signals — 348 MB memory, 26% disk, load 0.14, CPU at 49°C. The right one shows the Ente app on my phone, connected to `192.168.1.150:8080`, displaying an empty gallery with a green "Connected" indicator. The server is running. The app sees it. The pipeline from phone to database to object store is wired end to end.

Six days ago, the ROCK 3C was a hardened Linux box with great network diagnostics but no application workload. Now it's running three containerized services: PostgreSQL holding user metadata and encryption key bundles, Garage serving the S3 API for encrypted blob storage, and Museum providing the HTTP API that the phone app talks to. All hardened. All health-checked. All persisting data on the USB SSD.

The roadmap's exit criteria for Week 03 is: "Hand-draw the service graph from memory and explain what each service does, where its data lives, how the others reach it, and what happens when each one dies."

I can do that now.

**PostgreSQL** stores metadata. User accounts, album structures, sharing permissions, and the encrypted key bundles that unlock the photo files. Its data lives in the `postgres-data` Docker volume on the SSD. Museum reaches it at `postgres:5432` via Docker's bridge DNS. When Postgres dies, Museum loses auth and metadata queries, but Garage continues serving cached photos. Docker restarts Postgres in ~3 seconds; Museum's connection pool auto-recovers in ~10 seconds.

**Garage** stores encrypted photo blobs. Every photo the phone uploads is encrypted client-side with XChaCha20-Poly1305 before it leaves the device, then stored as an S3 object in the `b2-eu-cen` bucket. Garage's metadata lives in `garage-meta` (SQLite), blob data in `garage-data`. Museum reaches it at `garage:3900`. When Garage dies, uploads and downloads fail, but metadata operations continue. Docker restarts Garage in ~3 seconds; the cluster layout persists, so no re-initialization is needed.

**Museum** is the API gateway. It authenticates users via JWT tokens, routes upload/download requests between the phone and Garage, and manages the metadata in Postgres. Its data volume holds server-side transient state. The phone reaches it at `192.168.1.150:8080`. When Museum dies, the app loses its API entirely. Docker restarts it in ~5 seconds.

Yesterday's failure lab proved all three scenarios empirically. I didn't just read about what happens when services die — I killed them and watched the cascade.

The most important lesson of Week 03 wasn't any specific Docker command. It was the discipline of the build order. The roadmap insisted on a sequence: SSD first, stock quickstart second, Garage swap third, account registration fourth, hardening fifth. Each step built on the previous one. Each step produced a known-good baseline. When the Garage swap broke DNS resolution (it didn't, but if it had), I would have known instantly that it was the swap that caused the break, not some earlier misconfiguration lost in a two-hour marathon session.

This is how production systems are built. One change at a time. One verification at a time. Never two unknowns simultaneously.

Today I wrote the formal retrospective and the weekly article. Week 04 starts the real challenge: storage architecture, backup strategy, and preparing the SSD to handle a real photo library.
