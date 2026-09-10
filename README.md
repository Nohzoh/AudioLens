# 🎧 AudioLens

[![Tests](https://github.com/Nohzoh/AudioLens/actions/workflows/test.yml/badge.svg)](https://github.com/Nohzoh/AudioLens/actions/workflows/test.yml)
[![Build Android](https://github.com/Nohzoh/AudioLens/actions/workflows/build-android.yml/badge.svg)](https://github.com/Nohzoh/AudioLens/actions/workflows/build-android.yml)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/Nohzoh/AudioLens)](https://github.com/Nohzoh/AudioLens/commits/main)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

An AI-powered audio guide app for Android. Take a photo of a place and instantly get a spoken explanation — fully on-device or in the cloud, your choice.

**[📄 Project site & screenshots](https://nohzoh.github.io/AudioLens/)** · [ARCHITECTURE.md](ARCHITECTURE.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [PRIVACY.md](PRIVACY.md)

<p align="center">
  <img src="docs/assets/screenshot-home.png" width="220" alt="Home screen with recently visited places">
  <img src="docs/assets/screenshot-player.png" width="220" alt="Narration screen for a place">
  <img src="docs/assets/screenshot-history.png" width="220" alt="History of past visits">
</p>

<sup>Screenshots show example content used to illustrate the interface, not live captures.</sup>

## Features

- 📸 Photo capture to identify places
- 🗺️ Smart geolocation: photo **EXIF** coordinates, then **real-time GPS** as a fallback
- 📖 **Wikipedia** enrichment to add context to the place
- 🤖 AI analysis: **Gemini API** (cloud) or **Gemini Nano** (local, on-device)
- 🔊 Audio generation: **Gemini TTS** (cloud) with the device's **native Android TTS** as a fallback (offline, female/male voice choice)
- 🎚️ **Script style** (immersive, academic, anecdotal, concise) and **playback speed** (0.75x–1.5x), both configurable
- 📶 **Background-safe analysis**: a foreground service keeps the analysis alive while the app is backgrounded, with a notification when the audio is ready (or if it failed)
- 🧭 Location detection: the device needs coordinate access if the photo has no EXIF
- 📜 Analysis **history** (SQLite) with replay and retry
- 🧾 **Analysis detail sheet** (model, fallback, GPS, duration)
- 📋 Built-in **logs screen** for field debugging

## Architecture

```
Photo → EXIF GPS → Real-time GPS → Wikipedia → AI (vision) → LLM (script) → TTS → Audio
```

Pipeline details and diagrams in [`ARCHITECTURE.md`](ARCHITECTURE.md).

### Available modes
- **☁️ Cloud**: Uses your **Google account (Gemini API)** — best quality (~400 words)
- **📱 Local**: On-device **Gemini Nano** model — works without internet (~180 words)
- **⚡ Hybrid**: Cloud when available, **local fallback** otherwise

### AI providers
| Provider | Location | Model |
|---|---|---|
| **Gemini API** | Cloud | Configurable (`config.json`, default `gemini-3.6-flash`) |
| **Gemini Nano** | On-device | Local Android model |

### Text-to-Speech
| Engine | Location | Role |
|---|---|---|
| **Gemini TTS** | Cloud | Primary when an API key is configured |
| **Native Android TTS** | Local | Automatic fallback + offline mode, female/male voice choice |

## Privacy

No analytics, no tracking, no ads. Photos and location are used only to generate the guide, and are sent to Google's Gemini API **only in cloud mode** — local mode (Gemini Nano + on-device TTS) sends nothing off the device. Full details in [`PRIVACY.md`](PRIVACY.md).

## Download

**Android** only (an iOS port isn't started).

**Google Play — open testing** (anyone can join, no invite):

1. Join the [tester group](https://groups.google.com/g/audiolens) — one-time, required before Play lets you opt in.
2. [Opt in to testing](https://play.google.com/apps/testing/io.nohzoh.audiolens).
3. [Install from Google Play](https://play.google.com/store/apps/details?id=io.nohzoh.audiolens) — automatic updates from then on.

**GitHub Releases** — [latest release](https://github.com/Nohzoh/AudioLens/releases/latest), a signed APK to sideload directly.

> The APK on GitHub is signed with the project's upload key; the Google Play build is re-signed by Google (Play App Signing). The two have different signatures and can't update over each other — pick one source and stay on it.

## Building from source

```bash
flutter pub get
flutter build apk --debug
```

Full contributor setup (Android SDK, JDK, local signed build, tests) is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Configuration

Configuration (models, fallbacks, TTS, GPS) is centralized in [`config.json`](config.json), served from the project's GitHub Pages site and fetched at startup by `RemoteConfigService`, with built-in defaults as a fallback.

## Support

AudioLens is free and open-source. If it's useful to you, a tip helps keep it maintained:

[![Support on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/tarnaud)

## License

[AGPL-3.0](LICENSE)
