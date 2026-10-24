# EGYTUBE 0.6.4 — Professional native watch player
Native YouTube-only Android app using Media3/ExoPlayer. Preserves the 0.6.3 same-page video watch and YouTube search/feed/Shorts, favorites, local history, recommendations and user-supplied ads.

## New
- Native Android picture-in-picture with a PiP button within the player on Android 8.0+ (when supported); Android 12+ supports auto-enter from active playback when leaving the app
- In-player quality selector with adaptive HLS/DASH (when sources support it) and manual MP4 sources
- Playback speed (0.5–2×), ten-second seeking backward/forward, and automatic overlay control hiding
- Fit/zoom, full screen, video aspect ratio adapts to portrait/landscape, and display remains awake while watching
- Resume playback positions stored locally (except videos at completion)
- PiP displays only the playing video; player survives while the activity is in PiP and returns to the same watch panel

## Caveats
- Unofficial NewPipe extractor means video playback/search may stop working if YouTube changes interfaces; not all video sources offer adaptive quality.
- Third-party ads are shown outside playback view and should be screened for suitability and legal terms before publishing.
- Debug-signed APK, build and signing validated via GitHub Actions; not tested on physical Android device.
