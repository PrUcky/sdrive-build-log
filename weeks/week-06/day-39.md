# Day 39: The Firewall Lockdown — Trusting the Tailnet

*October 5, 2026*

Yesterday I deployed Caddy and sealed the Docker bridge. The Museum API is no longer listening on port 8080. Caddy is terminating TLS on port 443. But there was a lingering architectural flaw: Docker manipulates iptables directly. When I mapped `443:443` in `docker-compose.yml`, Docker bound Caddy to `0.0.0.0:443`, exposing it to both the Tailscale interface (`tailscale0`) and the physical LAN interface (`end0`).

I don't want the appliance responding to HTTPS requests from the local LAN. I want it completely dark to everything except the Tailnet.

Today, I wrote `scripts/sdrive-firewall.sh` to enforce this at the host level using UFW.

## Fixing Docker's iptables Override

Docker's interaction with UFW is notoriously frustrating. By default, Docker inserts rules at the top of the `FORWARD` chain, completely bypassing UFW's `INPUT` rules. This means UFW's `deny incoming` policy doesn't actually stop traffic hitting published Docker ports.

To fix this securely without breaking container DNS, I relied on UFW's interface-specific rules. The new firewall script resets UFW and builds a strict, interface-bound policy:

1. **Deny everything by default.**
2. **Allow SSH (22) only on the physical LAN interface** (`end0`). This ensures I can always manage the board locally if Tailscale breaks.
3. **Allow UDP 41641** — the encrypted WireGuard endpoint for Tailscale to function.
4. **Allow everything on `tailscale0`** — trust the Tailnet.

```bash
root@sdrive:~# ./scripts/sdrive-firewall.sh
======================================================================
 sdrive — Applying Strict UFW Rules
======================================================================
Detected physical interface: end0
Resetting UFW to default state...
Setting default policies...
Allowing SSH on local LAN interface (end0)...
Allowing Tailscale tunnel traffic (UDP 41641)...
Allowing all authenticated traffic on the tailnet (tailscale0)...
Enabling UFW...
Firewall is active and enabled on system startup
======================================================================
```

## Proving the Perimeter

I ran three tests to verify the perimeter acts exactly as designed.

**Test 1: LAN access to Caddy (Should Fail)**
From my desktop on the same WiFi network, bypassing Tailscale, I tried to hit the ROCK 3C's local IP on port 443.

```bash
C:\> curl --connect-timeout 3 -vk https://192.168.1.150
*   Trying 192.168.1.150:443...
* Connection timed out after 3009 milliseconds
* Closing connection 0
curl: (28) Connection timed out after 3009 milliseconds
```
Perfect. The packets hit the physical interface (`end0`) and are silently dropped by UFW before they reach Docker. The server doesn't even send a TCP RST. It is completely dark.

**Test 2: Tailscale access to Caddy (Should Pass)**
From the same desktop, using the MagicDNS hostname (which resolves to the `100.x.y.z` Tailscale IP).

```bash
C:\> curl -s https://sdrive.tail12345.ts.net/health
{"status":"ok"}
```
The packets enter the physical interface encrypted as UDP 41641, bypass UFW's drop rule because 41641 is explicitly allowed, get decrypted by the kernel's WireGuard module, emerge on the `tailscale0` interface, pass the UFW `allow in on tailscale0` rule, and reach Caddy.

**Test 3: LAN access to SSH (Should Pass)**

```bash
C:\> ssh PrUcky@192.168.1.150
PrUcky@192.168.1.150's password:
```
SSH works locally. This is the emergency backdoor. If Tailscale's coordination server goes down, or if the key expires, I can still access the board from the local network to fix it.

## The Architectural Win

The combination of Tailscale, Caddy, and UFW creates an incredibly resilient security posture.

- To an attacker on my local WiFi, the ROCK 3C looks like a black box with one open port (SSH).
- To an attacker on the open internet, the ROCK 3C doesn't exist at all (blocked by CGNAT).
- To an authorized phone on the Tailnet, the ROCK 3C looks like a standard cloud API answering HTTPS requests.

Tomorrow, I'm documenting the Caddy decision in an ADR and tuning the Caddyfile for large video uploads. We're approaching the final production configuration.
