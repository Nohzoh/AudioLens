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
    - ~~Skip forward/back by X seconds (podcast-style), instead of just play/pause~~ — done 2026-08-21, bundled with T118 (see CHANGELOG.md)
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
