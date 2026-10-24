# EGYTUBE v0.6.6 — Reference-inspired professional player
Native Android Media3/ExoPlayer; app is YouTube-only without EGYSHOW.
- Rounded red central play/pause, video-focused layout and near-black bottom transport strip
- Thin red progress line with scrubbing, buffer tracking and time readout
- Play/pause, first recommended next video, Android music volume control and slider, captions (only where present), settings, PiP and fullscreen in one black footer
- Small back/title bar; in-video compact settings with quality, speed, fit/zoom and captions
- Mobile toolbar supports horizontal swipe on narrow screens rather than clipped icons
- Existing double-tap ±10-second seek, video orientation fit, adaptive HLS/DASH quality when source supports it, in-page watch, PiP and local resume remain
- Existing external ad placements remain separate from controls; ad clicks open default browser
- Debug APK signed via CI. No physical Android device test. Unofficial source extractor can fail for YouTube videos.
