# UI/UX Client Review: sdrive Android App

*Date: October 10, 2026*
*Reviewer: Pratyush Chaudhary (Infrastructure)*
*Reference: weeks/week-07/day-45.md*

The teammate responsible for the client-side UI/UX has delivered the first Release Candidate (RC1) of the custom Android APK. This document reviews the build against the requirements outlined in the initial `ui-ux-brief.md`.

## 1. Branding and Theming
- **App Icon:** ✅ Replaced. The generic Ente logo is gone, replaced by the custom `sdrive` storage drive icon.
- **Splash Screen:** ✅ Replaced. Dark mode splash screen displays "sdrive: Your Private Vault".
- **Color Palette:** ✅ Adjusted. The accent colors have been shifted from Ente's default blue to the custom slate/amber palette defined in the brief.

## 2. Onboarding & Endpoint Configuration
- **Hardcoded Server URL:** ✅ Implemented. The "Advanced Setup -> Custom Server" screen has been bypassed. The app is hardcoded to point to `https://sdrive.tail12345.ts.net`. Users no longer need to know or type the Tailnet URL.
- **Registration Flow:** ⚠️ Partial. The registration flow works flawlessly, but the "Terms of Service" link still points to Ente's official website. This needs to be removed or repointed to a local empty file for the appliance build.

## 3. Subscription & Billing De-cluttering
Because this is a self-hosted appliance, the user owns the hardware and the 500GB SSD. Subscription screens are confusing and irrelevant.
- **Upgrade Prompts:** ✅ Removed. The "Upgrade to Premium" banners have been successfully stripped from the gallery view.
- **Settings Menu:** ✅ Cleaned. The "Billing" and "Subscription" tabs have been completely removed from the Settings menu.
- **Storage Quota Display:** ✅ Fixed. Instead of showing "5 GB / 5 GB (Full)", the app now polls the appliance for actual physical disk space and displays the true capacity (e.g., "6.2 GB / 458 GB").

## 4. Telemetry and Analytics
- **Sentry/Crashlytics:** ✅ Removed. All external crash reporting and telemetry SDKs have been stripped from the `build.gradle` file to maintain 100% data locality and privacy.

## Verdict
**STATUS: APPROVED FOR GATE B**

The RC1 build successfully transforms the generic Ente client into a purpose-built companion app for the sdrive appliance. It feels like a cohesive, single-purpose product rather than a self-hosted workaround. The remaining ToS link is a minor issue that won't block the October 25th gate.
