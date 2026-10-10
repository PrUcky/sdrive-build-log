# Client Configuration & Build Parameters

*Reference: weeks/week-07/day-45.md*

This document tracks the required configurations for compiling and connecting the custom Android client to the sdrive appliance.

## 1. Build-Time Constants
To hardcode the client to the sdrive Tailnet, the following changes were made in the teammate's fork of the Ente Android client (`app/src/main/java/io/ente/util/Constants.kt` equivalent):

```kotlin
// Original
// const val DEFAULT_ENDPOINT = "https://api.ente.io"

// sdrive Custom
const val DEFAULT_ENDPOINT = "https://sdrive.tail12345.ts.net"
const val HIDE_BILLING_UI = true
const val DISABLE_TELEMETRY = true
```

## 2. Tailscale VPN Integration (Android)
Because the appliance is not exposed to the public internet, the Android client relies on the Tailscale Android app being active.

**Split Tunneling Configuration:**
Running a full VPN on Android routes all traffic (YouTube, Chrome, etc.) through the Tailnet. To preserve battery and maintain privacy for non-sdrive traffic, configure Split Tunneling in the Tailscale Android app:
1. Open Tailscale on the phone.
2. Go to **Settings -> Use Tailscale subnets only** (Enable).
3. Alternatively, use **App Split Tunneling** and allow only the `sdrive` app to use the VPN.

**Always-On VPN:**
For background photo syncing to work reliably when the phone is locked, Tailscale must be configured as an "Always-on VPN" in Android System Settings -> Network & Internet -> VPN.

## 3. Battery Optimization
Android aggressively kills background processes. For the custom sdrive app to sync photos reliably in the background:
- Go to Android App Info -> **Battery**
- Change from "Optimized" to **Unrestricted**

If this is not set, Android will kill the upload worker after 10 minutes of screen-off time, causing large video uploads to fail despite Caddy's tuned timeouts.
