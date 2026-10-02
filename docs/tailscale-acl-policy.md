# Tailscale ACL Policy Reference

*Reference: weeks/week-05/day-36.md*

This document describes the access control policy for the sdrive tailnet. Tailscale ACLs control which devices can reach which services.

---

## Current Policy (Week 05)

The default Tailscale ACL policy allows all devices on the tailnet to reach all other devices on all ports. This is acceptable for a personal/family tailnet with 3 devices.

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["*:*"]
    }
  ]
}
```

---

## Recommended Policy (Production)

For a production deployment, tighten the ACL to restrict access by role:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:phone"],
      "dst": ["tag:server:443"]
    },
    {
      "action": "accept",
      "src": ["tag:admin"],
      "dst": ["tag:server:*"]
    }
  ],
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:phone":  ["autogroup:admin"],
    "tag:admin":  ["autogroup:admin"]
  }
}
```

### Policy Explanation

| Rule | Source | Destination | Purpose |
|---|---|---|---|
| 1 | `tag:phone` | `tag:server:443` | Phones can reach Caddy HTTPS only |
| 2 | `tag:admin` | `tag:server:*` | Admin devices can reach all ports (SSH, Museum, Garage) |

### Device Tags

| Device | Tag | Access Level |
|---|---|---|
| ROCK 3C (sdrive) | `tag:server` | — (destination) |
| Phone (Pixel) | `tag:phone` | HTTPS only (port 443) |
| Desktop | `tag:admin` | Full access (all ports) |

---

## Security Benefits

1. **Least privilege:** Phones can only reach the HTTPS endpoint. They cannot SSH into the server, access Garage directly, or query PostgreSQL.

2. **Admin isolation:** Only the desktop can SSH into the server for maintenance. If a phone is compromised, the attacker can't pivot to the server's management interface.

3. **Port restriction:** Even on the tailnet, only necessary ports are open. Garage's S3 port (3900) and PostgreSQL's port (5432) are unreachable from phones.

---

## Key Management

| Setting | Current | Recommended |
|---|---|---|
| Key expiry | 180 days (default) | Disable for server, 90 days for phones |
| Auth keys | Interactive login | Pre-auth key for server (headless) |
| MFA | Disabled | Enable for admin console access |

### Disabling Key Expiry for the Server

The ROCK 3C runs headless. If its Tailscale key expires, it drops off the tailnet and becomes unreachable until someone physically logs in to re-authenticate. Disable key expiry for the server node:

```bash
# In Tailscale admin console:
# Machines → sdrive → ... → Disable key expiry
```

Keep key expiry enabled for phones and desktops — these devices can re-authenticate interactively.

---

## Future Considerations

- **Headscale migration:** If Tailscale's managed control plane becomes a concern, the open-source Headscale server can replace it. ACL policies would need to be migrated to Headscale's format.
- **Funnel (public access):** Tailscale Funnel can expose specific services to the public internet without port forwarding. Not currently needed (the demo is tailnet-only).
- **SSH via Tailscale:** Tailscale SSH can replace traditional SSH keys with Tailscale identity-based authentication. Potential future hardening.
