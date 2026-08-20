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

- [ ] **T122** 📈 ⭐ - **History detail's "Générer l'audio"/play button floats awkwardly in photo mode**
  - **Added**: 2026-08-20
  - **Source**: user, real device screenshot (`history_screen.dart`'s photo-mode toggle).
  - **Finding**: entering photo mode (the image_outlined/article_outlined icon in the top bar) is meant to keep just the play/generate button visible over the photo (T94, deliberate — matches `player_screen.dart`'s intent of keeping playback controllable). But the implementation differs from `player_screen.dart`: there, the play/pause control lives as a small icon in the top bar, always naturally positioned; here, it's a full-width `FilledButton` at the end of a scrollable `Column` whose other children (title/date/actions/script) are hidden via `if (!_photoMode)` — with that content gone, the button collapses to sit high up over the middle of the photo instead of anchored at the bottom, looking like a stray/leftover element rather than an intentional control.
  - **Fix**: anchor the button to the bottom of the screen regardless of photo mode (e.g. move it outside the conditionally-shrinking scroll content, similar in spirit to how the top bar icons stay fixed), rather than letting its position depend on how much other content is currently hidden.

- [ ] **T104** 📈 ⭐⭐ - **`HistoryService._copyImageToPermanentStorage` filename collision on same-millisecond entries**
  - **Added**: 2026-08-19
  - **Source**: found while building T95 (`purgeEntriesOlderThan` test failed until a 2ms delay was added between two `addPendingEntry` calls) — deliberately left unfixed at the time and logged here for the full audit, per the CHANGELOG entry for T95.
  - **Root cause**: destination filenames are derived from `DateTime.now().millisecondsSinceEpoch` alone — two entries created within the same millisecond (e.g. via the T97 share-intent path plus a near-simultaneous manual pick, or any future batch/automated import) collide on the same destination path, silently aliasing one entry's photo to another's. Deleting one such entry then deletes the file the other still references.
  - **Fix**: use a collision-proof name (a monotonic counter, a UUID, or the DB row id once known) instead of a raw timestamp.

- [ ] **T105** 📈 ⭐⭐⭐ - **Zero widget-level test coverage across the whole app**
  - **Added**: 2026-08-19
  - **Source**: full-project security/tech-debt audit — `grep -rl testWidgets test/` returns nothing; all 172 tests are `test()` (service/unit level), none are `testWidgets()`.
  - **Why it matters now specifically**: recent UI-only refactors (T94/T96's history detail top bar, T97's `home_screen.dart` gallery-pick/share-handler consolidation) shipped with no automated protection against a layout regression, a broken tap target, or a dropped callback wiring — only manual/emulator spot-checks caught issues in this session.
  - **Relates to**: T37 (the existing vague "add a test coverage baseline" backlog item) — this is the concrete version of it. Suggested starting point: the screens that changed most recently and have the most interactive surface (`home_screen.dart`, `history_screen.dart`).

- [ ] **T106** 📈 ⭐ - **NDK version pinned below what 11 plugins declare they need**
  - **Added**: 2026-08-19
  - **Source**: real local release build during T98 — Flutter's own build output warns that `flutter_local_notifications`, `flutter_plugin_android_lifecycle`, `flutter_secure_storage`, `flutter_tts`, `gal`, `image_picker_android`, `jni`, `jni_flutter`, `shared_preferences_android`, `sqflite_android`, and `url_launcher_android` all declare a dependency on NDK `28.2.13676358`, while both `scripts/build_android_local.sh` and `.github/workflows/build-android.yml` pin NDK `27.0.12077973` (T83).
  - **Current impact**: a warning only, build still succeeds (NDK is backward compatible per Flutter's own message) — but this is exactly the kind of drift that turns into a hard failure on a future Flutter/AGP bump.
  - **Fix**: bump the pinned NDK version in both build scripts together (they must stay in sync, per the repo's own convention), and update the CI NDK cache key (`android/app/build-android.yml`'s `Cache Android NDK` step, currently keyed on the version string) to match.

- [ ] **T113** 📈 ⭐⭐ - **Image bytes fully loaded in memory with no size cap, twice (EXIF read + Gemini upload)**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT), cross-checked against the code — confirmed real.
  - **Finding**: `ExifLocationService` reads the complete image file into memory to parse EXIF, and the Gemini API upload path separately reads the full file and base64-encodes it (~33% size overhead). A modern phone photo can be 10-20MB; on a low-end device this is real memory/GC pressure, and there's no upfront size/dimension cap or rejection of oversized files anywhere in the pipeline.
  - **Fix**: downscale/compress the image once right after capture/pick (before EXIF read and before upload), and reject or warn on implausibly large files. `RemoteConfig` already has unused `imageMaxWidth`/`imageQuality` fields that look intended for exactly this.

- [ ] **T116** 📈 ⭐ - **No free-disk-space check before writing photo/audio/database**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: nothing in the photo copy, WAV write, or SQLite write paths checks available storage first. On a full device, these can fail partway through, potentially leaving a corrupt/partial file or an inconsistent history entry.
  - **Fix**: a `checkFreeSpace()` guard before the write paths in `HistoryService`, surfacing a clear user-facing error ("not enough storage to generate audio") instead of whatever raw I/O exception would otherwise bubble up.

- [ ] **T117** 📈 ⭐⭐ - **AI-generated script has no length/sanity validation beyond "title and script are non-empty"**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT), scoped down from its broader "semantic/factual validator" proposal (see the audit comparison note in the same conversation — the full validator is a bigger, more speculative undertaking not queued here).
  - **Finding**: `GeminiApiService`'s response validation checks that `title`/`script` are present and cleans the text, but doesn't cap script length or otherwise sanity-check the output. A model returning an excessively long script would sail through, degrading TTS cost/latency and UX.
  - **Fix**: a simple length cap (reject/truncate/regenerate) on the parsed script before it reaches history/TTS.

---

## 🌱 Low impact / Long term
*Backlog for future improvements*

- [ ] **T92** 🌱 ⭐⭐ - **Map picker: lock north-up orientation + add a place search field**
  - **Added**: 2026-08-19
  - **Found via real-device testing**: on `map_picker_screen.dart` (shown when a gallery photo has no EXIF GPS, T87), the map currently rotates to follow device heading instead of staying fixed with north up — disorienting when picking a precise spot.
  - Also requested: a text field to search/jump to a place by name, instead of only manual pan/tap — faster to reach a specific address or landmark than scrolling the map by hand.

- [ ] **T84** 🌱 ⭐⭐⭐⭐⭐ - **Play Store publication**
  - **Added**: 2026-08-15
  - **Already in place** (good starting point): working release signing (T79), `allowBackup=false` (T80), API key protected by allowlist (T81), secure key storage (T10), "AI-generated content" disclaimer, now localized and shown on the player screen itself, not just buried in a detail sub-screen (T72), stable `applicationId` `io.nohzoh.audiolens` (T63), a real custom app icon (headphone/soundwave design, `android/app/src/main/res/mipmap-*/ic_launcher.png` — the "missing icon" note below was stale, corrected 2026-08-18), English localization alongside French (T67)
  - **Updated (2026-08-18)**: CI now also builds a `.aab` (`Build App Bundle (release)` step, right after the existing APK build, reusing the same signing) and both the APK and AAB get a strictly increasing `versionCode` via `--build-number=${{ github.run_number }}` — the two "technical" items below are done
  - **Updated (2026-08-19)**: Privacy policy published (`PRIVACY.md`, repo root, rendered by GitHub — no separate hosting needed) — that item below is done. Google Play developer account **created (2026-08-19)** — the hard blocker is cleared, remaining items below are now actionable.
  - **Non-technical decisions/steps to handle first** — still blocking, nothing further to automate until these exist:
    - ~~Create a Google Play developer account~~ — **done 2026-08-19**
    - Play Console **"Data safety" form**: precisely declare what data is collected/shared (photo, GPS, script) and with whom (Google Gemini)
    - **Sensitive permissions declaration** — justification required by Google, location is especially scrutinized. Now also covers `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_DATA_SYNC`/`POST_NOTIFICATIONS` (T85), not just `ACCESS_FINE_LOCATION`/`CAMERA` as originally noted
    - ~~Check whether Play policies on generative AI apps require additional disclosures~~ — **checked 2026-08-19**: disclosure wording/placement isn't prescriptive (our T72 disclaimer on the player screen already satisfies the "reasonably understood" bar), but the policy does require an in-app content-reporting mechanism — split out as T91, **done 2026-08-19**
  - **To do, technical**:
    - **Store listing assets**: short/long description, category, feature graphic, screenshots — draft short/long description ready (see conversation 2026-08-19), needs review + a feature graphic + real device screenshots
    - **Automate the upload** to Play Console from CI (e.g. `r0adkll/upload-google-play` action, service account key as a secret) — only once the developer account exists
  - **Recommendation**: don't treat this as a single task — the non-technical steps (account, privacy policy, data safety) are blocking and must happen before any CI automation

- [ ] **T77** 🌱 ⭐⭐⭐⭐⭐ - **iOS port** — get AudioLens running on iPhone
  - **Added**: 2026-08-15
  - **Context**: 100% Android project today, `ios/` doesn't even exist yet — will need to generate the scaffold (`flutter create --platforms=ios .`)
  - **Blockers to resolve before starting**:
    - **Gemini Nano has no iOS equivalent** (`GeminiNanoPlugin.kt` relies on the Android AICore API) — no equivalent native solution identified. Decision needed: disable local mode on iOS (cloud only), or replace it with another on-device model?
    - **Apple developer account** ($99/year) needed to sign/distribute (TestFlight or sideload), unlike the current Android APK distributed directly from GitHub Actions
    - ~~iOS support for `sherpa_onnx` (local Piper) needs checking~~ — **stale, 2026-08-19**: T89 replaced Piper/`sherpa_onnx` with the native platform TTS engine app-wide, so this isn't a blocker on any platform anymore
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

- [ ] **T107** 🌱 ⭐ - **`ShareIntentService` (T97) has no dedicated test**
  - **Added**: 2026-08-19
  - **Source**: full-project security/tech-debt audit — every other service under `lib/services/` has a matching `test/*_test.dart`; `share_intent_service.dart` (added in T97) is the one exception.
  - **Fix**: mock the `MethodChannel`/`EventChannel` the way other platform-channel bridges in this test suite already do (e.g. `native_tts_service_test.dart`) and cover `getInitialSharedImage()`'s null/error/success paths plus `sharedImageStream`'s event mapping.

- [ ] **T108** 🌱 ⭐ - **Stale comments/references left over from removed dependencies**
  - **Added**: 2026-08-19
  - **Source**: full-project security/tech-debt audit.
  - **Found**: (1) `.github/workflows/build-android.yml:264`'s ABI-restriction comment still says "sherpa_onnx has real native code per ABI to compile/link/package" — `sherpa_onnx` was fully removed by T89; the ABI restriction itself is still correct (other native deps still need it) but the justification text is wrong. (2) `AudioPlayerPlugin.kt`'s comment on `pendingPlayResult` says "since MediaPipe.stop() alone never completes it" — should say `MediaPlayer.stop()` (the actual class used in that file); likely a leftover from when MediaPipe was still part of this codebase (removed T82).
  - **Fix**: correct both comments. Purely cosmetic — no behavior change.

- [ ] **T109** 🌱 ⭐ - **`latlong2` trailing its latest major version**
  - **Added**: 2026-08-19
  - **Updated (2026-08-20)**: `flutter_map`, `google_fonts`, and `flutter_lints` (the other three originally listed here) are done — bumped via Dependabot (PRs #90/#93/#94), each verified locally (analyze/test/build) before merging; `flutter_lints` 6.0.0 needed one small fix (`history_screen.dart`'s `_getTts` needed an explicit `dynamic` return type for the new `strict_top_level_inference` lint).
  - **Remaining**: `latlong2` (0.9.1 → 0.10.1) — Dependabot hasn't proposed this one yet. No known vulnerability, just version drift.

- [ ] **T110** 🌱 ⭐ - **Play Store listing icon doesn't render well in dark mode**
  - **Added**: 2026-08-19
  - **Source**: user, real device screenshot (Play Store app detail page, dark theme).
  - **Finding**: the launcher icon used for the Play Store listing looks off against the store's dark background — needs a visual check of the icon's edges/background against both light and dark Play Store themes, not just the home-screen launcher context it was originally designed for.
  - **Fix**: review/adjust the icon asset (or provide an adaptive-icon background suited to both themes) and re-check the listing in both Play Store display modes before the next store-listing update.

- [ ] **T111** 🌱 ⭐ - **`RemoteConfigService`'s cache is write-only — never actually used as a fallback**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT), verified against `lib/services/remote_config_service.dart`.
  - **Finding**: `load()` deletes any cached config first (line ~153), fetches remote, and — only on success — writes a fresh cache. On failure it falls straight to hardcoded defaults; the cache is never read back at all, so all the cache-writing code is currently dead weight that only costs a `SharedPreferences` write on every successful load for no benefit.
  - **Fix**: either make the network-failure path actually read the last good cached config before falling back to hardcoded defaults (real resilience gain: a user offline right after an intentional remote config change still gets it), or remove the cache read/write entirely if hardcoded defaults are judged good enough on their own — either is fine, just pick one instead of keeping the current write-only middle ground.

- [ ] **T112** 🌱 ⭐⭐⭐⭐ - **`AudioGuideService` concentrates most of the pipeline's responsibilities**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: `AudioGuideService` (~660 lines) owns state, AI provider selection, API key handling, config, location, AI calls, TTS, cancellation, the foreground service, notifications, progress, and error handling all at once. Not a crisis today, but every new AI/TTS provider or pipeline stage added so far has meant touching this one file in several places.
  - **Fix (if/when this becomes worth doing)**: extract pipeline stages (location → enrichment → AI → TTS → playback) behind small interfaces, keeping `AudioGuideService` as the UI-facing state adapter rather than the implementation of every stage. Not urgent — worth doing before adding a third AI/TTS provider, not necessarily before.

- [ ] **T114** 🌱 ⭐⭐⭐ - **Enrichment pipeline (geocoding/POI/Wikipedia) is fully sequential, with no caching**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: reverse geocoding (Nominatim), POI lookup (Overpass), and Wikipedia enrichment run one after another rather than in parallel, adding their latencies up instead of overlapping them; repeat visits to the same coordinates also re-fetch everything from scratch since there's no local geo cache.
  - **Fix**: run the independent lookups concurrently where they don't depend on each other's output, and consider a simple coordinates→result local cache with a TTL for repeat locations.

- [ ] **T115** 🌱 ⭐⭐ - **Analysis provenance isn't fully versioned in history**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: `HistoryEntry` already stores which AI/TTS model was used and whether fallback occurred — good — but not the prompt version, output schema version, or script style/language used for that specific analysis. As prompts evolve, an old history entry becomes hard to reproduce or reason about.
  - **Fix**: stamp a small prompt/schema version string alongside the existing `aiModel`/`ttsModel` fields when completing an entry.

- [ ] **T118** 🌱 ⭐⭐⭐⭐ - **Audio playback has no audio focus handling, lock-screen controls, or `MediaSession`**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: `AudioPlayerPlugin` uses a plain `MediaPlayer` — fine for the current use case, but it doesn't integrate with Android's audio focus (a phone call or another app's audio won't duck/pause it cleanly), doesn't expose lock-screen/notification transport controls, and has no explicit Bluetooth headset command handling.
  - **Fix**: migrate to a proper `MediaSession`-backed playback service if/when richer playback controls (T21) or background listening becomes a priority — bundle with T21 rather than doing it standalone.

- [ ] **T120** 🌱 ⭐⭐⭐⭐⭐ - **Analysis pipeline isn't resumable if the app process is killed mid-analysis**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT).
  - **Finding**: the T85 foreground service protects process priority while an analysis runs, but doesn't make the job itself durable — it doesn't execute the pipeline independently of the Flutter engine. If Android kills the process anyway (aggressive OEM battery management, low memory, forced update), the in-flight analysis is lost with no automatic resume; the user has to notice and manually retry from history.
  - **Fix**: a persistent job table (status/step/attempt/payload/last_error) that a resume check on app startup can pick up and retry — meaningfully bigger than a quick fix, so treat as a deliberate future project rather than an incremental patch. Not urgent at current usage scale (the failure mode is already visible and manually retryable via history), but worth doing before wider release if analysis loss reports start showing up.

- [ ] **T121** 🌱 ⭐⭐⭐ - **Time-to-first-audio: consider progressive/streaming enrichment instead of "compute everything, then play"**
  - **Added**: 2026-08-19
  - **Source**: external audit (ChatGPT) — product idea, not a bug.
  - **Idea**: today the full pipeline (GPS → geocoding → POI → Wikipedia → AI → TTS) completes before any audio plays. A "first sentence fast, rest streamed in" experience — start speaking as soon as there's enough context, keep enriching in the background — would make the wait feel much shorter without necessarily reducing total latency.
  - **Note**: this is a real UX bet worth discussing before committing effort — it changes the pipeline's shape (streaming AI/TTS output) rather than being a bolt-on, so effort is likely underestimated by the star rating above.

---

## 📝 To fill in as the project goes

- [ ] **T34** - Add **new improvement ideas** (issue tracker?)
- [ ] **T35** - **Prioritize tasks** by impact/effort (ROI table?)
- [ ] **T36** - **Track implementation progress** (Kanban board?)
- [ ] **T37** - Add a **test coverage baseline** and keep it up
