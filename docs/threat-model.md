# Threat Model & Security Architecture (STRIDE Analysis)

This document establishes the formal threat model for the `sdrive` personal photo backup appliance. We evaluate adversary capabilities, system trust boundaries, and mitigation strategies using the Microsoft **STRIDE** methodology.

---

## 1. Trust Boundaries & Adversary Profiles

```
+-----------------------------------------------------------------------------+
| TRUST ZONE 1: Mobile Client (Fully Trusted)                                 |
| - Master Passphrase / Derived Symmetric Keys (Argon2id)                     |
| - Plaintext Photos, Unencrypted EXIF Data, Local Facial Recognition Models  |
+-----------------------------------------------------------------------------+
                                     |
                [ BOUNDARY 1: Transport Layer (Untrusted) ]
                                     |
+-----------------------------------------------------------------------------+
| TRUST ZONE 2: Transport & Network Overlay                                   |
| - ISP / Cellular Carrier / Public Wi-Fi (Untrusted, Eavesdropping Risk)     |
| - Tailscale Mesh Overlay (WireGuard P2P Encrypted, Trusted Transport)       |
+-----------------------------------------------------------------------------+
                                     |
             [ BOUNDARY 2: Physical Host Appliance (Semi-Trusted) ]
                                     |
+-----------------------------------------------------------------------------+
| TRUST ZONE 3: sdrive Appliance (Radxa ROCK 3C)                              |
| - Control Plane: Go `museum` Daemon + PostgreSQL 16 (Encrypted Meta Only)   |
| - Data Plane: Rust `Garage` S3 Daemon (Raw Ciphertext Blobs Only)           |
| - Physical Hardware: Zero Master Keys, Zero Plaintext Storage               |
+-----------------------------------------------------------------------------+
```

### Adversary Capabilities Considered:
1. **The Physical Burglar / Hostile Forensic Analyst:** Gains physical possession of the powered-off or running hardware appliance.
2. **The Malicious ISP / Network Eavesdropper:** Inspects, alters, or intercepts packets on public or cellular Wi-Fi.
3. **The Compromised Network Peer:** An attacker controls an adjacent device on the same local LAN.
4. **The Malicious Storage Daemon / Insider:** An attacker compromises the underlying object storage daemon or host OS.

---

## 2. STRIDE Threat Matrix & Defenses

| Threat Category | Potential Attack Vector | Impact | sdrive Mitigation & Countermeasure |
|---|---|---|---|
| **S — Spoofing** | Adversary attempts to impersonate the mobile client to upload or delete photos. | High | **Dual Authentication:** Client must present a valid JWT session token to `museum` over mTLS/TLS. S3 uploads require a valid HMAC-SHA256 signature generated with the server's private secret. |
| **T — Tampering** | Adversary alters ciphertext blobs in storage or injects malicious payloads over the wire. | Critical | **Authenticated Encryption (AEAD):** All photos are encrypted with `XChaCha20-Poly1305`. Any single-bit tampering with the ciphertext causes authentication tag verification to fail on the handset during retrieval, immediately rejecting the blob. |
| **R — Repudiation** | User denies uploading specific photos or altering an album. | Low | **Signed Audit Log:** `museum` records all state transitions and object hashes in transactional PostgreSQL logs. |
| **I — Information Disclosure** | Adversary steals the physical appliance from the user's home. | Catastrophic (in traditional self-hosting) | **Zero-Knowledge Architecture:** The server never receives, generates, or stores the decryption keys. All data at rest in `Garage` is opaque ciphertext. Without the user's master passphrase (held exclusively in the user's head / phone Secure Enclave), physical drive dumps yield zero plaintext data. |
| **D — Denial of Service** | Malicious actor spams the appliance with oversized uploads to exhaust flash storage. | Medium | **Pre-signed URL Quota Checks:** `museum` enforces quota verification *before* generating a pre-signed PUT URL. Pre-signed URLs enforce strict `content-length-range` S3 headers and 10-minute TTLs. |
| **E — Elevation of Privilege** | Attacker exploits an unpatched daemon to gain root access to the Linux host. | High | **Least Privilege & Process Isolation:** Daemons (`garage`, `museum`, `postgres`) run under dedicated unprivileged system users (`sdrive-garage`, `sdrive-museum`). Systemd services enforce `ProtectSystem=strict`, `ProtectHome=yes`, `NoNewPrivileges=yes`, and `PrivateTmp=yes`. |

---

## 3. Cryptographic Primitives & Key Management

### Key Derivation Function (KDF)
- **Algorithm:** `Argon2id` (v13)
- **Parameters:** Memory: 64MB ($m=65536$), Iterations: $t=3$, Parallelism: $p=4$.
- **Purpose:** Derives master symmetric key from human passphrase, resistant to GPU/ASIC brute-force attacks.

### Symmetric File Encryption
- **Algorithm:** `XChaCha20-Poly1305` Construction (IETF / libsodium).
- **Key Size:** 256 bits (32 bytes).
- **Nonce:** 192 bits (24 bytes, randomly generated per object chunk). Eliminates nonce-reuse risk.
- **Auth Tag:** Poly1305 128-bit one-time authenticator.

### Pre-Signed URL Authorization
- **Algorithm:** AWS Signature Version 4 (SigV4) using `HMAC-SHA256`.
- **TTL:** 600 seconds (10 minutes max expiration).
- **Scope:** Restricted to a single, specific object UUID path within the target bucket.
