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

## AdMob production hook

`scripts/ad_service.gd` expects an Android plugin singleton named
`HandballAdMob`. Gameplay never blocks if the plugin or an ad is unavailable.
Use Google test ad unit IDs during testing. Before production, connect the real
HMG AdMob app/ad-unit IDs through the Android plugin and consent flow.

Interstitial policy in this build:

- The first loss never shows an interstitial.
- An interstitial becomes eligible after two completed rounds.
- At least 60 seconds must pass between interstitials.
- Rewarded video is reserved for `SAVE RALLY`.

## Art target

See `assets/reference/handball-gameplay-mockup.png` for the approved visual
direction.
