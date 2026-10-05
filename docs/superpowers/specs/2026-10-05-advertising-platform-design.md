# SHORT SERIES TV Advertising Platform Design

Date: 2026-10-05

## Purpose

Build a centrally managed advertising platform for SHORT SERIES TV that supports AdMob, private image/video campaigns, VAST/VMAP video advertising, campaign targeting, age-aware policies, membership tiers, analytics, frequency capping, and emergency remote controls without requiring a new APK for ordinary campaign changes.

The design must preserve playback reliability: an advertising failure must never prevent the application or a media item from opening.

## Existing Application Context

The Android Flutter application already has an `AdMobService` with production/test unit support, remote configuration through `app_config.admob`, adaptive banners, native ads, and interstitial frequency controls. The application also loads `app_config` from the server and exposes the website admin portal, including `/admin/ads`, inside the Android admin experience.

The new system will extend these existing flows rather than replace them wholesale.

## Core Architecture

The server is the source of truth for ad policy and campaign decisions. The Android application acts primarily as an ad renderer and playback coordinator.

Main components:

1. **Campaign Manager** in `/admin/ads`.
2. **Ad Decision API** that evaluates policy, targeting, placement, frequency caps, priority, and fallback order.
3. **Tracking API** for ad lifecycle events.
4. **Age Policy Engine** that uses an Age Gate and persists only a coarse age group.
5. **Membership Policy Engine** for Free, Premium, and VIP users.
6. **Player Ad Controller** for pre-roll, mid-roll, post-roll, pause ads, overlays, VAST/VMAP, private video, and AdMob transitions.
7. **Analytics Aggregation** for fast dashboard reporting.
8. **Remote Kill Switches** for all ads or individual ad systems.

## Supported Advertising Sources

The platform supports:

- Google AdMob banner.
- Google AdMob native.
- Google AdMob interstitial.
- Google AdMob rewarded.
- Google AdMob app-open where appropriate.
- Private image campaigns uploaded through the admin panel.
- Private video campaigns uploaded through the admin panel.
- Externally hosted image/video creatives.
- VAST ad tags.
- VMAP schedules.
- Optional HTML creatives only where rendered safely in a constrained WebView placement.

Every placement defines a server-controlled fallback chain, for example:

`Private Campaign -> VAST/VMAP -> AdMob -> No Ad`

or

`AdMob Native -> Private Banner -> No Ad`.

A failure at one source advances to the next source. If all sources fail, content continues with no ad.

## Age Gate and Privacy

The application shows an Age Gate at first launch or before ad policy is needed.

The user enters a full date of birth. The application or server calculates an age category and then discards the raw date of birth. Only the age category and a policy-verification timestamp are persisted.

Initial age groups:

- `child`
- `teen`
- `adult`

The raw date of birth is not retained by the ad platform.

For `child` and conservative/unknown states:

- No behavioral targeting.
- No unrestricted custom campaigns.
- Only explicitly child-safe eligible campaigns.
- Non-personalized ad requests where required.
- Consent and privacy handling must integrate with Google UMP or equivalent platform consent requirements.

If age or consent state is unavailable, the system fails toward the more conservative policy.

## Membership Policy

Membership tiers:

- **Free**: normal campaign policy and full supported ad inventory.
- **Premium**: reduced ad frequency and/or reduced placements according to server settings.
- **VIP**: no ads.

VIP should short-circuit ad decision processing and return `show_ad: false`.

## Campaign Management

Each campaign supports:

- Name.
- Status: draft, scheduled, active, paused, completed, archived.
- Priority.
- Start timestamp.
- End timestamp.
- Ad source/type.
- Creative(s).
- Click URL.
- CTA label.
- Placement assignments.
- Audience targeting.
- Content targeting.
- Frequency caps.
- Video rules.
- Skip policy.
- Daily and total impression/click caps where configured.
- Optional budget metadata.
- Child-safe eligibility flag.
- Audit metadata.

Campaigns can be created, copied, edited, paused, resumed, archived, and deleted according to permissions.

## Placements

Initial placement registry:

- `app_open`
- `home_top`
- `home_feed`
- `details`
- `between_episodes`
- `player_preroll`
- `player_midroll`
- `player_postroll`
- `player_pause`
- `player_overlay_top`
- `player_overlay_bottom`

Each placement contains:

- Enabled/disabled state.
- Allowed ad source types.
- Fallback order.
- Request timeout.
- Default frequency rules.
- Allowed membership tiers.
- Allowed age groups.

New placements should be addable without requiring changes to existing campaign records.

## Targeting

Targeting may include:

- Membership tier.
- Age group.
- Country.
- Locale/language.
- Platform.
- App version range.
- Content type.
- Content ID.
- Genre/category.

Targeting is permission-based, not permissive by default. A campaign that is not explicitly eligible for `child` must never be selected for a child profile.

## Database Model

Recommended logical tables:

- `ad_campaigns`
- `ad_creatives`
- `ad_placements`
- `ad_campaign_placements`
- `ad_targeting`
- `ad_frequency_rules`
- `ad_video_rules`
- `ad_admob_units`
- `ad_settings`
- `ad_events`
- `ad_daily_stats`
- `user_ad_profiles`

### ad_campaigns

Stores campaign identity, state, schedule, priority, source type, caps, and audit fields.

### ad_creatives

Stores image/video/upload/external/VAST/VMAP creative metadata and click destination.

### ad_placements

Stores placement registry and policy defaults.

### ad_campaign_placements

Many-to-many campaign-to-placement mapping.

### ad_targeting

Stores normalized targeting rules.

### ad_frequency_rules

Stores per-campaign and/or per-placement caps such as session maximum, minimum interval, daily maximum, episode cadence, or playback cadence.

### ad_video_rules

Stores pre-roll/mid-roll/post-roll configuration, mid-roll cue points, seek behavior, skip policy, and timeout values.

### ad_admob_units

Stores AdMob unit IDs by platform, type, and logical placement, plus enabled/test-mode metadata.

### ad_settings

Stores global kill switches and system defaults.

### ad_events

Stores raw or batched event records with decision ID, campaign, creative, placement, event type, timestamp, coarse user/session context, and error metadata.

### ad_daily_stats

Stores aggregated daily reporting values to keep analytics fast.

### user_ad_profiles

Stores ad-relevant non-sensitive profile data only, such as age group, membership tier cache where appropriate, and consent state/version.

## Ad Decision API

Endpoint concept:

`POST /mobile-api/ads/decision`

Example request:

```json
{
  "placement": "player_preroll",
  "platform": "android",
  "app_version": "1.14.0",
  "user_tier": "free",
  "age_group": "adult",
  "locale": "ar",
  "content_type": "series",
  "content_id": 1256,
  "genre_ids": [18, 10749],
  "session_id": "..."
}
```

Decision order:

1. Global emergency switch.
2. Membership policy.
3. Age/consent eligibility.
4. Placement enabled state.
5. Active campaign schedule.
6. Placement matching.
7. Audience and content targeting.
8. Frequency caps.
9. Priority and campaign selection.
10. Creative selection.
11. Fallback source selection.

Example response:

```json
{
  "ok": true,
  "show_ad": true,
  "decision_id": "dec_xxxxx",
  "type": "vast",
  "placement": "player_preroll",
  "creative": {
    "vast_url": "https://example.invalid/tag",
    "skip_after": 5
  },
  "tracking": {
    "token": "short_lived_token"
  }
}
```

No eligible ad:

```json
{
  "ok": true,
  "show_ad": false
}
```

The decision endpoint must be cached carefully enough to be fast while still honoring campaign edits and kill switches quickly.

## Tracking API

Endpoint concept:

`POST /mobile-api/ads/event`

Supported event types:

- `request`
- `filled`
- `impression`
- `click`
- `video_start`
- `quartile_25`
- `quartile_50`
- `quartile_75`
- `complete`
- `skip`
- `error`

Tracking uses a short-lived token tied to the server-generated `decision_id`. The server must not trust campaign or creative IDs supplied independently by the client.

The application should batch non-critical tracking events into a small queue when practical. Tracking failure must not block playback.

## Frequency Capping

Frequency capping is enforced both server-side and session-side.

Examples:

- Minimum 7 minutes between interstitials.
- Maximum 4 interstitials per day.
- One ad every 2 episode transitions.
- One VAST break every 15 minutes.
- One ad per session for a specific placement.

Server-side caps are authoritative. Client-side caps reduce unnecessary requests and improve responsiveness.

## Player Ad Controller

The Player Ad Controller is isolated from the content player.

Playback flow:

`Resolve media -> prepare content -> request pre-roll -> ad or no-ad -> play content -> mid-roll cue(s) -> resume content -> post-roll -> next action`

### Pre-roll

The app requests `player_preroll` while content is being prepared. A short timeout applies. If no usable ad is ready by timeout, playback starts immediately.

### Mid-roll

Supported cue styles:

- Absolute time, e.g. `00:10:00`.
- Percentage, e.g. `50%`.
- Repeating interval, e.g. every 20 minutes.
- VMAP-provided cue schedule.

When a cue is reached:

1. Save exact content position.
2. Pause content.
3. Activate ad session.
4. Play ad.
5. Dispose ad session.
6. Restore content session.
7. Resume from the saved position.

Each cue has a completion state so seeking backward does not automatically replay an already consumed break.

### Seek Policy

Per-policy options:

- `skip_missed`
- `latest_missed_only`
- `enforce_next_break`

Recommended defaults:

- Free: `latest_missed_only`.
- Premium: `skip_missed`.

### Post-roll

Optional and separately configurable by content type. For series, post-roll may occur before auto-next. For movies, it may occur before completion UI.

### Pause Ads

A pause placement may show a static/private/native creative over paused content. It disappears immediately when playback resumes.

### Overlay Ads

Top/bottom overlay placements may display without pausing content. They must respect subtitles, controls, safe areas, and close-button policy.

### Ad Session Isolation

Only one media session may own audible playback at a time.

During ads:

- Content session is paused.
- Ad session is active.

After ads:

- Ad session is destroyed.
- Content session resumes.

This prevents overlapping audio/video sessions.

## VAST / VMAP

Use Google IMA SDK or an equivalent standards-compliant Android ad playback layer for VAST/VMAP handling rather than manually parsing tags and converting them into direct media URLs.

The integration must support, where exposed by the SDK/tag:

- Wrappers.
- Impressions.
- Click-through.
- Skip controls.
- Quartile events.
- Error reporting.
- VMAP ad break scheduling.
- Companion metadata where relevant.

VAST/VMAP failure must fall through to the next configured source or no-ad.

## Private Video Ads

Private video creatives are controlled directly by the app's ad overlay/player component.

Example creative response:

```json
{
  "type": "private_video",
  "src": "https://shortseris.online/uploads/ads/campaign-22.mp4",
  "duration": 20,
  "skip_after": 5,
  "click_url": "https://example.invalid"
}
```

Private video ads may be preloaded according to server TTL and cache policy.

## Skip Rules

Per-campaign options:

- Not skippable.
- Skip after N seconds.
- Skip after percentage watched.
- Immediately skippable.

For VAST/VMAP inventory, the ad tag/SDK skip constraints take precedence unless the provider explicitly allows local override.

## Rewarded Ads

Supported optional use cases:

- Watch an ad to unlock an episode.
- Watch an ad for a temporary ad-free window.
- Watch an ad to unlock an optional feature such as HD where product policy permits.

Rewarded flows must be explicit opt-in interactions and must not silently replace normal playback.

## Application AdMob Integration

The existing `AdMobService` remains the low-level AdMob adapter but becomes increasingly policy-agnostic.

Remote configuration will continue to support:

- Master AdMob enable/disable.
- Test mode.
- Banner unit ID.
- Native home unit ID.
- Native details unit ID.
- Interstitial unit ID.
- New rewarded and app-open IDs.

Existing local frequency fields can remain as defensive fallback but the server decision engine becomes authoritative for campaign behavior.

AdMob initialization must remain deferred until after the first frame so third-party SDK initialization cannot block application startup.

## Admin Panel: `/admin/ads`

The page becomes a full Ads Studio with these areas:

### Dashboard

Shows:

- Master ads switch.
- AdMob switch.
- VAST/VMAP switch.
- Private ads switch.
- Active campaigns.
- Impressions.
- Clicks.
- CTR.
- Video starts.
- Completion rate.
- Skip rate.
- Fill rate.
- Errors.

### Campaigns

Create, edit, copy, schedule, pause, resume, archive, and delete campaigns.

### Placements

Manage placement enablement, timeout, source order, and default rules.

### Targeting

Manage membership, age, locale, country, content, genre, and app-version targeting.

### Video Rules

Manage pre-roll, mid-roll, post-roll, seek policy, skip policy, cue points, and timeouts.

### AdMob Units

Manage app ID and unit IDs for banner/native/interstitial/rewarded/app-open, plus enable/disable and test mode.

### Private Ads

Upload image/video creatives or provide external URLs.

### Analytics

Filter by date, campaign, placement, source, event type, age group, membership tier, and platform.

### Emergency Controls

Always-visible controls:

- Disable all ads.
- Disable AdMob only.
- Disable VAST/VMAP only.
- Disable private campaigns only.

Changes should propagate through remote configuration/decision APIs without an APK release.

## Admin Experience Inside Android App

The Android admin studio will include a lightweight ads summary page with:

- Overall ad system status.
- Active campaign count.
- Today's impressions/clicks/errors.
- Quick master on/off controls where permitted.
- Link into the full `/admin/ads` web panel for detailed editing.

The website admin remains the canonical management UI to avoid duplicated business logic.

## Performance

Requirements:

- Decision API response should be fast and cache campaign eligibility.
- Active campaign cache is invalidated/rebuilt on campaign edits.
- Raw events are written efficiently.
- Dashboard reads mostly from `ad_daily_stats`, not large raw event scans.
- Mid-roll decisions are preloaded shortly before cue time, not all at once.
- Ad failures use short bounded timeouts.
- The app does not retry ad requests indefinitely.

## Reliability / Fail-Safe Behavior

Advertising is always non-blocking unless a user explicitly chooses a rewarded flow.

On any of the following:

- Decision API timeout.
- No internet.
- AdMob no-fill.
- VAST error.
- VMAP error.
- IMA failure.
- Private creative load error.
- Tracking error.

The application:

1. Records the error if possible.
2. Disposes the ad session.
3. Restores the content player.
4. Continues playback.

The ad system must never produce an infinite spinner or prevent the application from reaching its first frame.

## Security

- Campaign mutation APIs require administrator authorization.
- CSRF protection applies to web-admin mutations.
- API authorization and role checks are server-side.
- Tracking tokens are short-lived and tied to `decision_id`.
- Rate limiting applies to tracking and decision endpoints.
- Sensitive provider secrets are not returned to the mobile app.
- Uploaded creatives are validated by MIME type, size, extension, and storage rules.
- Audit log records administrative changes.

## Consent and Policy Controls

The architecture includes consent state as policy input. Google UMP or equivalent consent handling must be integrated before personalized ad requests where required.

The system must allow the admin to force non-personalized behavior globally or by age group/region.

## Migration Strategy

Implementation is incremental to reduce risk:

1. Preserve existing AdMob behavior and current remote config.
2. Add database schema and server APIs behind feature flags.
3. Add Age Gate and ad profile policy.
4. Add server decision engine for existing banner/native/interstitial placements.
5. Add admin Ads Studio.
6. Add private image/video campaigns.
7. Add Player Ad Controller.
8. Add VAST/VMAP/IMA integration.
9. Add rewarded/app-open support.
10. Add analytics aggregation and dashboards.
11. Switch existing local placement decisions to server-authoritative decisions.
12. Keep emergency rollback switches throughout rollout.

## Testing Strategy

### Server

- Unit tests for campaign eligibility.
- Unit tests for age/membership policy.
- Frequency-cap tests.
- Targeting tests.
- Decision priority/fallback tests.
- Tracking token validation tests.
- Admin permission tests.

### Flutter / Android

- Age Gate tests.
- Ad decision parsing tests.
- Fail-open timeout tests.
- Banner/native/interstitial rendering tests.
- Playback state restoration tests.
- Mid-roll cue and seek tests.
- VIP no-ad tests.
- Child policy tests.
- AdMob initialization failure tests.
- Offline/no-ad-server tests.

### End-to-End

- Free adult user with pre-roll.
- Premium reduced-frequency session.
- VIP zero-ad session.
- Child profile with child-safe campaign only.
- VAST success/failure.
- Private video success/failure.
- Mid-roll seek forward/backward.
- Campaign change without APK update.
- Emergency kill switch during active rollout.

## Acceptance Criteria

The feature is complete when:

1. Ads can be globally enabled/disabled from the server without a new APK.
2. AdMob, private image/video, VAST, and VMAP inventory are supported.
3. Pre-roll, mid-roll, and post-roll function without breaking content playback.
4. Age Gate stores only age category, not raw date of birth.
5. Free/Premium/VIP policies are enforced server-side.
6. Child profiles cannot receive campaigns not marked child-safe.
7. Campaigns can be targeted by supported audience/content attributes.
8. Frequency caps are enforced.
9. Analytics events and daily summaries are available.
10. Ad failures never block app startup or normal media playback.
11. `/admin/ads` is the canonical management panel.
12. Existing app admin can open the full Ads Studio and show summary information.
13. Existing AdMob production integration remains functional throughout migration.
14. A tested rollback path exists through remote kill switches.

## Non-Goals for Initial Release

To keep the first production implementation controlled, the initial release will not attempt to build a full third-party advertising exchange, real-time bidding platform, advertiser self-service portal, or complex invoicing/billing engine. The architecture should not prevent those from being added later, but they are outside the initial scope.
