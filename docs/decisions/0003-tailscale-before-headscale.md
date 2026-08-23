# 0003: Tailscale before Headscale

**Date:** 2026-08-23
**Status:** Accepted

## Context
A cloud replacement is useless if it only works when you are connected to your home Wi-Fi. We need the mobile app to sync seamlessly over cellular data and coffee shop networks. Exposing the server directly to the public internet via port forwarding is a massive security risk and often impossible due to Carrier-Grade NAT (CGNAT) from modern ISPs.

## Decision
We will use **Tailscale** for the initial prototype and development phases, with the explicit goal of migrating to **Headscale** in the future.

Tailscale is a zero-config WireGuard mesh network that easily punches through NAT. While it is open-source on the client side, the coordination server is a proprietary SaaS. Headscale is the open-source, self-hosted alternative to that coordination server.

## Consequences
- **Positive:** We guarantee immediate, frustration-free remote connectivity during the critical early weeks of development. Momentum is preserved.
- **Negative:** For the first half of the project, we rely on a third-party SaaS for our network control plane, which technically violates the "fully self-hosted" ethos of the appliance. 
- **Mitigation:** The architecture will be designed to treat Tailscale as a swappable component. Once the hardware and core software loops are stable, we will execute a cutover to Headscale.