# Tailscale Configuration Reference

*Reference: weeks/week-05/day-32.md*

Complete guide for the Tailscale overlay network on the sdrive appliance.

---

## Network Topology

```
┌─────────────────┐       ┌────────────────────────┐       ┌─────────────────┐
│  Phone          │       │  Tailscale Control    │       │  ROCK 3C        │
│  100.100.64.11  │──────│  (coordination only)  │──────│  100.100.42.17  │
│  Ente App       │       │  login.tailscale.com  │       │  Museum :8080    │
└────────┬────────┘       └────────────────────────┘       └────────┬────────┘
         │                                                         │
         │              WireGuard Tunnel (direct)                  │
         └─────────────────────────────────────────────────┘
                 (or DERP relay if direct fails)
```

**Data path:** Phone → WireGuard tunnel → ROCK 3C. Photos never touch Tailscale's servers.  
**Control path:** Key exchange and peer discovery only. No data.

---

## Tailscale IPs (Tailnet)

| Device | Tailscale IP | Role |
|---|---|---|
| ROCK 3C (sdrive) | `100.100.42.17` | Server: Museum, Garage, PostgreSQL |
| Desktop | `100.100.89.3` | Admin: SSH, diagnostics |
| Phone (Pixel) | `100.100.64.11` | Client: Ente app |

These IPs are **stable** — they persist across reboots, network changes, and location changes.

---

## Connection Paths

| Scenario | Path | Latency | Notes |
|---|---|---|---|
| Same LAN (WiFi) | Direct peer-to-peer | ~3 ms | Hole-punched through local router |
| Mobile data (4G/5G) | Direct (hole-punched) | ~45 ms | Through ISP CGNAT + carrier NAT |
| Restrictive network | DERP relay | ~80–150 ms | Hotel WiFi, corporate firewall |
| Both behind hard NAT | DERP relay | ~100–200 ms | Worst case, still encrypted |

Tailscale automatically selects the best path. No manual configuration needed.

---

## Firewall Rules

```bash
# UFW rules for Tailscale
ufw allow in on tailscale0           # Allow all tailnet traffic
# No specific port rules needed — tailnet IS the access control

# Full rule set
ufw status
# 22/tcp          ALLOW  192.168.1.0/24     (SSH from LAN)
# 8080/tcp        ALLOW  192.168.1.0/24     (Museum from LAN)
# Anywhere on tailscale0  ALLOW  Anywhere   (all services via tailnet)
```

**Security model:** The `tailscale0` interface only accepts traffic from authenticated tailnet peers. Unauthenticated packets are dropped at the WireGuard layer before reaching UFW.

---

## Endpoints for Ente App

| Network | Server URL | When to Use |
|---|---|---|
| Local WiFi | `http://192.168.1.150:8080` | At home, fastest |
| Tailscale (anywhere) | `http://100.100.42.17:8080` | Away from home |
| MagicDNS (future) | `http://sdrive.tail*.ts.net:8080` | Human-readable |

> **Recommendation:** Always use the Tailscale IP (`100.100.42.17`). It works both on LAN and remotely. When on the same LAN, Tailscale detects this and routes directly.

---

## Diagnostics

```bash
# Status and peer list
tailscale status

# Check connection to a specific peer
tailscale ping <peer-name>

# NAT traversal diagnostics
tailscale netcheck

# Detailed debug info
tailscale debug netmap

# Check which DERP relay is being used
tailscale netcheck 2>&1 | grep -i "preferred DERP"

# Full health check
./scripts/sdrive-tailscale-health.sh
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `tailscale status` shows "Stopped" | Daemon not running | `sudo systemctl start tailscaled` |
| "NeedsLogin" state | Auth expired | `tailscale up` and re-authenticate |
| High latency (>100ms on LAN) | Using DERP relay instead of direct | Check `tailscale netcheck` for NAT type |
| Phone can't reach 100.100.42.17 | Tailscale app not running on phone | Open Tailscale app, ensure VPN is active |
| Upload works on WiFi but not mobile | Phone's Tailscale VPN not enabled | Android: check VPN consent dialog |
| "key expired" error | Tailscale key needs rotation | `tailscale up --reset` |

---

## Resource Impact

| Metric | Value |
|---|---|
| tailscaled memory | 24 MB |
| Kernel WireGuard | ~5 MB (shared) |
| CPU overhead (idle) | ~0.04% |
| CPU overhead (tunnel active) | < 1% (kernel crypto) |
| Network listeners | UDP :41641 (WireGuard endpoint) |
| Bandwidth overhead | ~0.1% (WireGuard header per packet) |
