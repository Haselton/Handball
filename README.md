# Handball

A portrait, first-person wall-ball game for Android. Tap the approaching blue
racquetball to drive it back into the cinder-block wall. Every wall impact adds
to the rally and gradually raises the speed.

## Current playable slice

- Procedural 3D cinder-block court with PBR-ready materials
- 120 Hz tuned ball simulation with swept gameplay boundaries
- One-thumb screen-space striking and directional aim
- Wall rebound, spin influence, progressive speed, scoring, and best score
- Impact light, procedural rubber/concrete audio, hand-strike animation, haptics
- Ball-drop loss state and immediate restart
- Ad service boundary for interstitial loss ads and rewarded rally saves
- Android portrait export preset and GitHub Actions debug APK workflow

## Run locally

Open this directory in Godot 4.4 or newer and run `main.tscn`. The project uses
the mobile-compatible GL renderer and selects Jolt Physics.

## Blender assets

Open Blender 4.x and run `blender/create_handball_assets.py`. It creates a
beveled block wall, court floor, blue ball, a `.blend` source, and exports a GLB
to `assets/handball_court.glb`. The live prototype constructs equivalent
geometry at runtime until the finished GLB and rigged hand are approved.

## Android online services

`native/play_games` implements the `HandballPlayGames` Godot singleton using
Google Play Games Services v2. The Android workflow copies the Java sources,
registers the singleton in the manifest, initializes the SDK from Application,
and checks the finished AAB for the native classes and registrations.
The leaderboard displays completed courts (larger is better). Progress is saved
locally and submitted after connection; opening Global while signed out resumes
opening the leaderboard after a successful connection.

All ads use the included Poing AdMob plugin. The old `HandballAdMob` placeholder
is removed. The service updates UMP privacy choices before initialization, retains
the billboard placement, logs load errors, retries banners with backoff, and
resumes a saved rally only after the SDK reports an earned reward. The SERVICES
button shows the latest connection/ad status for device troubleshooting.

### Required production configuration

Set these GitHub repository Actions variables (or the corresponding `[handball]`
settings in `project.godot`):

| Variable | Value from console |
| --- | --- |
| `PLAY_GAMES_APP_ID` | Numeric Game services project ID |
| `PLAY_GAMES_LEADERBOARD_ID` | Published leaderboard ID for completed courts |
| `ADMOB_INTERSTITIAL_ID` | Handball interstitial ad unit ID |
| `ADMOB_REWARDED_ID` | Handball rewarded ad unit ID |

The Handball production AdMob application and all three ad unit IDs are configured
in `project.godot`. Interstitial uses `Between Rounds Interstitial`; rewarded uses
`Save Rally Rewarded` with a reward of one `Rally Continue`. Actions variables can
override these values when needed. The Play Games project and leaderboard IDs
remain blank until obtained from the owner's console.
Production export fails before building when required values are missing,
malformed, or contain Google's sample ad publisher ID.

In Play Console, link `com.haseltonmediagroup.handball` with the **Play App Signing**
certificate SHA-1, configure the leaderboard as an integer ordered largest first,
and publish the Play Games configuration. Publishing the Android app alone does
not publish its Play Games configuration. Set up/publish the applicable privacy
messages in AdMob and confirm the Handball app is ready to serve ads.

Branch builds and default manual runs are explicitly **diagnostic**: a separate
`com.haseltonmediagroup.handball.diagnostic` package with Google sample ads and
no production Play Games IDs. They verify compilation and packaging, not live
authentication or production ad fill. Main and manual `production` builds require
the real configuration. Do not upload diagnostic artifacts to the production app.

After configuring the IDs, test the production-signed app through a Play testing
track on a real device: connection, Global leaderboard, completed-court submission,
banner, rewarded rally continuation, and interstitial dismissal. This device test
is still required; build success does not prove account-side setup or ad serving.

Interstitial policy in this build:

- The first loss never shows an interstitial.
- An interstitial becomes eligible after two completed rounds.
- At least 60 seconds must pass between interstitials.
- Rewarded video is reserved for `SAVE RALLY`.

## Art target

See `assets/reference/handball-gameplay-mockup.png` for the approved visual
direction.
