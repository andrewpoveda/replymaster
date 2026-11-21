# Project Instructions

## Overview

Vocal is an iPhone-first accessibility app for MicroLumin M6 glasses. The iPhone handles speech recognition and future vision processing; the glasses render short, high-contrast messages.

## Current targets

- `ios-livecaptions/` is the iPhone Swift app.
- `glasses-hello/` is the Android app installed directly on the glasses.
- `MLDemo` in `/Users/albertlieyeong/Downloads/Microlumin_Ship/04_Demo_Apps/MLDemo` is the vendor iPhone control app and SDK reference.

## Development rules

- Keep captions readable on the 640×480 glasses display: black background, bright text, and at most two lines.
- Keep the iPhone as the source of truth for speech and vision processing.
- Use `adb` only for glasses installation, launching, and logs.
- Do not commit signing certificates, provisioning profiles, SDK secrets, or vendor confidential assets.
- Prefer the existing TCP caption protocol on port `8787` until the vendor glasses-side SDK is available.
- Update `README.md` when build or demo steps change.

## Validation

Build the glasses app with the Gradle wrapper from the MicroLumin SDK package and build the iPhone app with Xcode. A generic iPhone build can use `CODE_SIGNING_ALLOWED=NO`; installing on a physical iPhone requires the developer's Apple Team and provisioning profile.
