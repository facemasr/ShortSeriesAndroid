# EGYTUBE 0.6.7 — MediaSession background playback + PiP fixes
- Bottom navigation simplified to **Home / Search / You**, removing Shorts and Subscriptions from the bottom tabs.
- A foreground MediaSessionService owns the ExoPlayer. Media-style Android system notification provides audio playback controls in background / lock screen; resumes while switching to other apps. Android may still stop the service if force-stopped or when battery policies intervene.
- Home and search retain standard video cards; no EGYSHOW integration. Shorts no longer a menu tab; Shorts can still be discovered via search.
- PiP: source rect, automatic Android 12+ while playing, explicit onUserLeaveHint for Android 8-11, UI controls hidden in floating video mode.
- Native professional player and all four user ad placements retained.
- This is a debug-signed build that is not tested on a physical phone; media extraction and ad providers may not work for every item.
