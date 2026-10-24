# EGYTUBE Native 0.5.0 (fresh build)
Build from source to avoid class-not-found errors from re-signing patched DEX files.
- No YouTube Data API key required. Home displays videos from the EGYSHOW YouTube entertainment listing (not a global YouTube API).
- Arabic native Android home is one video feed with no subdivided sections.
- Bottom navigation: Home, Search, Movies, Series, Short Series, News.
- Search filters content from current EGYSHOW listings; not a global YouTube search.
- YouTube playback uses the official iframe embedded in a dedicated native Activity with auto quality controlled by YouTube; no custom quality override.
- Bonepa ad slot placed below, outside the YouTube iframe.
- EGYSHOW title details open in the device browser for now (native watch for all EGYSHOW titles not implemented).
- Debug APK signed with different key / package com.egytube.rebuilt: installs separately from 0.4.4.
- This does not bypass YouTube ads, DRM, age controls or platform restrictions.
- No physical-device test completed; API and external site availability can change.
