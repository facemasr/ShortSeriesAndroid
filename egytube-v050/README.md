# EGYTUBE 0.8.2 Preview — built from the 0.8.1 source
This preview preserves the v0.8.1 player, PiP, background audio, video downloads, share controls and UI without reverting to the 0.7 branch.

**Added:** AADS 2460254 (320×100 iframe) inline in the feed after item 14, while retaining the four existing advertising placements. Ad click behavior uses the existing external-browser WebView client.

**Updates:** The existing automatic and manual update checks remain in place; corrected the fallback URL to the 0.8.1 branch and reject update metadata for a mismatched Android application package.

**Why a preview APK?** The installed official app uses `com.egytube.official` and requires an identically signed APK to upgrade. A stable production signing key is not available in the current build workflow. To avoid breaking installs, the preview has an independent application ID `com.egytube.official.preview` and can be installed alongside the official app. This is *not* a direct update. The official `latest.json` continues to point to the last published official package until a correctly signed stable release is published.

**Requirements for official OTA updates:** User-authorized stable signing credentials and successful install test on device, followed by upload of signed official APK to the site and publishing matching `latest.json`. Do not commit keystore secrets to Git.
