# EGYTUBE v0.6.9 — AADS 2460254 added

YouTube-only native Android app. Keeps EGYTUBE v0.6.8 player, PiP, background audio service, and three-tab navigation.

- New fifth advertisement **AADS ad unit 2460254**, iframe `https://ad.a-ads.com/2460254/?size=320x100` with `data-aa='2460254'`.
- Labeled "إعلان", inserted after the seventh video in home/search results. The ad is inline, max 320x100, centered and never overlays player controls.
- Existing advertisements are untouched: 300x250, 468x60, 320x50 under player, and Bonepa.
- Ad WebView attempts to open user-clicked HTTP(S) links in the phone's external default browser; unsolicited popups are blocked.
- AADS may decline inventory on embedded WebViews or show a blank creative; live ad rendering is not guaranteed.
- Build and signing checks run in GitHub Actions. Not validated on a physical Android phone.
