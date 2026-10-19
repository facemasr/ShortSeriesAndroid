# EGYSHOW Android Installable Preview

A small Flutter/WebView installable Android **preview**, connected to https://egyshow.com.

- The app supports Arabic/English navigation, catalog tabs, search/account links,
  system back navigation, and renders the existing site's player within Android WebView.
- It does NOT yet use the advanced native catalog implementation or native HLS player.
  Video and account behavior depend on the existing EGYSHOW website.
- This preview is not a Google Play release, and playback compatibility is not guaranteed.
- Build with GitHub Actions `Build EGYSHOW Android APK` from branch `egyshow-android-install`.
- Download the `EGYSHOW-Android-APK` artifact ZIP, extract `app-release.apk`,
  and install on an Android device.
- This branch does not replace the existing ShortSeris app in `main`.
