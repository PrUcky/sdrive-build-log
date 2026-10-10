# Day 45: The Joy of the Custom Client

*October 11, 2026*

For seven weeks, this project has been terminals, bash scripts, Docker containers, and UFW rules. The only way to interact with it was through standard API calls or a generic cloud app that I had to manually trick into talking to my server.

Today, that changed. The teammate building the UI/UX delivered the RC1 `.apk` file for the custom Android client.

## Sideloading the Experience

I uninstalled the upstream Ente app from my Pixel. I pulled the RC1 APK over ADB and installed it. 

When I opened the app launcher, I didn't see the Ente cloud icon. I saw the custom `sdrive` vault icon we designed in the `ui-ux-brief.md`. I tapped it.

The splash screen didn't load a corporate logo. It loaded the dark-mode "sdrive: Your Private Vault" screen. 

There was no "Advanced Configuration" button. There was no "Custom Server" field. The app just presented a clean login screen. I typed in my credentials. The SRP authentication protocol fired, and I was logged in. 

It felt like a cohesive, physical appliance for the first time. I wasn't just self-hosting a cloud service anymore. I had built a *product*.

## Verifying the Traffic

To make sure the app was actually hardcoded correctly and not secretly calling out to the cloud, I SSH'd into the board and ran the new `sdrive-tail-client.sh` script I wrote today to tail the Caddy logs.

I took a photo on my phone. Almost instantly, the terminal on my monitor lit up:

```text
[2026-10-11T14:32:10Z] POST /api/v1/objects - 200 (0.43s)
[2026-10-11T14:32:10Z] PUT /api/v1/metadata - 200 (0.12s)
```

The app was speaking directly to the Tailnet IP. 

I opened the Settings menu in the app. The "Billing" and "Upgrade to Premium" tabs were completely gone. I went to the Storage tab. Instead of a hardcoded 5GB quota, it accurately reported the capacity of the external SSD sitting on my desk: `6.4 GB / 458 GB`. 

## The Documentation Phase

I spent the rest of the day documenting the client architecture. 

I wrote a formal UI/UX review (`docs/ui-ux-review.md`) approving the RC1 build for Gate B. I documented the necessary Android Tailscale configurations (Split Tunneling, Always-On VPN) and the critical Android Battery Unrestricted setting required to keep background uploads alive (`docs/client-configuration.md`). 

Finally, I wrote ADR-006 to formally justify *why* we forked the Android client. The maintenance burden of managing our own APKs is high, but the resulting user experience—a frictionless, private, subscription-free UI—is the entire point of the sdrive project.

Tomorrow, we stress-test this custom client. We're going to see how it handles backgrounding a massive video upload while the phone is locked.
