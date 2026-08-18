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

---

## 🌱 Low impact / Long term
*Backlog for future improvements*

- [ ] **T84** 🌱 ⭐⭐⭐⭐⭐ - **Play Store publication**
  - **Added**: 2026-08-15
  - **Already in place** (good starting point): working release signing (T79), `allowBackup=false` (T80), API key protected by allowlist (T81), secure key storage (T10), "AI-generated content" disclaimer, now localized and shown on the player screen itself, not just buried in a detail sub-screen (T72), stable `applicationId` `io.nohzoh.audiolens` (T63), a real custom app icon (headphone/soundwave design, `android/app/src/main/res/mipmap-*/ic_launcher.png` — the "missing icon" note below was stale, corrected 2026-08-18), English localization alongside French (T67)
  - **Updated (2026-08-18)**: CI now also builds a `.aab` (`Build App Bundle (release)` step, right after the existing APK build, reusing the same signing) and both the APK and AAB get a strictly increasing `versionCode` via `--build-number=${{ github.run_number }}` — the two "technical" items below are done
  - **Non-technical decisions/steps to handle first** — still blocking, nothing further to automate until these exist:
    - Create a **Google Play developer account** ($25, one-time payment) — absolute prerequisite, no technical task can be tested for real before this
    - **Privacy policy** hosted publicly, with a link to provide in the Play Console listing — mandatory given the requested permissions (camera, location) and the fact that photos + position are sent to the Gemini API (third-party data sharing). Can be hosted directly in this repo (a Markdown file, or GitHub Pages) — no separate site needed
    - Play Console **"Data safety" form**: precisely declare what data is collected/shared (photo, GPS, script) and with whom (Google Gemini)
    - **Sensitive permissions declaration** — justification required by Google, location is especially scrutinized. Now also covers `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_DATA_SYNC`/`POST_NOTIFICATIONS` (T85), not just `ACCESS_FINE_LOCATION`/`CAMERA` as originally noted
    - Check whether **Play policies on generative AI apps** require additional disclosures beyond the existing disclaimer (T72)
  - **To do, technical**:
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

- [ ] **T19** 🌱 ⭐⭐ - Add **sharing/exporting** the text or audio

- [ ] **T21** 🌱 ⭐⭐⭐ - Add **richer interactions** to the playback screen
  - **Clarified (2026-08-16)**: ideas selected —
    - Skip forward/back by X seconds (podcast-style), instead of just play/pause
    - Long-press a sentence in the displayed text to jump audio playback to that spot
    - Mini-map of the GPS location, in addition to the text address
    - Swipe gesture to navigate between history entries
  - **Target**: `player_screen.dart`

- [ ] **T22** 🌱 ⭐ - Allow **pausing** audio playback from the home screen's "Recently visited" grid
  - **Clarified (2026-08-16)**: "gallery" means the thumbnail grid on the home screen (`home_screen.dart`), not a dedicated screen

- [ ] **T23** 🌱 ⭐⭐⭐ - Improve **visual accessibility**
  - **Needs breaking down into subtasks**: Contrast, button sizes, readability

- [ ] **T24** 🌱 ⭐⭐⭐⭐ - Prepare an **internationalization (i18n) baseline**
  - **Updated (2026-08-17)**: T67 delivered most of this baseline as a side effect of doing string extraction properly — French/English ARB files, `flutter gen-l10n` wired up, and the app now follows the device's system locale automatically (English fallback for anything else, chosen to reach more non-French speakers). **Remaining for this task**: screens/widgets' error-producing utilities (`lib/utils/user_message_utils.dart`, `lib/utils/build_info.dart`) and all service-layer error strings (`GuideError`/`Exception` messages surfaced via SnackBar) are still French-only — T67 deliberately scoped those out. `about_analysis_screen.dart` (a debug screen) was also left untranslated. No in-app language picker exists (by design, T67) — only automatic system-locale following.

- [ ] **T49** 🌱 ⭐⭐ - Allow **choosing the output language** independently of the interface language

- [ ] **T50** 🌱 ⭐⭐⭐ - **Re-run an old analysis** with a new style/length/language/model

- [ ] **T51** 🌱 ⭐⭐⭐ - Add **favorites or trip collections** (e.g. Louvre, Rome, personal trip)

---

## 📝 To fill in as the project goes

- [ ] **T34** - Add **new improvement ideas** (issue tracker?)
- [ ] **T35** - **Prioritize tasks** by impact/effort (ROI table?)
- [ ] **T36** - **Track implementation progress** (Kanban board?)
- [ ] **T37** - Add a **test coverage baseline** and keep it up
