# EGYTUBE 0.6.3 — Native inline watch page
- YouTube-only mobile app, no EGYSHOW content or references.
- Tapping a video opens an in-page native watch panel in MainActivity; closing returns to the same feed and scroll position.
- Video stays pinned at top while details and related recommendations scroll underneath.
- ExoPlayer/Media3 remains the actual native player, not an official YouTube iframe.
- Quality button appears inside player overlay; real available HLS/DASH adaptive quality and manual formats; switching attempts to retain playback position.
- In-player fit/zoom and fullscreen controls. Height adapts to actual video dimensions, portrait/landscape, without forcing orientation.
- 320×50 data527 banner under player; other user-supplied ads remain in feed, open in external browser on click.
- Upload is debug signed and has not been tested on a physical device. Unofficial NewPipeExtractor may fail for individual YouTube videos or regional restrictions.
