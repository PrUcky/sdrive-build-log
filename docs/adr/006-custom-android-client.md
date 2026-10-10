# ADR-006: Custom Android Client Fork

**Status:** Accepted  
**Date:** 2026-10-10  
**Deciders:** Pratyush Chaudhary, UI/UX Teammate  

---

## Context

The sdrive backend is built on the open-source Ente architecture (Museum + Garage). Out of the box, a user can download the official Ente app from the Google Play Store, go to "Advanced Settings", and manually type in a custom server URL to connect to our self-hosted backend.

However, the goal of `sdrive` is to create a seamless, appliance-like experience for non-technical family members. 

Relying on the official upstream Ente app presents several UX friction points:
1. **Manual Configuration:** Users have to type `https://sdrive.tail12345.ts.net` exactly correct during onboarding.
2. **Irrelevant UI:** The official app includes screens for "Upgrade to Premium", "Billing", and "Subscription Quotas" which do not apply to a self-hosted appliance with a 500GB SSD.
3. **Telemetry:** The official app includes Sentry/Crashlytics SDKs for error reporting to Ente's servers.

## Decision

We will maintain a **hard-fork of the Ente Android client** rather than using the generic Play Store release. The teammate will own the fork, implement the branding, and compile custom `.apk` files for deployment.

## Rationale

1. **Frictionless Onboarding:** By changing `DEFAULT_ENDPOINT` in the Kotlin source code, the app defaults to connecting to the appliance. The user simply opens the app and logs in.
2. **Appliance Branding:** Replacing the Ente logo with the `sdrive` icon reinforces the appliance model. The user feels they are connecting to their physical drive at home, not a cloud service.
3. **Total Privacy:** By stripping the telemetry SDKs from `build.gradle`, we guarantee 100% data locality. No crash logs or usage metrics leave the Tailnet.
4. **Clean UI:** Hiding the billing logic prevents user confusion about storage quotas.

## Consequences

### Positive
- The UX matches the `ui-ux-brief.md` requirements perfectly.
- Onboarding is foolproof.
- Total control over privacy.

### Negative
- **Maintenance Burden:** We now own the client build pipeline. When upstream Ente releases a crucial bug fix or Android 17 compatibility update, we must manually rebase our fork and resolve merge conflicts.
- **Distribution:** We cannot use the Google Play Store. The app must be sideloaded (`.apk`), which requires walking family members through enabling "Install Unknown Apps" on Android.

## Alternatives Considered

**Option A: MDM / Managed Configuration**  
Using Android Enterprise managed configurations to push the server URL to the stock app. *Rejected:* Too complex for a home environment, and doesn't solve the billing UI problem.

**Option B: DNS Hijacking**  
Running Pi-Hole/AdGuard to intercept `api.ente.io` and route it to the ROCK 3C. *Rejected:* Breaks if the user disables Tailscale or connects to cellular data without DNS overrides. Certificate pinning in the app would also break this.

---

*This decision finalizes the client-side deployment strategy for Gate B.*
