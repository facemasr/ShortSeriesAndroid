# EGYTUBE 0.6.1 — YouTube Only
Native Android application with a YouTube-style layout but independent EGYTUBE branding.
- Native feed for regular YouTube videos, search, Shorts, following, local library/history
- NewPipeExtractor reads YouTube search results with no user API key and can stop working if YouTube changes its site or blocks requests
- Fully removes any EGYSHOW URLs and content sections
- Uses original-style Media3 / ExoPlayer player for compatible sources, not official embedded YouTube iframe; media availability not guaranteed
- Automatic adaptive HLS/DASH quality when available; other formats manual
- User-supplied Bonepa ad in player and one feed slot labeled Advertisement, no ad covering playback
- Does not offer Google account sign-in, posting, uploads, YouTube Premium, or authentic YouTube subscriptions
- Separate APK identifier `com.egytube.rebuilt`, debug signed, builds independently from 0.4.4
- Requires real phone testing and review of YouTube terms / ad network policies before distribution
\nAd placements: #1 300x250 in the video feed, #2 468x60 responsive banner in the feed, #3 320x50 below the ExoPlayer, #4 separate Bonepa placement in long feed and library. All ad-initiated browser links launch an ACTION_VIEW intent, no overlay on playback; JS bridges and auto popups disabled. This does not guarantee third-party ad fill or content suitability; audit advertisers before public release.\n