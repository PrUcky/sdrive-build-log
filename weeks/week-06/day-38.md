# Day 38: Sealing the Perimeter — Deploying Caddy and Enforcing HTTPS

*October 4, 2026*

Gate A is officially passed today. The embedded network proof is solid, and the demo works from any network. But as of yesterday, the traffic inside the WireGuard tunnel was plain HTTP. Today, kicking off Week 06, I deployed the Caddy reverse proxy, enabled TLS termination with the Tailscale-provisioned Let's Encrypt certificates, and completely sealed the backend.

## The Docker Compose Surgery

The goal wasn't just to add Caddy. The goal was to force all traffic through Caddy by removing Museum's direct public port.

In `compose/docker-compose.yml`, I made two critical changes. First, I added the Caddy service using the `caddy:2-alpine` image. Second, I stripped the `ports: ["8080:8080"]` directive from Museum entirely.

```yaml
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ../config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ../certs:/etc/caddy/certs:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      museum:
        condition: service_healthy
```

By removing port 8080 from Museum, Museum now only exists on the `internal` Docker bridge network. It is physically impossible to reach the Go API directly from the host, the Tailnet, or the local LAN. The only way in is through Caddy on port 443.

## Hardening the Proxy

Caddy is the new front door, which means it gets the same aggressive hardening treatment as the rest of the stack:

1. **Memory Limits:** Capped at 256 MB. Caddy is lightweight (written in Go), and since we disabled its automatic ACME certificate management (Tailscale handles it), it barely uses 30 MB at rest.
2. **Read-Only Rootfs:** `read_only: true`.
3. **No New Privileges:** `security_opt: ["no-new-privileges:true"]`.
4. **Tmpfs Mounts:** Because the root filesystem is read-only, I had to mount tmpfs volumes for `/tmp`, `/run`, and crucially, `/var/log/caddy`. The Caddyfile is configured to write access logs to `/var/log/caddy/access.log`, which would crash the container on a read-only filesystem. A 64 MB tmpfs mount solves this perfectly.

## The Certificate Mounts

In Week 05, I provisioned the Let's Encrypt certificates via `tailscale cert sdrive.tail12345.ts.net`. I created a `certs/` directory at the project root and copied the generated `.crt` and `.key` files there.

The Compose file mounts this directory read-only into Caddy at `/etc/caddy/certs`. Caddy reads the certificate, binds to 443, and terminates the TLS connection, forwarding plain HTTP to Museum over the secure Docker bridge.

## Bringing Up the Sealed Stack

I ran `docker compose up -d` and watched the stack rebuild. Caddy started instantly.

```bash
root@sdrive:~# docker compose ps
NAME                      IMAGE                      STATUS                   PORTS
sdrive-stack-caddy-1      caddy:2-alpine             Up 2 minutes             0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
sdrive-stack-garage-1     dxflrs/garage:v1.0.1       Up 2 minutes (healthy)
sdrive-stack-museum-1     ghcr.io/ente-io/server     Up 2 minutes (healthy)
sdrive-stack-postgres-1   postgres:16-bookworm       Up 2 minutes (healthy)
```

Look at the `PORTS` column. Museum and Garage have no published ports. Only Caddy exposes 80 and 443. The perimeter is sealed.

I tested the old HTTP endpoint to verify the seal:

```bash
root@sdrive:~# curl -s http://100.100.42.17:8080/health
curl: (7) Failed to connect to 100.100.42.17 port 8080: Connection refused
```

Connection refused. Exactly what I want.

## The HTTPS Test

I tested the new MagicDNS HTTPS endpoint from my desktop:

```bash
C:\> curl -v https://sdrive.tail12345.ts.net/health
*   Trying 100.100.42.17:443...
* Connected to sdrive.tail12345.ts.net (100.100.42.17) port 443
* ALPN: curl offers h2, http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=sdrive.tail12345.ts.net
*  start date: Oct  2 12:45:11 2026 GMT
*  expire date: Dec 31 12:45:10 2026 GMT
*  subjectAltName: host "sdrive.tail12345.ts.net" matched cert's "sdrive.tail12345.ts.net"
*  issuer: C=US; O=Let's Encrypt; CN=R3
*  SSL certificate verify ok.
> GET /health HTTP/2
> Host: sdrive.tail12345.ts.net
> User-Agent: curl/8.4.0
> Accept: */*
>
< HTTP/2 200
< strict-transport-security: max-age=31536000; includeSubDomains
< x-content-type-options: nosniff
< x-frame-options: DENY
<
{"status":"ok"}
```

Beautiful. A full TLS 1.3 handshake, a publicly trusted Let's Encrypt certificate, ALPN negotiating HTTP/2, and all the security headers from the Caddyfile (`strict-transport-security`, `nosniff`, `DENY`).

## The Final Ente App Configuration

I opened the Ente app on my phone and changed the server URL one last time:

```
Server: https://sdrive.tail12345.ts.net
```

I took a photo and watched the upload. It succeeded seamlessly.

The defense-in-depth architecture is complete. The photo is encrypted on the phone with XChaCha20-Poly1305. It's sent over an HTTPS connection encrypted with TLS 1.3. That HTTPS connection is routed through a Tailscale WireGuard tunnel encrypted with ChaCha20-Poly1305. Three layers of modern cryptography. And not a single port exposed to the open internet.

Tomorrow, I'll update the UFW rules to lock down port 443 specifically to the `tailscale0` interface, ensuring Caddy can't be reached even from the local LAN without the VPN, making the Tailnet the absolute ultimate source of truth for access.
