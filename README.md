# EGYSHOW Android

Native Flutter companion app for the current EGYSHOW website: **https://egyshow.com**.

The app uses the first-party EGYSHOW JSON APIs for the catalogue, search, details, account and playback. It keeps the Arabic/English interface and RTL/LTR layout.

## Included sections

- Home and featured titles
- Movies
- Series
- Short series, seasons and episodes
- Search
- Match listings
- EGYSHOW YouTube discovery
- Account, sign-in and favourites

**Live TV / EGY TV Sport channel browsing and playback have been removed from this app.** The separate EGY TV PRO product is not part of this project and is not modified.

## Website API

Base origin: `https://egyshow.com`

Main API routes used by the app include:

- `/api/v1/home`
- `/api/v1/media`
- `/api/v1/media/{id}`
- `/api/v1/search`
- `/api/v1/player/context`
- `/api/v1/auth/login` and `/api/v1/auth/register`
- `/api/v1/profile`
- `/matches/api`
- `/api/v1/youtube/discover` and `/api/v1/youtube/search`

## Android build

The project is Flutter. Install Flutter stable and Android SDK, then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The release APK must be signed with the existing EGYSHOW production signing key before publishing as an update. Never replace the installed production app with an unsigned or differently signed APK.

## Version

Current development candidate: **2.0.34+42**.
