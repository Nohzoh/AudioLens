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

- [ ] **T100** 📈 ⭐ - **Bump the pinned Kotlin version (deprecation warning in CI)**
  - **Added**: 2026-08-19
  - **Source**: full log review of the first successful `workflow_dispatch` Play Store publish run (build 32287754331), requested after the user spotted a Kotlin warning live in the logs.
  - **Warning**: "Flutter support for your project's Kotlin version (2.2.10) will soon be dropped. Please upgrade your Kotlin version to a version of at least 2.2.20 soon."
  - **Odd detail to check first**: both `.github/workflows/build-android.yml` and `scripts/build_android_local.sh` patch the Kotlin version to `"2.2.0"` via sed — but the build actually reports **2.2.10**, not 2.2.0. Worth understanding why the patched value doesn't match the observed one (maybe the patch isn't matching/applying as intended, or another source overrides it) before just bumping the target string, so the fix doesn't just paper over a patch that silently isn't taking effect.
  - **Fix**: update the pinned version in both places to `>= 2.2.20` once the discrepancy above is understood.

- [ ] **T101** 📈 ⭐ - **Migrate `upload-google-play`'s deprecated `track:` input to `tracks:`**
  - **Added**: 2026-08-19
  - **Source**: same log review — `##[warning]WARNING!! 'track' is deprecated and will be removed in a future release. Please migrate to 'tracks'`, from `r0adkll/upload-google-play@v1` (added earlier tonight in `build-android.yml`'s "Publish to Play Store" step).
  - **Fix**: replace the single `track: ${{ inputs.track }}` input with the plural `tracks: [${{ inputs.track }}]` (or whatever list syntax the action's current docs specify) before `track` is actually removed and breaks the workflow outright.

- [ ] **T95** 📈 ⭐⭐⭐ - **Optional auto-purge of history after N days**
  - **Added**: 2026-08-19
  - **Source**: UX feedback from a closed-testing tester (fast turnaround — first feedback within minutes of the invite).
  - **Ask**: a Settings option to automatically delete photos, scripts, and audio for history entries older than N days (user-configurable). Default stays **manual only** (no auto-purge) — this only kicks in if the user explicitly opts in and picks a value.
  - **Related**: this is the broader retention-policy scope that was deliberately descoped from **T45** at the time (T45 stayed narrow — just the `image_picker` temp-file leak fix, not a general expiry policy) per explicit user choice. Revisit T45's notes before designing this.

- [ ] **T98** 📈 ⭐⭐⭐ - **Enable R8 minification/resource shrinking for release builds**
  - **Added**: 2026-08-19
  - **Source**: Play Console's "App optimization" score on the uploaded AAB — "Faible" (Low), with minification/R8 config showing "-"/"Aucune métadonnée R8". Confirms and closes the earlier open question about the "no deobfuscation file" warning: it's not that a mapping.txt existed and wasn't uploaded, R8 isn't actually enabled at all on this build (the 1% obfuscation shown is negligible/incidental, not real ProGuard/R8).
  - **Not blocking** — this is a quality/size score, not a review requirement.
  - **Risk to plan for**: enabling `isMinifyEnabled`/`isShrinkResources` in the release `buildType` is a classic Flutter footgun if ProGuard keep rules are incomplete — native plugins relying on reflection (ML Kit GenAI for Gemini Nano, JSON model parsing, etc.) can silently break at runtime in ways `flutter analyze`/`flutter test` won't catch. Needs a full real-device pass across every feature (both AI providers, both TTS engines, history, settings) after enabling, not just a build-success check. Also remember to upload the resulting `mapping.txt` to Play Console once this ships (closes the earlier warning for real).

- [ ] **T97** 📈 ⭐⭐⭐ - **Register AudioLens as a share target for photos**
  - **Added**: 2026-08-19
  - **Source**: closed-testing tester feedback.
  - **Ask**: appear in Android's native "Share via..." sheet when sharing a photo from another app (Gallery, another photo viewer, etc.), instead of only being reachable by opening AudioLens first and picking from the gallery.
  - **Implementation direction**: an `ACTION_SEND`/`ACTION_SEND_MULTIPLE` (`image/*`) intent filter in `AndroidManifest.xml`, plus handling the incoming share intent on the Flutter side (likely via a package like `receive_sharing_intent`, or a native platform-channel handler like the app's other integrations). Needs a UX decision: land on Home with the shared photo pre-loaded (closer to today's gallery-pick flow, including the no-EXIF-GPS map picker path), or jump straight into analysis.

- [ ] **T96** 📈 ⭐ - **History detail screen: top bar icons hard to see over bright photos**
  - **Added**: 2026-08-19
  - **Source**: same closed-testing tester — didn't recognize the top-right delete icon as a trash icon over a bright-sky photo (Kelpies of Falkirk screenshot).
  - **Root cause found**: `history_screen.dart`'s `HistoryDetailScreen` gradient overlay (`stops: [0.3, 1.0]`, black 0.3→0.95) barely darkens the very top of the screen — the top bar (back/info/delete icons) sits almost directly on the raw photo, no real scrim behind it. The delete icon's `Colors.redAccent` also has weak contrast against light backgrounds (sky, light walls) specifically.
  - **Fix direction**: strengthen the gradient's top stop (e.g. add a stop near 0.0 with non-zero opacity, not just starting at 0.3) and/or give each top-bar icon its own subtle circular scrim background, independent of photo content — same class of fix would help **T94**'s planned photo-mode toggle icon too, worth doing together.

---

## 🌱 Low impact / Long term
*Backlog for future improvements*

- [ ] **T92** 🌱 ⭐⭐ - **Map picker: lock north-up orientation + add a place search field**
  - **Added**: 2026-08-19
  - **Found via real-device testing**: on `map_picker_screen.dart` (shown when a gallery photo has no EXIF GPS, T87), the map currently rotates to follow device heading instead of staying fixed with north up — disorienting when picking a precise spot.
  - Also requested: a text field to search/jump to a place by name, instead of only manual pan/tap — faster to reach a specific address or landmark than scrolling the map by hand.

- [ ] **T94** 🌱 ⭐⭐ - **History detail screen: add the "view photo full-screen while listening" toggle**
  - **Added**: 2026-08-19
  - **Found via real-device testing**: `player_screen.dart` has a toggle (`_photoMode`, the `Icons.image_outlined`/`Icons.article_outlined` icon) to show the plain photo instead of the script overlay while listening — `history_screen.dart`'s `HistoryDetailScreen` (replaying a past entry) has no equivalent, even though it plays audio the same way. Feature-parity gap between the two playback screens.

- [ ] **T84** 🌱 ⭐⭐⭐⭐⭐ - **Play Store publication**
  - **Added**: 2026-08-15
  - **Already in place** (good starting point): working release signing (T79), `allowBackup=false` (T80), API key protected by allowlist (T81), secure key storage (T10), "AI-generated content" disclaimer, now localized and shown on the player screen itself, not just buried in a detail sub-screen (T72), stable `applicationId` `io.nohzoh.audiolens` (T63), a real custom app icon (headphone/soundwave design, `android/app/src/main/res/mipmap-*/ic_launcher.png` — the "missing icon" note below was stale, corrected 2026-08-18), English localization alongside French (T67)
  - **Updated (2026-08-18)**: CI now also builds a `.aab` (`Build App Bundle (release)` step, right after the existing APK build, reusing the same signing) and both the APK and AAB get a strictly increasing `versionCode` via `--build-number=${{ github.run_number }}` — the two "technical" items below are done
  - **Updated (2026-08-19)**: Privacy policy published (`PRIVACY.md`, repo root, rendered by GitHub — no separate hosting needed) — that item below is done. Google Play developer account **created (2026-08-19)** — the hard blocker is cleared, remaining items below are now actionable.
  - **Non-technical decisions/steps to handle first** — still blocking, nothing further to automate until these exist:
    - ~~Create a Google Play developer account~~ — **done 2026-08-19**
    - Play Console **"Data safety" form**: precisely declare what data is collected/shared (photo, GPS, script) and with whom (Google Gemini)
    - **Sensitive permissions declaration** — justification required by Google, location is especially scrutinized. Now also covers `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_DATA_SYNC`/`POST_NOTIFICATIONS` (T85), not just `ACCESS_FINE_LOCATION`/`CAMERA` as originally noted
    - ~~Check whether Play policies on generative AI apps require additional disclosures~~ — **checked 2026-08-19**: disclosure wording/placement isn't prescriptive (our T72 disclaimer on the player screen already satisfies the "reasonably understood" bar), but the policy does require an in-app content-reporting mechanism — split out as **T91** below
  - **To do, technical**:
    - **Store listing assets**: short/long description, category, feature graphic, screenshots — draft short/long description ready (see conversation 2026-08-19), needs review + a feature graphic + real device screenshots
    - **Automate the upload** to Play Console from CI (e.g. `r0adkll/upload-google-play` action, service account key as a secret) — only once the developer account exists
  - **Recommendation**: don't treat this as a single task — the non-technical steps (account, privacy policy, data safety) are blocking and must happen before any CI automation

- [ ] **T91** 🌱 ⭐⭐ - **In-app AI content reporting/flagging**
  - **Added**: 2026-08-19
  - **Context**: Google Play's AI-Generated Content policy requires generative-AI apps to have an in-app way for users to report/flag offensive or problematic AI output "without needing to exit the app" (found while researching T84 — [policy source](https://support.google.com/googleplay/android-developer/answer/13985936)). AudioLens currently has no such mechanism anywhere (player screen, history detail).
  - **User's concern**: a "real" reporting feature sounds like it needs a backend to receive/store reports, which doesn't exist today (AudioLens is 100% client + third-party APIs, no server component) and the user doesn't want to build one for this.
  - **Backend-free option worth considering**: a "Signaler ce contenu" action that opens a pre-filled `mailto:` (or similar) to the developer contact address with the script text attached — arguably satisfies the policy's wording without any server. Whether Google's review actually accepts an email-based flow (vs. requiring something that stays fully in-app) isn't confirmed by the policy text found so far — worth a closer look or a support inquiry before building it.
  - Not blocking initial submission investigation, but likely needed before/around actual submission for review.

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
