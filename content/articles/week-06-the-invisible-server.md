# The Invisible Server: Defense in Depth for Home Infrastructure

*By Pratyush Chaudhary · October 8, 2026 · 9 min read*

---

## 1. The Home Server Fallacy

There is a dangerous assumption in the self-hosting community: *“It's on my home network, so it's safe.”*

This fallacy leads to architecture where the reverse proxy trusts the local LAN, the API trusts the reverse proxy, and the database trusts the API. The moment an attacker compromises a single smart lightbulb or IoT vacuum cleaner on your WiFi network, the entire castle falls.

For the `sdrive` appliance, I wanted a different architecture. I wanted a server that assumes the local network is hostile. A server that is physically sitting on my desk, connected to my router, but is mathematically invisible to both.

This week, I finished building it.

---

## 2. The Docker-UFW Trap

The journey started with a terrifying discovery. 

Earlier in the project, I configured `ufw` (Uncomplicated Firewall) to `default deny incoming`. I ran `ufw status` and saw that everything was locked down except SSH (port 22). Feeling secure, I mapped Caddy's HTTPS port in `docker-compose.yml` (`443:443`).

Then I ran a port scan from another machine on my local WiFi. Port 443 was wide open.

This is the Docker-UFW trap. Docker manipulates `iptables` directly to route traffic to containers. It inserts its rules into the `FORWARD` chain, executing *before* UFW's `INPUT` drop rules. To a sysadmin looking at `ufw status`, the system appears locked down. To an attacker on the LAN, every published Docker port is exposed.

I could have fixed this by binding Docker to localhost (`127.0.0.1:443`), but that breaks Tailscale routing. Instead, I wrote a strict interface-binding script (`sdrive-firewall.sh`). 

The rule is simple: **Drop everything from the physical network interface (`end0`), no matter what Docker says.** Allow traffic *only* on the virtual `tailscale0` interface. 

The result? The server silently drops all packets from the local WiFi. It doesn't send a TCP Reset. It is a black hole.

---

## 3. The Caddy TLS Envelope

If you have a valid Tailscale key, your packets are allowed through the firewall. But they don't hit the application. They hit Caddy.

I chose Caddy over NGINX for one specific reason: memory safety. NGINX is written in C. It is undeniably fast, but it is historically susceptible to memory corruption (buffer overflows). Caddy is written in Go. It trades a few megabytes of RAM for total immunity to buffer overflows. Because Caddy is the *only* component parsing HTTP requests from the Tailnet, memory safety is paramount.

Caddy terminates the TLS 1.3 connection using a publicly trusted Let's Encrypt certificate (provisioned via Tailscale's DNS-01 challenge). It enforces Strict-Transport-Security (HSTS), strips identifying headers, and prevents MIME-sniffing. 

Crucially, I had to explicitly tune Caddy's timeout windows for mobile behavior. When a phone uploads a 500 MB 4K video over a weak 4G connection, it takes 10 minutes. Most reverse proxies assume any connection taking 10 minutes is a "Slowloris" attack and terminate it. By extending `read_body` to 10 minutes and increasing the `max_size` to 1 GB, Caddy gracefully handles massive, slow uploads while streaming the bytes directly to the backend without buffering them in RAM.

---

## 4. The Airgapped Backend

Behind Caddy sits the Ente Museum API. 

In Week 03, Museum had a published port (`8080:8080`). In Week 06, I deleted that port mapping entirely. Museum now exists exclusively on the internal Docker bridge network (`172.x.x.x`). 

It is physically impossible to route a packet from the host OS, the Tailnet, or the local LAN directly to the API. The only way in is for Caddy to proxy it.

And Museum doesn't trust Caddy. Every API request must carry a cryptographic JWT token proving the user authenticated via the Secure Remote Password (SRP) protocol.

---

## 5. The Final Equation

If you want to view a photo on the sdrive appliance, here is what you have to break:

1. **The Network (Tailscale):** You must steal a Curve25519 private key authenticated by the Tailscale control plane to pass the UFW firewall.
2. **The Transport (Caddy):** You must breach TLS 1.3 to view the traffic, or find a zero-day in Caddy's memory-safe Go HTTP parser.
3. **The Application (Museum):** You must forge a cryptographically signed JWT token, or exploit an authentication bypass in the API.
4. **The Data (Ente E2EE):** Even if you do all of the above, dump the entire PostgreSQL database, and extract the 400 GB of Garage S3 blobs... you lose. Every photo is encrypted with XChaCha20-Poly1305. The decryption keys never leave the user's phone.

This is Defense in Depth. It assumes the network is hostile, the proxy is flawed, the API has bugs, and the physical hardware will be stolen. 

It is the invisible server. And it works beautifully.

---

*This article is part of the **`sdrive` Build Log** — a 12-week public engineering series documenting the ground-up development of an end-to-end encrypted home photo backup appliance. Track the daily commits on GitHub: [github.com/PrUcky/sdrive-build-log](https://github.com/PrUcky/sdrive-build-log).*
