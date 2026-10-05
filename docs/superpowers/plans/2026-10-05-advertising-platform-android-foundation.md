# SHORT SERIES TV Advertising Platform - Android Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-safe Android layer of the SHORT SERIES TV advertising platform: age policy, remote ad decisions, event tracking, server-controlled placements, AdMob integration, admin summary, and a playback pre-roll hook that always fails open.

**Architecture:** Keep `AdMobService` as the low-level Google Mobile Ads adapter, add an independent ad-policy client that consumes server decisions, and add small placement/player coordinators above both. The server remains authoritative when the new decision feature flag is enabled; while the website backend is not yet available in this repository, the Android app must remain compatible with the existing `app_config.admob` behavior and must never block startup or playback if ad services fail.

**Tech Stack:** Flutter/Dart, Dio, `flutter_secure_storage`, `google_mobile_ads ^9.1.0`, `media_kit`, `cached_network_image`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-05-advertising-platform-design.md`

## Global Constraints

- Advertising failure must never prevent the application or a media item from opening.
- The user enters a full date of birth only for Age Gate calculation; the raw date is discarded and only `child`, `teen`, or `adult` is persisted.
- Age categories are `child < 13`, `teen 13-17`, and `adult 18+`; unknown age fails toward conservative policy.
- Membership policy is `Free = normal`, `Premium = reduced`, `VIP = no ads`.
- Child/unknown profiles must never receive campaigns that are not explicitly eligible for them.
- Remote kill switches and server decisions override client-side campaign behavior when the new ad platform is enabled.
- Existing production AdMob IDs and existing `app_config.admob` behavior must remain a safe fallback until the backend decision endpoints are deployed.
- Ad SDK initialization must remain unable to block the first Flutter frame.
- Tracking failures and decision timeouts are non-fatal and may not delay playback indefinitely.
- This repository does not contain the full `shortseris.online` backend; backend/admin implementation requires the website source in a separate plan.

## Review Focus

- **Unknown/corrupt age profile:** treat as conservative/unknown and show Age Gate rather than assuming adult; pinned in Task 2 tests.
- **Decision API timeout, 5xx, malformed JSON:** return fail-open/no-ad or the explicitly configured legacy fallback without crashing; pinned in Task 3 tests.
- **VIP profile:** every new placement and player decision must short-circuit to no-ad before network work; pinned in Tasks 3 and 5 tests.
- **Rapid episode transitions/back navigation:** do not double-show or leave an interstitial active underneath content; pinned in Task 6 tests.
- **Offline playback:** do not wait on remote ad decisions before local content starts; pinned in Task 6 tests.

---

### Task 1: Add advertising domain models and parsing

**Files:**
- Create: `lib/ad_platform_models.dart`
- Modify: `lib/main.dart` (part declarations only)
- Create: `test/ad_platform_models_test.dart`

**Interfaces:**
- Produces: `enum AdAgeGroup { child, teen, adult, unknown }`
- Produces: `enum AdMembershipTier { free, premium, vip }`
- Produces: `enum AdSourceType { none, admobBanner, admobNative, admobInterstitial, admobRewarded, appOpen, privateImage, privateVideo, vast, vmap }`
- Produces: `class AdRequestContext` with placement, platform, appVersion, membershipTier, ageGroup, locale, contentType, contentId, genreIds, sessionId.
- Produces: `class AdCreative` with source type, media URL, click URL, VAST/VMAP URL, CTA, skip seconds, and arbitrary metadata.
- Produces: `class AdDecision` with `showAd`, `decisionId`, `placement`, `creative`, `trackingToken`, and `static AdDecision fromJson(Map<String,dynamic>)`.
- Produces: `class AdEvent` with event type, decision ID, token, timestamp, and metadata.

- [ ] **Step 1: Write failing model tests**

Create tests for: valid VAST decision parsing, no-ad response parsing, unknown source type degrading to `AdSourceType.none`, missing optional creative fields, and malformed data not throwing from tolerant parsing helpers.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/ad_platform_models_test.dart`
Expected: FAIL because the model types do not exist.

- [ ] **Step 3: Implement the models**

Add the exact public types above in `lib/ad_platform_models.dart` as `part of 'main.dart';`. Keep placement as a string rather than an enum so new server placements do not require a new APK.

- [ ] **Step 4: Run tests and verify pass**

Run: `flutter test test/ad_platform_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/ad_platform_models.dart test/ad_platform_models_test.dart
git commit -m "feat: add advertising domain models"
```

### Task 2: Add Age Gate and persistent coarse age profile

**Files:**
- Create: `lib/ad_age_gate.dart`
- Modify: `lib/main.dart` (`Bootstrap` flow and startup initialization)
- Create: `test/ad_age_gate_test.dart`

**Interfaces:**
- Consumes: `AdAgeGroup` from Task 1.
- Produces: `class AgePolicy { static AdAgeGroup classify(DateTime birthDate, {DateTime? now}); }`
- Produces: `class AdProfileStore` with `Future<AdAgeGroup> readAgeGroup()`, `Future<void> writeAgeGroup(AdAgeGroup value)`, `Future<AdMembershipTier> readMembershipTier()`, and `Future<void> clearAgeGroup()`.
- Produces: `class AgeGatePage extends StatefulWidget` that returns a computed `AdAgeGroup` to the bootstrap flow and never persists the raw birth date.

- [ ] **Step 1: Write failing age-policy tests**

Test birthdays one day before/after the 13th and 18th birthdays, leap-year dates, a future date rejection, and unknown/corrupt stored profile fallback.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/ad_age_gate_test.dart`
Expected: FAIL because `AgePolicy` and `AdProfileStore` do not exist.

- [ ] **Step 3: Implement classification and storage**

Persist only keys `ad_age_group` and `ad_age_verified_at`; never write the DOB to `FlutterSecureStorage`.

- [ ] **Step 4: Gate app bootstrap before ad SDK policy initialization**

Update `Bootstrap` so first launch shows `AgeGatePage` before ad policy is initialized. Keep MediaKit and cache cleanup non-blocking. Remove the unconditional `AdMobService.I.initialize()` call from `_initializeAfterFirstFrame`; initialization will be triggered after age/config policy is known in Task 4.

- [ ] **Step 5: Run tests**

Run: `flutter test test/ad_age_gate_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/ad_age_gate.dart test/ad_age_gate_test.dart
git commit -m "feat: add privacy-safe age gate"
```

### Task 3: Add fail-open Ad Decision client and tracking queue

**Files:**
- Create: `lib/ad_platform_api.dart`
- Modify: `lib/main.dart` (part declaration)
- Create: `test/ad_platform_api_test.dart`

**Interfaces:**
- Consumes: `AdRequestContext`, `AdDecision`, `AdEvent`, `AdProfileStore`.
- Produces: `typedef AdApiTransport = Future<Map<String,dynamic>> Function(String action, Map<String,dynamic> data);`
- Produces: `class AdDecisionClient` with `Future<AdDecision> decide(AdRequestContext context, {Duration timeout = const Duration(milliseconds: 2500)})`.
- Produces: `class AdTrackingQueue` with `void enqueue(AdEvent event)`, `Future<void> flush()`, and `int get pendingCount`.
- Production transport uses `Api.I.call('ads_decision', method:'POST', data:...)` and `Api.I.call('ads_events', method:'POST', data:{'events': ...})` until the backend exposes dedicated REST routes.

- [ ] **Step 1: Write failing API tests**

Use injected fake transports to test: VIP short-circuits without invoking transport, success parses a decision, timeout returns no-ad, thrown network error returns no-ad, malformed payload returns no-ad, tracking failure retains/bounds queue without throwing, and queue batching preserves order.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/ad_platform_api_test.dart`
Expected: FAIL because the clients do not exist.

- [ ] **Step 3: Implement the clients**

Do not add retries inside `decide`; one bounded request only. Cap the in-memory tracking queue at 100 events and drop oldest non-critical events first if the cap is exceeded.

- [ ] **Step 4: Run tests**

Run: `flutter test test/ad_platform_api_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/ad_platform_api.dart test/ad_platform_api_test.dart
git commit -m "feat: add remote ad decision and tracking clients"
```

### Task 4: Make AdMob policy-aware without regressing startup

**Files:**
- Modify: `lib/admob_ads.dart`
- Modify: `lib/main.dart` (`Bootstrap` initialization handoff)
- Create: `test/admob_policy_test.dart`

**Interfaces:**
- Consumes: `AdAgeGroup`, `AdMembershipTier`, `AdProfileStore`.
- Produces: `Future<void> AdMobService.initializeFor({required AdAgeGroup ageGroup, required AdMembershipTier membershipTier})`.
- Produces: read-only resolved IDs for banner, native home/details, interstitial, rewarded, and app-open using remote config -> dart define -> production/test fallback order.
- Produces: `bool AdMobService.get policyAllowsAds` and conservative request configuration for child/unknown profiles.

- [ ] **Step 1: Write failing policy tests**

Extract pure configuration resolution/policy helpers so tests prove: VIP is disabled, global remote disable wins, test mode selects Google test IDs, production fallbacks remain unchanged, and child/unknown policy is marked conservative.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/admob_policy_test.dart`
Expected: FAIL for missing policy helpers.

- [ ] **Step 3: Implement policy-aware initialization**

Call Google Mobile Ads request configuration before `MobileAds.instance.initialize()`. Preserve deferred initialization and catch SDK failures so the app remains usable.

- [ ] **Step 4: Add rewarded/app-open config keys without showing them yet**

Support remote keys `rewarded_id_android`, `app_open_id_android`, and matching `--dart-define` names. Rendering these formats belongs to the later player/app-open plan.

- [ ] **Step 5: Run tests**

Run: `flutter test test/admob_policy_test.dart test/ad_platform_api_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/admob_ads.dart test/admob_policy_test.dart
git commit -m "feat: make AdMob age and membership aware"
```

### Task 5: Add server-controlled ad placement widgets

**Files:**
- Create: `lib/ad_placements.dart`
- Modify: `lib/main.dart` (part declaration)
- Modify: `lib/pro_home.dart` (replace direct Home AdMob calls)
- Modify: `lib/pro_detail.dart` (replace direct Details AdMob call)
- Create: `test/ad_placements_test.dart`

**Interfaces:**
- Consumes: `AdDecisionClient`, `AdMobBanner`, `AdMobNativeCard`, `AdCreative`.
- Produces: `class RemoteAdPlacement extends StatefulWidget` with `placement`, optional content context, and `legacyFallback`.
- Phase-1 supported decision sources: `admobBanner`, `admobNative`, `privateImage`, and `none`.
- Unsupported future sources (`vast`, `vmap`, `privateVideo`, rewarded/app-open) must render nothing and report an error event rather than block the page.

- [ ] **Step 1: Write failing widget tests**

Test no-ad renders zero height, VIP never requests remote ads, private image uses the returned creative URL/CTA, malformed creative renders nothing, and decision timeout does not leave a progress spinner.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/ad_placements_test.dart`
Expected: FAIL because `RemoteAdPlacement` does not exist.

- [ ] **Step 3: Implement placement rendering**

Use `CachedNetworkImage` for private image creatives and `url_launcher` for click-through. Send `impression` only after the creative is actually visible/loaded and `click` only after a user tap.

- [ ] **Step 4: Replace current Home/Details AdMob widgets**

`home_top` should keep the existing site-controlled `AppAd('app_home_top')` and replace direct AdMob banner/native calls with remote placements that can fall back to the current AdMob widgets while the new server feature flag is off. `details` should do the same around `AppAd('app_details')`.

- [ ] **Step 5: Run tests**

Run: `flutter test test/ad_placements_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/ad_placements.dart lib/pro_home.dart lib/pro_detail.dart test/ad_placements_test.dart
git commit -m "feat: add server-controlled ad placements"
```

### Task 6: Add playback ad coordinator and replace direct interstitial call

**Files:**
- Create: `lib/player_ad_coordinator.dart`
- Modify: `lib/main.dart` (part declaration)
- Modify: `lib/pro_player.dart` (`_loadTarget` pre-playback flow)
- Create: `test/player_ad_coordinator_test.dart`

**Interfaces:**
- Consumes: `AdDecisionClient`, `AdMobService`, `AdRequestContext`, `AdProfileStore`.
- Produces: `class PlayerAdCoordinator` with `Future<void> beforePlayback({required String ownerType, required int ownerId, required bool betweenEpisodes, required bool offline})`.
- Phase-1 decision support: `admobInterstitial` and `none`; future `vast`, `vmap`, and `privateVideo` decisions are tracked as unsupported/fail-open and content continues.

- [ ] **Step 1: Write failing coordinator tests**

Test VIP skips all requests, offline returns immediately, timeout returns immediately, repeated episode transition is delegated to existing AdMob frequency controls only once, unsupported source returns without throwing, and ad-show failure resumes caller flow.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/player_ad_coordinator_test.dart`
Expected: FAIL because coordinator does not exist.

- [ ] **Step 3: Implement the coordinator**

Keep one in-flight `beforePlayback` decision at a time. Never own the content `Player`; it only coordinates the pre-playback gate.

- [ ] **Step 4: Wire `_loadTarget`**

Replace the direct `AdMobService.I.maybeShowPlaybackInterstitial(...)` call with `PlayerAdCoordinator.I.beforePlayback(...)`. Offline playback must bypass remote decision calls entirely.

- [ ] **Step 5: Run tests**

Run: `flutter test test/player_ad_coordinator_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/player_ad_coordinator.dart lib/pro_player.dart test/player_ad_coordinator_test.dart
git commit -m "feat: add fail-open playback ad coordinator"
```

### Task 7: Add lightweight Ads Studio summary inside Android admin

**Files:**
- Create: `lib/admin_ads_summary.dart`
- Modify: `lib/main.dart` (part declaration)
- Modify: `lib/admin_studio_core.dart`
- Create: `test/admin_ads_summary_test.dart`

**Interfaces:**
- Produces: `class AdminAdsSummaryPage extends StatefulWidget`.
- Reads `admin_ads_summary` when available; on 404/unsupported action, derives local status from `Api.I.config['admob']` and displays that the server Ads Studio API is not deployed yet.
- Opens the canonical website panel through `AdminWebPanelPage(initialPath:'/admin/ads', ...)`.

- [ ] **Step 1: Write failing widget tests**

Test summary cards render from server data, fallback status renders without crashing, and the full-management action targets `/admin/ads`.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/admin_ads_summary_test.dart`
Expected: FAIL because the page does not exist.

- [ ] **Step 3: Implement summary page and Admin Studio action**

Add one `إدارة الإعلانات / Ads Studio` action to `AdminStudioPage` without duplicating the full website campaign editor in Flutter.

- [ ] **Step 4: Run tests**

Run: `flutter test test/admin_ads_summary_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/admin_ads_summary.dart lib/admin_studio_core.dart test/admin_ads_summary_test.dart
git commit -m "feat: add Android Ads Studio summary"
```

### Task 8: Release verification and build compatibility

**Files:**
- Modify: `pubspec.yaml` (increment app build/version after implementation)
- Modify only if required by new dart defines: `.github/workflows/android.yml`
- Verify: all `test/*.dart`

**Interfaces:**
- No new runtime interfaces.
- If rewarded/app-open dart defines were added in Task 4, workflow passes `ADMOB_REWARDED_ID` and `ADMOB_APP_OPEN_ID` with empty-safe defaults.

- [ ] **Step 1: Run formatter and analyzer**

Run: `dart format lib test`
Run: `flutter analyze`
Expected: no analyzer errors.

- [ ] **Step 2: Run complete test suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 3: Verify release build**

Run: `flutter build apk --release`
Expected: `build/app/outputs/flutter-apk/app-release.apk` produced successfully.

- [ ] **Step 4: Verify startup safety manually/emulator**

Verify app reaches first frame with network disabled; Age Gate appears on first install; a decision endpoint timeout does not block navigation/playback; existing AdMob behavior still works when the new server decision feature flag is absent.

- [ ] **Step 5: Bump version and commit**

Increment from the current `1.13.3+18` only after all checks pass, then commit:

```bash
git add pubspec.yaml .github/workflows/android.yml
git commit -m "chore: release Android ad platform foundation"
```

## Follow-on Plans

This plan intentionally stops at a stable Android foundation. Two separate plans follow after it because they are independently testable subsystems:

1. **Player video advertising plan:** private video ads, pre/mid/post-roll cue engine, pause/overlay ads, `interactive_media_ads`/Google IMA VAST/VMAP integration, rewarded flows, and player-state restoration.
2. **Backend/admin plan:** `ad_campaigns`, creatives, placements, targeting, frequency rules, tracking/daily stats, `/admin/ads`, decision/event APIs, remote kill switches, and campaign analytics. This plan cannot be written with exact source paths until the `shortseris.online` backend repository/files are available.

The official Flutter `interactive_media_ads` plugin is the intended IMA candidate for the follow-on player plan; its Android integration requires network permission and core-library desugaring, which will be handled in that later plan rather than mixed into this foundation release.
