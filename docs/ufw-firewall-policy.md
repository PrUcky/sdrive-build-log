# sdrive — UFW Firewall Policy

This document defines the complete inbound firewall policy for the sdrive appliance. All rules follow the principle of **deny by default, allow by exception**, scoped to the minimum network surface required for each service.

---

## Default Policy

| Direction | Action | Rationale |
|---|---|---|
| Incoming | **DENY** | No inbound traffic unless explicitly whitelisted |
| Outgoing | **ALLOW** | Appliance must reach upstream DNS, NTP, APT repos, Tailscale coordination |
| Routed | **DENY** | Board is not a router; no packet forwarding between interfaces |

---

## Inbound Allow Rules

| # | Port | Proto | Source | Service | Deployed In | Notes |
|---|---|---|---|---|---|---|
| 1 | 22 | TCP | `192.168.1.0/24` | OpenSSH | Week 01 | Ed25519 keys only, password auth disabled |
| 2 | 8080 | TCP | `192.168.1.0/24` | Ente `museum` API | Week 03 | Go HTTP backend for metadata and auth |
| 3 | 3900 | TCP | `192.168.1.0/24` | Garage S3 | Week 03 | Rust object storage, pre-signed URL endpoint |
| 4 | 5432 | TCP | `127.0.0.1` | PostgreSQL 16 | Week 03 | Localhost only — `museum` connects over loopback |

---

## IPv6 Policy

IPv6 inbound is **blocked by default** with the following exceptions in `/etc/ufw/before6.rules`:

| ICMPv6 Type | Purpose | Required? |
|---|---|---|
| Neighbour Solicitation | Link-layer address resolution | Yes — kernel requires for local communication |
| Neighbour Advertisement | Response to solicitation | Yes — kernel requires for local communication |
| Router Advertisement | SLAAC prefix delegation | Yes — needed if ISP enables IPv6 in future |

All other inbound IPv6 traffic is silently dropped at the netfilter layer before reaching userspace.

**Rationale:** The board currently has only a link-local `fe80::` IPv6 address. However, if the ISP begins prefix delegation, a globally routable `2xxx:` address could appear without warning. The preemptive block ensures the board remains invisible on the IPv6 internet regardless of upstream ISP changes.

---

## Tailscale Integration (Week 06+)

When the Tailscale WireGuard mesh is deployed, the `tailscale0` virtual interface will carry overlay traffic on `100.64.0.0/10`. Firewall rules for Tailscale-addressed services will be added as:

```bash
ufw allow in on tailscale0 to any port <PORT> proto tcp comment '<SERVICE> via mesh'
```

This scopes the rule to traffic arriving exclusively through the encrypted WireGuard tunnel, preventing LAN clients from accessing mesh-only services and vice versa.

---

## Logging

UFW logging is set to `low` (default). Blocked packets are logged to the kernel ring buffer and captured by `journald`:

```bash
# View recent firewall blocks
journalctl -k --grep="UFW BLOCK" --since="1 hour ago"
```

---

## Verification Commands

```bash
# Show all rules with numbers (for deletion by index)
ufw status numbered

# Show default policies
ufw status verbose

# Verify no unexpected listeners
ss -tulnp

# Verify from external host (should timeout on blocked ports)
nmap -Pn -p 22,80,443,3900,5432,8080 192.168.1.150
```

---

## Change Log

| Date | Change | Reference |
|---|---|---|
| 2026-09-01 | SSH rule added (LAN only) | `weeks/week-01/day-09.md` |
| 2026-09-05 | Museum, Garage, PostgreSQL rules pre-provisioned | `weeks/week-02/day-15.md` |
| 2026-09-06 | IPv6 hardening applied | `weeks/week-02/day-16.md` |

---

*This policy is the single source of truth for the sdrive appliance firewall. Any rule change must be documented here before deployment.*
