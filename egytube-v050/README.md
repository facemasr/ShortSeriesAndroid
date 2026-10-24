# EGYTUBE 0.6.8 — Professional Android UI, background audio, PiP
- Bottom navigation: Home, Search, You. No Shorts or Subscriptions tabs. Shorts still accessible by search.
- Updated navigation and header, correcting search shortcut to the Search tab.
- Foreground MediaSessionService with notification and standard OS playback controls supports audio after Home, screen lock and ordinary removal from recent apps while service remains allowed to play.
- Picture-in-picture: auto-entry on Android 12+, onUserLeaveHint for Android 8–11, with correct PiP source geometry.
- Original Media3 ExoPlayer, custom professional watch controls, quality / speed menus, fullscreen, scrubbing, captions, playback resume, four advertising slots kept.
- Closing watch explicitly stops playback. Exiting Android Activity while playback is in progress leaves it to the media service.
- Some phone manufacturers restrict background apps; force-stop always stops playback. User should allow PiP in system settings if disabled.
- Debug-signed build; real-device tests still necessary. YouTube source extraction is unofficial and media may fail to load.
