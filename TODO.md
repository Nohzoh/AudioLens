# Todo list - AudioLens

Completed tasks and test results are archived in [`CHANGELOG.md`](CHANGELOG.md).

---

## 📌 Legend
- **Status**: ` ` To do | `~` In progress | `x` Done
- **Priority**: 🔥 Critical | ⚡ High | 📈 Medium | 🌱 Low
- **Effort**: ⭐ (1-2h) | ⭐⭐ (1/2 day) | ⭐⭐⭐ (1 day) | ⭐⭐⭐⭐ (2-3 days) | ⭐⭐⭐⭐⭐ (5+ days)
- **IDs**: unique sequence shared with `CHANGELOG.md` — check the highest ID across both files before creating a new one (`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`)
- **Added**: every new task carries its creation date (`**Added**: YYYY-MM-DD`) — helps spot low-priority tasks that have been lingering. No backfilling for existing tasks with unknown dates.

---

## 🔥 Critical / Blocking
*Must be handled before any new feature*

*No critical tasks in progress.*

---

## ⚡ High impact / Short term
*To handle within 1-2 weeks*

*No high-impact tasks in progress.*

---

## 📈 Medium impact / Medium term
*To handle within 1-2 months*

- [ ] **T45** 📈 ⭐⭐ - Define a **retention policy** for images, WAV files, caches, temp files
  - **Includes**: temp file cleanup (ex-T11)

- [ ] **T70** 📈 ⭐⭐ - Migrate to **dio** for cancellable HTTP requests
  - **Related to**: T43 (interruptible cancellation)
  - **Why**: The `http` package doesn't support native cancellation. `dio` offers `cancel()` on requests
  - **Services affected**: GeminiApiService, GeminiTtsService
  - **Impact**: Will enable true interruptibility of cloud calls

- [ ] **T85** 📈 ⭐⭐⭐⭐ - Run the **analysis in the background** and **notify** when the audio is ready
  - **Added**: 2026-08-16
  - **Context**: user request following a history of freezes when used alongside GPS-heavy apps (AllTrails, Ingress). Code analysis (2026-08-16): no background mechanism today — no foreground service, no `WorkManager`, no wakelock. The Android process generally keeps running while the app is backgrounded, but nothing protects it: the OS can kill it at any time (memory pressure, Doze, battery optimization), in which case the analysis stops dead, with no notification. The only existing safety net: `home_screen.dart:72` writes a `pending` entry to the DB before starting the analysis, so at worst the user finds an entry to retry manually in the history (T13) — but no automatic resume and no notification
  - **To do**:
    - **Android foreground service** (persistent notification during the analysis) to make background execution reliable — required by Android 8+ for guaranteed background work beyond a few minutes
    - **Local notification** when the audio is ready (e.g. `flutter_local_notifications`, not yet in `pubspec.yaml`)
    - Patch `AndroidManifest.xml` (not committed, CI bootstrap — see `scripts/patch_signing.py` for the existing pattern) for the `FOREGROUND_SERVICE` permission and the service declaration
  - **Out of scope for now**: resuming an analysis interrupted mid-way (full restart from scratch, as today)

- [ ] **T75** 📈 ⭐⭐ - Add a **script style option** (a friend's suggestion)
  - **Examples**: "academic/historical" style vs. a style that leans into **anecdotes and storytelling**
  - **To do**: style picker in settings (and/or onboarding), pass the style to the AI prompt (`gemini_api_service.dart` + `gemini_nano_service.dart`), persistence via `SettingsService`
  - **Related to**: T48 (tone variants) — consider merging to avoid duplication

---

## 🌱 Low impact / Long term
*Backlog for future improvements*

- [ ] **T84** 🌱 ⭐⭐⭐⭐⭐ - **Play Store publication**
  - **Added**: 2026-08-15
  - **Already in place** (good starting point): working release signing (T79), `allowBackup=false` (T80), API key protected by allowlist (T81), secure key storage (T10), "AI-generated content" disclaimer already in the app (T72), stable `applicationId` `io.nohzoh.audiolens` (T63)
  - **Non-technical decisions/steps to handle first**:
    - Create a **Google Play developer account** ($25, one-time payment) — absolute prerequisite, no technical task can be tested for real before this
    - **Privacy policy** hosted publicly, with a link to provide in the Play Console listing — mandatory given the requested permissions (camera, location) and the fact that photos + position are sent to the Gemini API (third-party data sharing)
    - Play Console **"Data safety" form**: precisely declare what data is collected/shared (photo, GPS, script) and with whom (Google Gemini)
    - **Sensitive permissions declaration** (`ACCESS_FINE_LOCATION`, `CAMERA`) — justification required by Google, location is especially scrutinized
    - Check whether **Play policies on generative AI apps** require additional disclosures beyond the existing disclaimer (T72)
  - **To do, technical**:
    - **AAB instead of APK**: the Play Store requires a `.aab` (`flutter build appbundle --release`), not the current APK — new job or dedicated CI step
    - **versionCode strategy**: `pubspec.yaml` has been stuck at `0.1.0+1` since the start, never bumped — every Play Console upload needs a strictly increasing `versionCode`, needs automating (e.g. `versionCode` based on the CI run number or a committed counter)
    - **Missing app icon**: `assets/images/` is empty (just a `.gitkeep`) — the app currently runs with the default Flutter icon (`android/app/src/main/res/mipmap-*/ic_launcher.png`, regenerated on every CI bootstrap). A real icon is required before any submission
    - **Store listing assets**: short/long description, category, feature graphic, screenshots
    - **Automate the upload** to Play Console from CI (e.g. `r0adkll/upload-google-play` action, service account key as a secret) — only once the developer account exists
  - **Recommendation**: don't treat this as a single task — the non-technical steps (account, privacy policy, data safety) are blocking and must happen before any CI automation

- [ ] **T77** 🌱 ⭐⭐⭐⭐⭐ - **iOS port** — get AudioLens running on iPhone
  - **Added**: 2026-08-15
  - **Context**: 100% Android project today, `ios/` doesn't even exist yet — will need to generate the scaffold (`flutter create --platforms=ios .`)
  - **Blockers to resolve before starting**:
    - **Gemini Nano has no iOS equivalent** (`GeminiNanoPlugin.kt` relies on the Android AICore API) — no equivalent native solution identified. Decision needed: disable local mode on iOS (cloud only), or replace it with another on-device model?
    - **Apple developer account** ($99/year) needed to sign/distribute (TestFlight or sideload), unlike the current Android APK distributed directly from GitHub Actions
    - **iOS support for `sherpa_onnx`** (local Piper) needs checking before committing — not confirmed from this environment
  - **Native work to duplicate in Swift** (3 active MethodChannels):
    - `audio_guide/location` (`LocationPlugin.kt`) → CoreLocation + reverse geocoding, `Info.plist` permissions
    - `audio_guide/audio_player` (`AudioPlayerPlugin.kt`, `MediaPlayer`) → `AVAudioPlayer`
    - `audio_guide/gemini_nano` (`GeminiNanoPlugin.kt`) → blocked by the Gemini Nano point above
  - **CI**: new workflow (`build-ios.yml`), macOS runner (paid/limited on GitHub Actions), certificates/provisioning as secrets
  - **Recommendation**: don't treat this as a single task — break it down once the blockers above are resolved

- [ ] **T12** 🌱 ⭐⭐⭐ - Merge the **home screen's "Recently visited" grid and the history screen**
  - **Clarified (2026-08-16)**: "gallery" meant the thumbnail grid on the home screen (`home_screen.dart`), not a dedicated screen — none exists
  - **Option**: Make history the main view, with access to a new analysis and to settings

- [ ] **T15** 🌱 ⭐ - Allow **configuring playback speed**

- [ ] **T17** 🌱 ⭐⭐ - Add a **more detailed or shorter analysis mode**

- [ ] **T18** 🌱 ⭐⭐⭐ - Allow **choosing voice language/style**

- [ ] **T19** 🌱 ⭐⭐ - Add **sharing/exporting** the text or audio

- [ ] **T21** 🌱 ⭐⭐⭐ - Add **richer interactions** to the playback screen
  - **Clarified (2026-08-16)**: ideas selected —
    - Skip forward/back by X seconds (podcast-style), instead of just play/pause
    - Long-press a sentence in the displayed text to jump audio playback to that spot
    - Mini-map of the GPS location, in addition to the text address
    - Swipe gesture to navigate between history entries
  - **Target**: `player_screen.dart`

- [ ] **T22** 🌱 ⭐ - Allow **pausing** audio playback from the home screen's "Recently visited" grid
  - **Clarified (2026-08-16)**: same clarification as T12 — "gallery" = the thumbnail grid on `home_screen.dart`

- [ ] **T86** 🌱 ⭐ - Fix Ko-fi **icon contrast** on the home screen
  - **Added**: 2026-08-16
  - **Reported**: the Ko-fi button on the home screen looks noticeably more washed out than on the history/settings screens right next to it
  - **Investigated**: the icon color is actually identical (`Colors.grey[600]`, `kofi_button.dart:28`, the default) on 5 of the 6 screens that show it (home, history, settings, about_analysis, logs) — there's no differing constant to unify. The difference is contrast: `home_screen.dart:246-256` renders it inside a custom gradient `Container` (`theme.colorScheme.surface` → `surfaceContainerHigh`), while the other 4 screens use a plain `AppBar(backgroundColor: Colors.transparent)` sitting on the flat Scaffold background — same fixed color, different backdrop, so it reads differently. `player_screen.dart:106` is the one legitimate exception (`iconColor: Colors.white70`), intentional for its dark photo backdrop — leave that one alone
  - **To do**: pick an icon color/opacity with enough contrast against the home screen's specific gradient (or reconsider using that gradient behind the icon row) — applying "the same color" everywhere won't fix it since it's already the same color

- [ ] **T23** 🌱 ⭐⭐⭐ - Improve **visual accessibility**
  - **Needs breaking down into subtasks**: Contrast, button sizes, readability

- [ ] **T24** 🌱 ⭐⭐⭐⭐ - Prepare an **internationalization (i18n) baseline**

- [ ] **T48** 🌱 ⭐⭐ - Add **analysis tone variants** (child, expert, storytelling, concise)

- [ ] **T49** 🌱 ⭐⭐ - Allow **choosing the output language** independently of the interface language

- [ ] **T50** 🌱 ⭐⭐⭐ - **Re-run an old analysis** with a new style/length/language/model

- [ ] **T51** 🌱 ⭐⭐⭐ - Add **favorites or trip collections** (e.g. Louvre, Rome, personal trip)

- [ ] **T67** 🌱 ⭐⭐⭐ - **Extract all static strings** for i18n
  - Lays the groundwork for T24 (internationalization)
  - Use the `intl` package (already present)
  - Create `.arb` files for French/English

- [ ] **T68** 🌱 ⭐⭐⭐ - **Extend test coverage** to untested services
  - **Updated**: 2026-08-15 — `MediaPipeService` removed from scope (deleted in T06); `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService` added (born from the T06 refactor, still without dedicated tests)
  - **Updated**: 2026-08-16 — T09 added migration-path coverage for `HistoryService` (`history_service_migration_test.dart`); its CRUD methods (`addPendingEntry`, `completeEntry`, `failEntry`, `saveAudioPath`, `deleteEntry`) are still untested
  - Target: `LocationService`, `WikipediaService`, `ExifLocationService`, `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService`
  - Goal: 80% coverage on critical services

---

## 📝 To fill in as the project goes

- [ ] **T34** - Add **new improvement ideas** (issue tracker?)
- [ ] **T35** - **Prioritize tasks** by impact/effort (ROI table?)
- [ ] **T36** - **Track implementation progress** (Kanban board?)
- [ ] **T37** - Add a **test coverage baseline** and keep it up
