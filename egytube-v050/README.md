# EGYTUBE v0.7.0 — app updates connected with advertisements

**What is now linked:**
- The new AADS creative `data-aa=2460254` continues to be included in future releases. CI fails if its `AdSlots.java` implementation or home feed placement disappears.
- Every successful GitHub APK build now publishes `public-downloads/latest.json` beside the APK. Fields include the version code, version name, APK URL, SHA-256 digest, size, release note and the configured ad units.
- Android native `UpdateChecker` polls the project's hosted manifest no more than every 12 hours and alerts the user when a newer version is available, with an explicit user-approved download link.
- A new menu action **التحقق من تحديثات التطبيق** provides on-demand checks.
- Previous 0.6.9 and older versions do not contain this update checker. Install v0.7.0 to opt into it.
- Existing PiP, background audio, native ExoPlayer, three-tab navigation and five advertising units remain unchanged.

**Important limitation**
APK installation requires Android user approval and a *consistent signing certificate*. GitHub's default debug signing key may vary across workflow runs. A fresh version signed differently cannot be installed over an existing same-package app. Set up a secure, reusable signing keystore via GitHub Actions secrets for production releases. Do not commit a private signing key to this public repository. The updater does **not** silently install packages or bypass Android's signature checks.

**Verification**
GitHub Actions checks APK contents and signature; this is not a physical-device test of the update dialog, ad fill or successful device upgrades.
