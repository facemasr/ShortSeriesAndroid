# ShortSeris Native App

Native Flutter application for **https://shortseris.online**.

This repository no longer uses Android WebView. The app reads JSON from the ShortSeris mobile API and renders native Flutter screens.

## API
Base endpoint:

`https://shortseris.online/mobile-api/index.php`

Main actions used by the app:
- `home`
- `media`
- `media_detail`
- `channels`
- `playback`
- `login` / `logout` / `me`
- `favorites`
- `watchlist`
- `continue`
- `progress`

## Features
- Arabic / English
- RTL / LTR
- Movies
- Series
- Short series
- Seasons and episodes
- Live TV
- Search
- Native playback with media_kit
- Multiple playback servers
- Secure Bearer-token login
- Favorites
- My List
- Continue Watching
- Playback progress sync

## GitHub build
Every push to `main` starts **Build Android APK** in GitHub Actions.

After the workflow succeeds:
1. Open **Actions**
2. Open the latest **Build Android APK**
3. Download the **ShortSeris-Android** artifact
4. Extract `app-release.apk`

The workflow generates the Android runner automatically, so this repository can stay focused on the Flutter source.

## Local development
```bash
flutter create . --platforms=android,ios --org online.shortseris --project-name shortseris_app
flutter pub get
flutter run
```

For Android release builds ensure the INTERNET permission exists in the main Android manifest.


## Remote control from the website

The app reads `action=app_config` from the ShortSeris mobile API at launch.

After installing ShortSeris **v5.8.0 App Control Center**, the website admin can remotely control:
- App on/off and maintenance mode
- Arabic/English app name, logo, splash and colors
- Movies, Series, Short Series, Live TV, Search, Account and Continue Watching visibility
- Android/iOS minimum and latest versions
- Forced app updates and update URLs
- Native app ads for Home, Details, Player and TV

Admin path: `/admin/app-control`
