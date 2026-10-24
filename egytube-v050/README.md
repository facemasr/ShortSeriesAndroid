# EGYTUBE v0.6.2 — YouTube-only Android app
- Built from Android/Kotlin native code with Media3 ExoPlayer as the app's own player, not a full YouTube WebView player
- Home video feed, Shorts, search, local channel follows, favorites and history
- Four user-supplied ad units, marked "إعلان":
  1. 300 x 250 in feed (data527.click)
  2. responsive 468 x 60 in feed (data527.click)
  3. 320 x 50 beneath native player (data527.click)
  4. Bonepa unit in feed and library
- On deliberate ad click, navigate using Android ACTION_VIEW to the default browser. Handle iframe links and popup targets; ignore unsolicited popup requests and non-http(s) schemes. No auto-open in background, no JS-native bridge, no overlay over player controls.
- The ads are third-party scripts; content, fill and destination websites are controlled by providers, not by this app. Screen ad content/age appropriateness and check their terms before public release.
- Content search/extraction uses unofficial NewPipeExtractor and may stop working as YouTube changes. Videos may not work in all circumstances.
- Build verification checks APK ZIP integrity, signing and MainActivity presence; on-device tests are still required.
- Independent install ID com.egytube.rebuilt. Debug, not production-signed.
