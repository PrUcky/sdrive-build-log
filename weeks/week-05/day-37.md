# Day 37: Week 05 Retrospective — The Appliance Is Reachable From Everywhere

*October 2, 2026*

Week 05 is done. Gate A is passed. The sdrive appliance is reachable from any network in the world through a WireGuard tunnel that requires zero port forwarding, zero public IPs, and zero exposed attack surface.

I'm sitting at my desk looking at the Tailscale health check output showing two peers connected — the desktop on WiFi and the phone on mobile data. Both can reach Museum. Both can upload and download photos. The tunnel throughput ranges from 382 Mbps on the local network to 7.8 Mbps through a DERP relay — and even the worst case is fast enough for continuous background backup.

The biggest learning this week wasn't technical. It was the realization that NAT traversal is a solved problem. I spent two days in Week 02 understanding CGNAT and concluding that traditional port forwarding was impossible. Tailscale solved it in a single `tailscale up` command. The STUN/ICE hole-punching negotiation that happens behind the scenes is genuinely sophisticated — it probes NAT types, discovers peer endpoints, and establishes direct UDP tunnels through multiple layers of CGNAT. But from the user's perspective, it's invisible. That's the whole point.

The Caddy HTTPS architecture is mapped out for Week 06. The MagicDNS hostname is live. The Let's Encrypt certificate is provisioned. The draft Caddyfile is written. Week 06 can focus on execution rather than design.

Gate B is October 25 — 23 days away. It requires "complete one-app upload/retrieval proof." The pieces are coming together: the stack runs (Week 03), photos upload and download (Week 04), and the network reaches everywhere (Week 05). What remains is HTTPS (Week 06), the UI/UX rebranding from the teammate, and the final demo preparation.

Today I wrote the formal retrospective and the weekly article. Five weeks down, seven to go.
