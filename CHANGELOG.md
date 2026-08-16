# Changelog - AudioLens

History of completed tasks and test feedback. Tasks in progress or to do
are in [`TODO.md`](TODO.md).

IDs (T01, T02...) form a single sequence shared with `TODO.md` — before
creating a new task, check the highest ID across both files
(`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`).

---

## ✅ Done

- [x] **T13** 🌱 ⭐⭐ - Allow **re-requesting an old failed analysis** from history
  - **Verified**: 2026-08-16 (already done, noticed during a task review)
  - **Finding**: already covered by T78 — `history_screen.dart`: `_HistoryCard.onTap` retries the analysis (`_retryAnalysis`) when the entry is `pending` or `failed`. No code written for this task, just a closure

- [x] **T69** 🌱 ⭐⭐ - **Document the architecture** and data flows
  - **Verified**: 2026-08-16 (PR #12)
  - **What was done**: `ARCHITECTURE.md` — main pipeline diagram (photo → location → AI → TTS → audio, including the deferred capture T78 and script-only T16 branches), location resolution diagram (EXIF/GPS → reverse geocoding → POI → Wikipedia), persistence table, native channels table, screens → services diagram. Written after T74/T76/T78/T16 to reflect the actual pipeline, not its shape before those overhauls. `README.md` now links to this file instead of duplicating it

- [x] **T76** 📈 ⭐⭐⭐⭐ - **Chunk the script** to start audio playback faster
  - **Verified**: 2026-08-16 (PR #11, commit `4c8dd93`)
  - **Context**: ~30s (sometimes more) of waiting between the text appearing and audio playback starting — `GeminiTtsService.speak()` synthesized the whole script in a single blocking HTTP call
  - **What was done**:
    - `lib/utils/text_chunker.dart` (new): splits at sentence boundaries, short first chunk (fast start), larger following chunks (fewer network round-trips)
    - `GeminiTtsService`: synthesis and playback separated (`synthesizeToFile`/`playFile`), existing `speak()` unchanged; `concatenateWavFiles` (new) so the chunked result still gets cached like a regular synthesis
    - `TtsOrchestrator.speakChunked()`: synthesizes chunk N+1 while chunk N plays; on failure, falls back to Piper for the whole script (1st chunk failure) or just the remaining text (later failure) — no repeat and no voice change mid-narration. `onChunkStart(index, total)` drives real chunk N/M progress instead of the indeterminate spinner
    - `CancelToken.onCancel` (new, a `Future` completed by `cancel()`) so the playback loop can race against cancellation instead of polling `isCancelled`
  - **Real bugs found while building this**:
    - `AudioPlayerPlugin.kt`: `stop()` never resolved an in-flight `playWav` call — would have hung cancellation indefinitely mid-chunk; only the new chunked path actually awaits `playWav`. Fixed (tracks the pending `Result`, also resolved by `stop`)
    - A synthesis error could surface as an unhandled Zone error despite a `try/catch` further down — Dart flags a rejected `Future` as unhandled if no listener is attached at the moment of rejection. Fixed by attaching `.then(onError:)` immediately when the `Future` is created
  - **Actually verified**: local Android build (the native Kotlin file is modified)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 78/78 (13 new: `text_chunker_test.dart`, `tts_chunking_test.dart`)

- [x] **T78** 🌱 ⭐⭐⭐⭐ - **Deferred capture**: photo + GPS now, analysis (cloud) later
  - **Verified**: 2026-08-16 (PR #9, commit `33c0673`)
  - **Context**: user request — save mobile data without falling back to local models (lower quality): capture photo + position right away, run the cloud analysis later (e.g. once on wifi)
  - **What was done**:
    - `AnalysisStatus.captured` (new): photo + raw GPS saved, analysis not started — no DB migration needed (`status` was already TEXT, GPS columns already existed)
    - `LocationService.getCurrentRawCoordinates()`: GPS fix without reverse geocoding — truly offline capture (the GPS fix itself doesn't need network; `getCurrentLocation()` previously always coupled the fix to a Nominatim call)
    - `LocationContextResolver` split into coordinate resolution (`resolve()` from a photo, or `resolveFromCoordinates()` from already-known coordinates) + shared enrichment (`_enrich`: reverse geocoding + POI + Wikipedia) — enrichment now runs when "run analysis" is triggered, using the coordinates captured at that time, not the device's current position
    - `home_screen.dart`: "Capture without analyzing" option; `history_screen.dart`: captured entries now show a visual status and trigger the analysis on tap using the stored coordinates (this screen previously handled no pending/failed/captured tap at all — only the `home_screen.dart` grid did; both are now consistent)
    - `lib/utils/analysis_runner.dart` (new): the "analyze + persist to history" sequence extracted and shared between the two screens
  - **Bonus**: `LocationService` had no HTTP client injection (unlike every other network service in the project) — added, needed to verify this change with a real test instead of just inspection
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 65/65 (3 new: `deferred_capture_test.dart`)
  - **T20 removed (2026-08-16)**: "Improve the offline experience" (resume/cache + available/unavailable feature badge) had become obsolete — covered by the above (offline deferred capture, per-entry visual status)

- [x] **T16** 🌱 ⭐⭐⭐ - Add a **no-TTS mode**, with **on-demand audio generation** afterwards
  - **Verified**: 2026-08-15 (PR #7, commit `896bb2b`)
  - **Context**: user request — a setting to disable automatic audio generation after analysis, with the option to request audio synthesis later from a "script only" history entry
  - **What was done**:
    - `SettingsService.autoGenerateAudio` (default `true`), toggle in settings modeled on `showKofiButton`
    - `AudioGuideService.analyzeAndPlay(imageFile, generateAudio: false)` stops after the AI analysis, new `GuideState.scriptReady` state instead of `speaking` — no DB migration needed, `HistoryEntry.audioPath` was already nullable
    - `AudioGuideService.generateAudioForScript()` (new): re-runs only the TTS step (`TtsOrchestrator`, so cloud → Piper fallback still applies) on an already-known script, without redoing GPS/Wikipedia/AI
    - `history_screen.dart`: "Script only" indicator on entries with no audio, "Generate audio" button that now persists the result via `HistoryService.saveAudioPath` (the old behavior — on-the-fly generation with no save and no fallback — was replaced)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 62/62 (7 new: `script_only_mode_test.dart`)

- [x] **T74** 📈 ⭐⭐⭐ - Improve **place and history detection**
  - **Verified**: 2026-08-15 (PR #5, commit `3592327`)
  - **Context**: real-world test (Matène bowling alley, 2026-08-12) — the app never mentioned that *Les Tontons flingueurs* was filmed there: the place had no geolocated Wikipedia article within the 200 m radius, and the business name (POI) was never fetched
  - **What was done**:
    - `PoiService` (new): Overpass API search for nearby tagged POIs (leisure/tourism/historic/amenity), picks the closest by Haversine distance
    - `WikipediaService.searchByName` (new): full-text search by name + city, merged with the existing geosearch (`WikipediaService.merge`), fr → en fallback if French finds nothing
    - `gemini_api_service.dart` prompt: explicitly nudges the model to use the identified place/address to pin down the real location and look for notable facts (filmings, events, notable people) instead of only describing what's visible
    - **Bug fixed along the way**: `RemoteConfigService`'s `wikipedia_radius_meters`/`max_results`/`extract_chars` were fetched but never actually passed to `WikipediaService.searchNearby` (the call used its own defaults) — wired up; default radius raised from 200 m to 500 m (raising it via `config.json` previously had no effect, since the value was never read)
  - **Note**: `location_service.dart`/`audio_guide_service.dart` untouched — the original target predated the T06 refactor; a dedicated `PoiService` fits this architecture better, and no new persisted/displayed field was needed to fix the actual bug (the AI never mentioned the place)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 55/55 (11 new: `poi_service_test.dart`, `wikipedia_service_test.dart`)

- [x] **T79** 🔥 ⭐⭐ - CI ships a **debug APK**, not release
  - **Verified**: 2026-08-15 (commits `4011b5e`, `9d9ff11`, `88c196d` — green CI run [31897372162](https://github.com/Nohzoh/audio-guide/actions/runs/31897372162))
  - **What was done**: `flutter build apk --release` (instead of `--debug`); CI check that the final APK isn't `debuggable` (via `aapt dump badging`)
  - **Detours along the way**:
    - R8/minification (enabled by default in release) broke the build on missing classes (`javax.lang.model.*`) coming from a shaded dependency pulled in by dead MediaPipe/genai deps (see T82) — minification explicitly disabled in `scripts/patch_signing.py` pending their removal
    - The added anti-debuggable check actually checked nothing: `aapt` isn't on the CI runner's `PATH`, so the `grep` always matched an empty result and reported "not debuggable" regardless of the truth — fixed by locating the binary under `$ANDROID_HOME/build-tools`
  - **Actually verified**: the final CI run shows a working `aapt dump badging` (package/version/sdkVersion displayed) and confirms the absence of the `application-debuggable` flag

- [x] **T80** ⚡ ⭐⭐ - `allowBackup` forced to `true` in CI, with a likely-broken `backupAgent` class
  - **Verified**: 2026-08-15 (commit `4011b5e`)
  - **What was done**: the 4 chained `sed` commands (with a buggy `backupAgent` and a silent `|| true` fallback) replaced with a single explicit `android:allowBackup="false"` patch — decision: no automatic backup until the history (GPS, photos) has dedicated exclusion rules. Replicated in `scripts/build_android_local.sh` for CI/local consistency

- [x] **T81** ⚡ ⭐⭐⭐ - `RemoteConfigService` could redirect the API key to an arbitrary URL, unvalidated
  - **Verified**: 2026-08-15 (commit `4011b5e`)
  - **What was done**: `RemoteConfigService.isAllowedApiUrl()` — an allowlist (`generativelanguage.googleapis.com`) checked before using a `gemini_api_url` received from the remote config, otherwise falls back to the default value. 4 tests added (`remote_config_service_test.dart`, this service's first test)

- [x] **T82** 📈 ⭐⭐ - Follow-up cleanup after T06 (remaining dead code)
  - **Verified**: 2026-08-15 (PR #3, commit `0b14c3b`)
  - **What was done**: `MediaPipePlugin.kt` and its registration in `MainActivity.kt` removed, `tasks-genai` Gradle dependency removed (`genai-prompt`, used by `GeminiNanoPlugin.kt`, kept); unused `google_generative_ai` Dart dependency removed from `pubspec.yaml`; dead conditional in `gemini_api_service.dart` removed rather than implemented (the regex — any line starting lowercase and ending with a period — was too broad and risked cutting legitimate French narration, with no test to catch a regression)
  - **Bonus found while validating locally**: the `allowBackup` patch (T80) wasn't idempotent — re-running it on an already-patched manifest (without a fresh bootstrap) duplicated the attribute and broke the manifest merge. Fixed in both scripts (CI + local) with the same guard pattern as the permissions/FileProvider blocks
  - **Actually verified**: a truly cold local Android bootstrap (`git clean -X` on `android/` — without touching tracked files), successful debug build with no `MediaPipePlugin`. `flutter analyze` → 0 issues, `flutter test` → 44/44

- [x] **T02** - Improve **network error handling** and local fallback
- [x] **T03** - Prevent **concurrent analyses** and properly handle retries/cancellations
- [x] **T04** - Check and fix the **geolocation logic** on a new analysis after a failure
- [x] **T05** - Show a **clear user message** when voice enhancement fails (e.g. HTTP 429)
  - **Verified**: 2026-08-02
- [x] **T31** - Introduce explicit **business error types**
- [x] **T32** - Add **basic test coverage** on critical services
- [x] **T33** - Check the project's **license** and add/clarify the license file
- [x] **T39** 🔥 ⭐⭐ - Fix `flutter analyze` blocking errors
  - **Verified**: 2026-08-02 (via T39b)
- [x] **T40** 🔥 ⭐⭐ - Fix onboarding to talk about **Gemini API** instead of Anthropic
  - **Verified**: Included in T60 (commit `0f13e76`)
- [x] **T39b** 🔥 ⭐⭐ - Fix **all `flutter analyze` errors**
  - **Verified**: Commit `c37a3f1`
- [x] **T60** 🔥 ⭐ - Remove all **Anthropic/OpenAI** code and references
  - **Verified**: Commit `0f13e76`
- [x] **T61** ⚡ ⭐⭐⭐ - Align **cloud providers** with the actual implementation
  - **Verified**: Included in T60 (commit `0f13e76`)
- [x] **T62** ⚡ ⭐⭐⭐⭐ - **Finish the local models** or remove unused screens
  - **Verified**: Commit `c37a3f1`
- [x] **T38** 🌱 ⭐ - Add a **Ko-fi button** to accept voluntary support
  - **Verified**: Commit `83a790e` (reusable widget, integrated on every page, toggle in settings)
- [x] **T42** 🔥 ⭐⭐⭐ - Add a **full Android build** check and clarify the bootstrap's role in GitHub Actions
  - **Verified**: Commit `82d877a`
- [x] **T01** 🔥 ⭐⭐⭐ - Fix the **phone freeze** when launching Piper + add a **cancel button**
  - **Related to**: T43 (interruptible cancellation)
  - **Verified**: Commit `37f4ccd` (cancel button + cancelling state + timeout)
  - **Note**: Cancel button works during synthesis. Residual freeze needs T43.
- [x] **T43** ⚡ ⭐⭐⭐ - Make cancellations **actually interruptible** (HTTP calls, long pipeline steps)
  - **Related to**: T01 (Piper freeze)
  - **Verified**: Commit `4a9b211` (CancelToken system, checks before each step, wired into TTS services)
  - **Note**: Cancellation based on checks before each step. Native HTTP not supported (needs the dio package).
- [x] **T63** ⚡ ⭐ - **Unify the project name** as AudioLens
  - **Verified**: Commit `6afd7b9` (pubspec, README, AGENTS, workflow) + full Android package renaming (Kotlin files, channels, namespace)
  - **applicationId changed to `io.nohzoh.audiolens` (2026-08-16)**: `com.audiolens.audiolens` implied a non-existent commercial entity/organization; final prefix choice (`io.`, personal rather than tied to a hosting platform like `io.github.*`) discussed with the user before the Play Store publication (T84), the last moment this change is still free — `applicationId` becomes immutable after the first publication
- [x] **T64** ⚡ ⭐⭐ - Clean up **untracked files** and .gitignore
  - **Verified**: Commit `2e3d404` (untracked files cleanup)
- [x] **T65** ⚡ ⭐⭐ - Clean up all **unused imports** and dead variables
  - **Verified**: Commit `e176b62` (7 files cleaned up, 0 warnings)
- [x] **T41** ⚡ ⭐ - Sync the **README** with the current product
  - **Content to update**: Gemini Nano/API, Gemini/Piper TTS, Android status, architecture
  - **Verified**: 2026-08-08 (README rewritten: EXIF/GPS → Wikipedia → AI → TTS pipeline, AI providers, TTS, platform, config)
- [x] **T66** ⚡ ⭐ - Replace all **.withOpacity()** with **.withValues()**
  - Files affected: `history_screen.dart`, `home_screen.dart`, `player_screen.dart`, `onboarding_screen.dart`, `settings_screen.dart`, widgets/*
  - **Verified**: 2026-08-08 (20 occurrences replaced across 7 files)
- [x] **T71** ⚡ ⭐ - Clean up **asset configuration** in pubspec.yaml
  - Remove duplicates (`assets/tts/` appeared twice)
  - Check that all assets actually exist
  - **Verified**: 2026-08-08 (duplicate removed, existence checked)
  - **Note**: `assets/images/google.png` referenced in `app_settings.dart` but missing (dead code, cleaned up in T06)
- [x] **T47** ⚡ ⭐⭐ - Add an **analysis detail sheet**
  - **Content**: Model used, fallback, GPS, Wikipedia, duration, source
  - **Depends on**: T46 (fallback tests, still to do)
  - **Verified**: 2026-08-08 (AI/TTS fallback indicator added to the "About" screen, persisted in `HistoryEntry` + DB migration v6, serialization tests covered)
- [x] **T46** ⚡ ⭐⭐⭐ - Add **AI/TTS/GPS fallback tests**
  - **Cases to cover**: Primary Gemini model → fallback, Gemini TTS → Piper, GPS denied
  - **Verified**: 2026-08-08 (15 new tests: Gemini model fallback via `MockClient`, TTS→Piper / Cloud→Nano / GPS-denied orchestration, EXIF GPS parsing)
  - **Note**: HTTP injection (`GeminiApiService(client:)`) and service injection (`AudioGuideService(ttsService:, geminiTtsService:, geminiApiService:, nanoService:)`) added, backward compatible, no new dependency

- [x] **T72** 📈 ⭐ - Add an **"AI-generated content" disclaimer** (EU AI Act transparency)
  - **Verified**: 2026-08-12 (`_AiGeneratedBanner` banner at the top of the "About this analysis" screen in `about_analysis_screen.dart`)
  - **Note**: Copy: "AI-generated content: this analysis's script and voice were automatically created by an artificial intelligence model."

- [x] **T73** 📈 ⭐ - Replace the **Ko-fi icon** (heart) with the **standard coffee cup**
  - **Verified**: 2026-08-12 (`Icons.favorite_border` → `Icons.local_cafe_outlined` in `lib/widgets/kofi_button.dart`)

- [x] **T10** 📈 ⭐⭐ - **Secure API key storage** with flutter_secure_storage
  - **Verified**: 2026-08-12 (new `lib/services/secure_key_storage.dart`: encrypted Android Keystore/iOS Keychain storage, one-shot migration from `SharedPreferences`, clean fallback; `settings_service.dart` + `audio_guide_service.dart` wired up; 4 migration tests added)
  - **Goal reached**: No plaintext key left in `SharedPreferences` (removed after migration)

- [x] **T06** 📈 ⭐⭐⭐⭐ - **Refactor the architecture** and clean up legacy code
  - **Merged from**: clarify the pipeline + clean up duplication (ex-T08)
  - **Verified**: 2026-08-15
  - **1st batch (2026-08-12)**: dead code removed (`app_settings.dart`, `cloud_provider_picker.dart`, `mode_card.dart`, `mediapipe_service.dart`, `image_utils.dart`), `aiModelAttempts` getter removed, User-Agent centralized in `network_config.dart`
  - **2nd batch (2026-08-15)**: `audio_guide_service.dart` (524 → 445 lines) split into 4 dedicated classes — `GuidePreferencesStore` (prefs/timing persistence), `GuideProgressEstimator` (progress simulation/estimation), `LocationContextResolver` (EXIF/real-time GPS + Wikipedia enrichment), `TtsOrchestrator` (Gemini TTS → Piper fallback) — plus a shared `utils/error_sanitizer.dart`
  - **Note**: the AI fallback (cloud → nano) stays in `audio_guide_service.dart` since it mutates the service's own `activeProvider` state — less cleanly isolable than the other steps
  - **Goal reached**: modular pipeline, separated responsibilities; `AudioGuideService` now only drives state transitions and notifies the UI

---

## 📊 Test feedback

- **2026-08-15 (T79/T80/T81 — CI security audit)**
  - ✅ **T79/T80/T81 verified**: signed, non-debuggable release build confirmed by a real CI run ([31897372162](https://github.com/Nohzoh/audio-guide/actions/runs/31897372162))
  - 🐛 **2 bugs found along the way, invisible without a real run**:
    - R8 (minification, enabled by default in release) broke the build on missing classes pulled in by dead MediaPipe/genai deps — explicitly disabled pending their removal (T82)
    - The added anti-debuggable check actually checked nothing: `aapt` was missing from the CI runner's `PATH`, `grep` always matched an empty result → always "✅ not debuggable" regardless of the actual result. Fixed by locating the binary under `$ANDROID_HOME/build-tools`
  - ⚙️ **Android environment installed locally** (Java 17 via `openjdk@17`, SDK/NDK via `android-commandlinetools`, `gnu-sed`) — `flutter doctor` green, variables persisted in `~/.zshrc`. Now allows reproducing CI builds locally without waiting for a GitHub Actions run
  - 🐛 **Bug found in `scripts/build_android_local.sh`**: all `sed -i` calls used GNU syntax, silently broken under macOS's BSD `sed` (`-i` with no argument swallows the next token as a backup suffix, then tries to interpret the target file path as a sed script). Fixed by forcing the use of `gsed`
  - ⚠️ **Minor incident**: an `rm -rf android` meant to force a clean bootstrap deleted git-tracked files (native Kotlin plugins) — restored immediately via `git checkout`, nothing lost
  - ✅ **T83 added**: leads to speed up the CI build (~6-8 min/run), identified while watching the runs

- **2026-08-15 (resumed after a break, T06 — 2nd batch)**
  - ✅ **T10 confirmed done**: the code existed but was never committed (interrupted due to running out of credits); committed as-is after verification (fully wired up, tests green)
  - ✅ **T06 done**: `audio_guide_service.dart` split into `GuidePreferencesStore`, `GuideProgressEstimator`, `LocationContextResolver`, `TtsOrchestrator` + shared `utils/error_sanitizer.dart` (524 → 445 lines)
  - ✅ **Final validation**: `flutter analyze` → 0 errors; `flutter test` → 40 tests passed (30 existing + 4 `guide_preferences_store_test.dart` + 6 `guide_progress_estimator_test.dart`)
  - ⚠️ **Worth noting**: commit GPG signing broken on this machine (gpg missing, no signing key found) → gpg installed (`brew install gnupg`), new key generated and added to GitHub, local repo config fixed (`user.name`/`user.email` had been left at the template's placeholder values)

- **2026-08-12 (T06 — 1st batch)**
  - ✅ **T06 (partial)**: dead code removed (`app_settings.dart`, `cloud_provider_picker.dart`, `mode_card.dart`, `mediapipe_service.dart`, `image_utils.dart`), `aiModelAttempts` getter removed, User-Agent centralized in `network_config.dart`
  - ✅ **Final validation**: `flutter test` → 30 tests passed, 2026-08-12
  - ⚠️ **T06 remaining**: AI/GPS/TTS pipeline modularization + extracting prefs persistence out of `audio_guide_service.dart`

- **2026-08-12 (T72 / T73 / T10)**
  - ✅ **T72 verified**: "AI-generated content" disclaimer added to the analysis sheet (AI Act)
  - ✅ **T73 verified**: Ko-fi icon replaced with the coffee cup (`Icons.local_cafe_outlined`)
  - ✅ **T10 verified**: Gemini API key stored via `flutter_secure_storage` (Keystore/Keychain), one-shot migration from SharedPreferences, degraded fallback if secure storage is unavailable
  - ✅ **Final validation**: `flutter test` → 30 tests passed (26 existing + 4 new `secure_key_storage_test.dart`), 2026-08-12
  - ⚠️ **Worth noting**: T74 (place detection) created following a real-world test at the Matène bowling alley; T75 (script style) created following an outside suggestion

- **2026-08-08 (T41 / T66 / T71 / T47 / T46)**
  - ✅ **T41 verified**: README synced with the current product (EXIF/GPS → Wikipedia → AI → TTS pipeline)
  - ✅ **T66 verified**: `.withOpacity()` → `.withValues()` (20 occurrences across 7 files)
  - ✅ **T71 verified**: `assets/tts/` duplicate removed, all declared assets exist
  - ✅ **T47 verified**: AI/TTS fallback indicator in the analysis sheet (persisted in DB v6)
  - ✅ **T46 verified**: AI/TTS/GPS fallback tests (15 tests, see the Done section)
  - ✅ **Final validation**: `flutter analyze` → 0 errors; `flutter test` → 26 tests passed (2026-08-08)
  - 🐛 **Bug fixed**: test imports still referenced `package:audio_guide/` after the rename to `audiolens` (T63) → `flutter test` failed to compile (6 files fixed)
  - ⚠️ **Worth noting**: `assets/images/google.png` referenced but missing (dead code, cleaned up in T06)
  - ⚠️ **Worth noting**: `test/widget_test.dart` (broken template, referenced a nonexistent `MyApp`) removed

- **2026-08-02**
  - ✅ **T05 verified**: Clear error message when voice enhancement fails.
  - ✅ **Build date verified**: Shown correctly in settings.
  - ⚠️ **T01 to finish**: No cancel button visible during Piper synthesis (processing too fast to reproduce the freeze). **Needs retesting** with the phone charging + active background apps.

- **2026-08-02 (T60/T39b/T61/T62)**
  - ✅ **T60 verified**: All Anthropic/OpenAI code removed (commit `0f13e76`)
  - ✅ **T61 verified**: Cloud providers aligned with the implementation (Gemini only)
  - ✅ **T62 verified**: Model download screens removed (commit `c37a3f1`)
  - ✅ **T39b verified**: `flutter analyze` → **0 errors** (commit `c37a3f1`)

- **2026-08-02 (T42)**
  - ✅ **T42 verified**: Bootstrap documented + APK check added (commit `82d877a`)

- **2026-08-02 (T63)**
  - ✅ **T63 verified**: Project name aligned on AudioLens (commit `6afd7b9`) + full Android package renaming (Kotlin files, MethodChannels, namespace, applicationId)

- **2026-08-02 (T65)**
  - ✅ **T65 verified**: Unused imports and variables cleaned up (commit `e176b62`)

- **2026-08-02 (T64)**
  - ✅ **T64 verified**: Untracked files + .gitignore cleanup (commit `2e3d404`)
