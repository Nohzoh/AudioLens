# Changelog - AudioLens

History of completed tasks and test feedback. Tasks in progress or to do
are in [`TODO.md`](TODO.md).

IDs (T01, T02...) form a single sequence shared with `TODO.md` — before
creating a new task, check the highest ID across both files
(`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`).

---

## ✅ Done

- [x] **T123** 🔥 ⭐⭐⭐ - **Sign `config.json` (Ed25519) so CI/repo write access alone can't push a trusted config change**
  - **Verified**: 2026-08-20
  - **Source**: comparison with an external audit (ChatGPT) — flagged the remote config's integrity as protected only by a host allowlist, not a signature. Discussed and refined into a specific threat model: `config.json` is fetched live at every app startup and applied immediately to every installed build, unlike a code change (which must go through CI, review, staged rollout) — it's the fastest path an attacker with repo/CI write access would have to affect real users.
  - **What was done**: `RemoteConfigService` now fetches `config.json.sig` alongside `config.json` and verifies it (Ed25519, `package:cryptography`) against a public key embedded in the service before applying anything — falls back to built-in defaults (same as a network failure) on any verification failure. New `scripts/sign_config.dart` (local-only signing tool) and `scripts/generate_config_signing_key.dart` (one-off/rotation keygen). **The private key never touches CI, GitHub secrets, or this repo** — generated locally, backed up to the developer's password manager, only ever used offline to produce `config.json.sig` before committing it alongside `config.json`. Documented in `AGENTS.md` under "Remote Config Signing".
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 176/176 (4 new: valid signature accepted, tampered body rejected, malformed signature rejected, empty signature rejected)

- [x] **T98** 📈 ⭐⭐⭐ - **Enable R8 minification/resource shrinking for release builds**
  - **Verified**: 2026-08-19 (PR #79)
  - **Source**: Play Console's "App optimization" score on the uploaded AAB — "Faible" (Low), R8 not enabled at all.
  - **What was done**: `isMinifyEnabled`/`isShrinkResources` flipped to `true` on the release `buildType` (`scripts/patch_signing.py`, the only place that writes it — `android/` isn't committed, see repo convention). The blocker that forced them off in the first place (T79 — R8 failing on a shaded autovalue/javapoet dependency pulled in transitively by `com.google.mediapipe:tasks-genai`) no longer applies: T82 dropped that dependency entirely (dead code, only used by the already-removed `MediaPipePlugin.kt`). New `android/app/proguard-rules.pro` (tracked, unlike the rest of `android/app/`) keeps ML Kit GenAI (`com.google.mlkit.**`, `com.google.android.gms.**`) and Gson's reflection-based (de)serialization, both used transitively by the Gemini Nano dependency. CI also now uploads the resulting `mapping.txt` as a build artifact and feeds it to the Play Store publish step (`r0adkll/upload-google-play`'s `mappingFile` input) so future crash reports can be de-obfuscated.
  - **Verification performed from this environment**: real signed release APK **and** AAB built locally end-to-end with R8 enabled (`isMinifyEnabled`/`isShrinkResources` true, same patch scripts as CI) — both succeed, `mapping.txt` is generated. Installed the release APK on an Android emulator and smoke-tested: cold start (no `FATAL EXCEPTION` in logcat), Settings screen (remote GitHub config fetch + JSON parsing renders correctly), the existing encrypted Gemini API key decrypts via `flutter_secure_storage`, the new T95 auto-purge toggle persists a `SharedPreferences` write/read across navigation, History screen opens an empty `sqflite` database with no error, and `flutter_tts` successfully dispatches to the system TTS engine.
  - **Not verified (needs the user's physical device)**: the actual Gemini Nano / ML Kit GenAI on-device inference path — AICore isn't available on the test emulator, so this specific reflection-heavy path (the main risk this task called out) couldn't be exercised here. Also not covered: Gemini API cloud analysis (needs a live network key + quota), Gemini/native TTS full audio generation and playback, camera capture, and share-target intent handling (T97). Please run a real device pass across at least: taking a photo → analysis (both AI engines) → audio generation (both TTS engines) → playback, before the next Play Store publish.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 172/172

- [x] **T97** 📈 ⭐⭐⭐ - **Register AudioLens as a share target for photos**
  - **Verified**: 2026-08-19 (PR #77)
  - **Source**: closed-testing tester feedback.
  - **What was done**: a second `<intent-filter>` (`ACTION_SEND`, `image/*`) on `MainActivity`, so AudioLens appears in Android's native "Share via..." sheet from other apps. New `SharePlugin.kt` bridges the shared image to Dart — a method channel for the cold-start case (app launched directly by the share) and an event channel for the warm-start case (`onNewIntent`, app already running — `launchMode="singleTop"` already in place). The content:// URI is copied to the app's cache dir since the rest of the pipeline expects a real file path. New `lib/services/share_intent_service.dart` on the Dart side; `home_screen.dart`'s gallery-pick logic (EXIF check → map picker fallback → pending entry → analysis) was factored into a shared `_processImageForAnalysis` used by both the picker and the new share handler, landing on Home with the photo already flowing through the same path as a gallery pick.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 169/169; real local build (`scripts/build_android_local.sh`) confirms the native Kotlin compiles. Functional verification of the actual OS share-sheet integration needs a real device — not possible from this environment.

- [x] **T95** 📈 ⭐⭐⭐ - **Optional auto-purge of history after N days**
  - **Verified**: 2026-08-19 (PR #78)
  - **Source**: UX feedback from a closed-testing tester (fast turnaround — first feedback within minutes of the invite).
  - **What was done**: a Settings toggle ("Purger automatiquement l'historique", off by default) + a day-count choice (7/14/30/90, default 30) shown once enabled. `HistoryService.purgeEntriesOlderThan(days)` reuses `deleteEntry`'s mechanics (photo/audio files + DB row) for each expired entry; run once per app startup in `main.dart`, only when the setting is on — no background scheduling infrastructure needed. Manual deletion (from the entry itself) stays the default and always available regardless of this setting.
  - **Bug found while testing this**: `HistoryService._copyImageToPermanentStorage` names files by millisecond timestamp — two entries created within the same millisecond collide on the same destination path. Not fixed here (out of T95's scope), logged for the full project audit.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 172/172

- [x] **T91** 🌱 ⭐⭐ - **In-app AI content reporting/flagging**
  - **Verified**: 2026-08-19 (PR #76)
  - **Context**: Google Play's AI-Generated Content policy requires generative-AI apps to have an in-app way for users to report/flag offensive or problematic AI output "without needing to exit the app". AudioLens had no such mechanism anywhere.
  - **What was done**: a "Signaler" action (flag icon, matching the existing Save/Copy action rows) on both `player_screen.dart` and `history_screen.dart`'s detail view — opens a confirmation dialog with an optional free-text reason, then composes a pre-filled `mailto:` to the developer contact address (script, AI model, date, reason) via `url_launcher`, with a snackbar fallback if no mail app is available. No backend — the user sees exactly what's sent before choosing to send it. New shared `lib/widgets/report_content_button.dart`, fully localized (FR/EN).
  - **Known residual risk**: whether Google's review accepts an email-handoff flow as satisfying "without needing to exit the app" isn't confirmed — noted at design time, to revisit if flagged during the production-access review.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 169/169

- [x] **T96** 📈 ⭐ - **History detail screen: top bar icons hard to see over bright photos**
  - **Verified**: 2026-08-19 (PR #74)
  - **Source**: closed-testing tester — didn't recognize the top-right delete icon as a trash icon over a bright-sky photo.
  - **Root cause**: the gradient overlay barely darkened the very top of the screen, and the delete icon's `Colors.redAccent` had weak contrast against light backgrounds specifically.
  - **What was done**: 3-stop vignette gradient (protects both the top bar and bottom text without hiding the photo's middle) plus a dedicated `_ScrimIconButton` — a subtle circular dark scrim behind every top-bar icon, independent of the gradient or photo content. Bundled with T94 since both touch the same top bar.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 168/168

- [x] **T94** 🌱 ⭐⭐ - **History detail screen: add the "view photo full-screen while listening" toggle**
  - **Verified**: 2026-08-19 (PR #74)
  - **What was done**: added the same `_photoMode` toggle `player_screen.dart` already has (icon in the top bar, `Icons.image_outlined`/`Icons.article_outlined`, reusing its `playerShowText`/`playerPhotoMode` l10n keys) — hides title/date/location/action buttons/script/upgrade button while photo mode is on, but keeps the play/generate button visible so playback stays controllable, matching the player screen's own behavior.

- [x] **T100** 📈 ⭐ - **Bump the pinned Kotlin version (deprecation warning in CI)**
  - **Verified**: 2026-08-19 (PR #73)
  - **Warning**: "Flutter support for your project's Kotlin version (2.2.10) will soon be dropped. Please upgrade your Kotlin version to a version of at least 2.2.20 soon" — seen in the first successful automated Play Store publish run's logs.
  - **Investigated first**: both build scripts pinned `"2.2.0"`, yet the build reported 2.2.10 — likely Gradle's default "highest version wins" dependency conflict resolution, since `kotlinx-coroutines-android`/`play-services` (added in the same patched file) can pull in a newer Kotlin stdlib transitively than the plugin version declared. Rather than chase the exact transitive culprit, pinned directly to the version Flutter actually wants (2.2.20) so it's compliant regardless of what Gradle resolves around it.
  - **What was done**: bumped the sed-patched Kotlin Gradle Plugin version from `2.2.0` to `2.2.20` in both `.github/workflows/build-android.yml` and `scripts/build_android_local.sh`.

- [x] **T101** 📈 ⭐ - **Migrate `upload-google-play`'s deprecated `track:` input to `tracks:`**
  - **Verified**: 2026-08-19 (PR #72)
  - **What was done**: `r0adkll/upload-google-play@v1`'s `track:` input (added earlier tonight) was already flagged as deprecated in its own logs — renamed to `tracks:` (same value format, plain string; comma-separated for multiple tracks per the action's docs).

- [x] **T99** 📈 ⭐ - **Rename the ambiguous "Modèle IA" label**
  - **Verified**: 2026-08-19 (PR #71)
  - **What was done**: renamed "Modèle IA"/"AI model" to "Modèle d'analyse"/"Analysis model" in all 3 places it appeared (player fallback banner, Settings config display, analysis detail debug screen) — it read as the only AI involved when TTS (Gemini TTS) is AI too.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 168/168

- [x] **T93** 📈 ⭐⭐ - **TTS model not persisted when Gemini TTS falls back to native with no cached audio**
  - **Verified**: 2026-08-19 (PR #70)
  - **Found via real-device testing**: with the daily Gemini API quota exhausted, an analysis still completed (script generated), TTS fell back to the native engine as expected — but revisiting the entry in History showed "Modèle TTS : Inconnu" and only a "Générer l'audio" button, as if nothing had been recorded at all.
  - **Root cause**: `saveAudioPath()` was the only place `ttsModel` got persisted, but it requires a real file to copy — native TTS legitimately never produces one, so the model used was silently dropped whenever there was nothing to cache.
  - **What was done**: added `HistoryService.saveTtsModel()` to persist just the model (and fallback flag) independently of any audio file, called from `analysis_runner.dart` when TTS genuinely ran (`GuideState.speaking`) but produced no cacheable path — guarded so a script-only entry (T16) or one deferred while backgrounded (T85), where TTS never ran, doesn't get a stale value carried over from a previous entry.
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 169/169

- **2026-08-18 (T84 prep, PR #55)**: two of T84's (Play Store publication) technical prerequisites, done ahead of the full task since they're small and self-contained
  - **AAB build**: CI now also builds `build/app/outputs/bundle/release/app-release.aab` via a new "Build App Bundle (release)" step right after the existing APK build, in the same job — reuses the already-bootstrapped/patched `android/` project and signing config rather than a separate job. The `.apk` build stays too, for direct-sideload testing (`adb install`)
  - **versionCode**: both the APK and AAB builds now pass `--build-number=${{ github.run_number }}`, giving every release a strictly increasing `versionCode` (Play Console rejects any upload whose versionCode isn't higher than the last one) without needing to hand-edit `pubspec.yaml`'s committed `0.1.0+1` per upload
  - **Verified**: real local build of both the debug APK (bootstrap) and a release AAB (`flutter build appbundle --release --build-number=999`, throwaway keystore) — confirmed a well-formed `.aab` (60.8MB, correct `BUNDLE-METADATA`/`base/manifest` structure)

- [x] **T67** 🌱 ⭐⭐⭐ - **Extract all static strings** for i18n
  - **Verified**: 2026-08-17 (PR #53)
  - **Scope decisions**: screens and widgets only (~159 strings across 8 files: `settings_screen.dart`, `history_screen.dart`, `player_screen.dart`, `home_screen.dart`, `logs_screen.dart`, `onboarding_screen.dart`, `map_picker_screen.dart`, `kofi_button.dart`) — service-layer error strings (`GuideError`/`Exception` messages) and two small error-formatting utilities (`user_message_utils.dart`, `build_info.dart`) stay French for now, a natural follow-up rather than part of this task. `about_analysis_screen.dart` (a dev/debug screen, already partly English/technical) left untranslated. `_ttsPreviewSample` (Settings' voice-test sentence) deliberately kept French-only and unextracted — the native TTS engine itself is hardcoded to `fr-FR` regardless of UI language, so an English sentence would be mispronounced
  - **Fallback locale**: initially planned as French (matching the app's source language), changed mid-implementation to **English** — reaches more non-French speakers for unsupported system locales. Ended up needing no custom `localeResolutionCallback` at all: `AppLocalizations.supportedLocales` is generated alphabetically (`[en, fr]`), and Flutter's own default resolution already falls back to `.first` (English) when the device locale doesn't match either
  - **What was done**: Flutter's official ARB + `flutter gen-l10n` codegen (`flutter_localizations` SDK package added, `generate: true`, new `l10n.yaml`, `lib/l10n/app_fr.arb`/`app_en.arb` — 125 keys, ICU placeholders for the ~10 dynamic strings like `Logs ({count})`). `intl` bumped `^0.19.0` → `^0.20.2` (pinned exactly by `flutter_localizations` from the SDK). The two `DateFormat(pattern, 'fr_FR')` call sites in `history_screen.dart` and `main.dart`'s single-locale `initializeDateFormatting` now follow the active `Localizations.localeOf(context)` / initialize both locales — otherwise dates would've stayed French-formatted in an English UI. Generated `app_localizations*.dart` files are gitignored (regenerated by `flutter pub get` via `generate: true`), only the `.arb` sources are versioned
  - **Bug found and fixed along the way**: none this time — but the extraction surfaced a design point worth documenting: proper nouns (`AudioLens`, `Gemini Nano`, `Gemini API`) and format hints (`AIza...`) were deliberately left as plain Dart literals rather than extracted, since translating a brand name to itself or a format example adds ARB noise for zero user-visible benefit
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 154/154 (unaffected — all existing tests are service-layer, not UI-string-dependent); real local Android build succeeded, confirming `flutter gen-l10n`'s codegen runs cleanly as part of the build; a grep sweep across all 9 touched files for any remaining accented-French string literals found only the deliberately-excluded `_ttsPreviewSample`
  - **Requires the user's device** to confirm the visual result: every screen renders correctly with no missed strings, and switching the phone's system language to English actually flips the UI

- [x] **T68** 🌱 ⭐⭐⭐ - **Extend test coverage** to untested services
  - **Verified**: 2026-08-17 (PR #49)
  - **Scope**: expanded beyond the original target list during an audit — `HistoryService`'s CRUD methods were still genuinely untested (only `HistoryEntry`'s serialization and the migration path had coverage), and two services born since T68 was last updated (`NativeTtsService`, `GeminiNanoService`, both T89-era) had **zero real coverage**: every test that touches them fakes them via a subclass overriding the method entirely, so their actual implementation never ran. Also closed smaller gaps in `SettingsService` (only `autoGenerateAudio` was tested) and `GuidePreferencesStore` (missing `ttsVoiceGender`/`playbackSpeed`, added in T89/T15)
  - **Bug found and fixed along the way**: writing a real CRUD test for `completeEntry` caught it silently dropping `analysisSource`, `analyzedAt`, and `wordCount` from the in-memory entry it hands back (the DB `update()` call saved them correctly, but the manual in-memory `HistoryEntry` reconstruction next to it had drifted out of sync as fields were added over time) — the "Analysis detail sheet" would show these blank/unknown for a freshly-completed entry until the app restarted and reloaded from DB. Fixed by adding the three missing fields to the reconstruction
  - **What was done**: `history_service_crud_test.dart` (new, real SQLite via `sqflite_common_ffi`, `path_provider`'s platform channel mocked directly) covers `addPendingEntry`, `addCapturedEntry`, `completeEntry`, `failEntry`, `saveAudioPath`, `deleteEntry`, including stale-file cleanup on both re-completion and deletion. `native_tts_service_test.dart` (new, mocks the raw `flutter_tts` platform channel) covers the T89 voice-availability safeguard, `frenchVoices()` filtering, speed application, lazy init, and `speakAndWaitForResult()`'s completion/error signaling (simulated via the reverse platform→Dart channel dispatch, synchronized by having the mocked `speak` call trigger the callback itself rather than racing it externally). `gemini_nano_service_test.dart` (new, mocks `audio_guide/gemini_nano`) covers lazy init, arg-building (locationContext/style only sent when non-null), title extraction/truncation, and PlatformException wrapping. `settings_service_test.dart` (new) and extensions to `guide_preferences_store_test.dart` close the remaining preference gaps
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 154/154 (34 new, up from 120); pure Dart change, no native/manifest edits, no local build needed

- [x] **T15** 🌱 ⭐ - Allow **configuring playback speed**
  - **Verified**: 2026-08-17 (PR #47)
  - **Scope decision**: applies to both TTS engines (native + Gemini TTS), not just native — Gemini TTS is the default engine when configured, so a speed setting that silently did nothing for it would be confusing. Settings-only persistent preference (0.75x/1x/1.25x/1.5x), no live in-player control, matching the TODO's ⭐ estimate
  - **What was done**: native TTS speed is a multiplier on the app's already-tuned baseline rate (`0.45` in `flutter_tts` units, applied fresh on every `speak()`/`speakAndWaitForResult()` call rather than cached, so a mid-session change takes effect immediately). Gemini TTS plays a pre-rendered WAV via `AudioPlayerPlugin.kt`'s `MediaPlayer`, which had no speed control at all — added `MediaPlayer.playbackParams = PlaybackParams().setSpeed(...)` (API 23+, this project's minSdk is 26) after `prepare()` and before `start()`; left pitch untouched, so `PlaybackParams`' default behavior time-stretches without the "chipmunk" pitch shift. The multiplier is threaded as a plain parameter (`speed`) through `TtsOrchestrator.speak()`/`speakChunked()` down to both engines and the native `playWav` MethodChannel call, sourced from a new persisted `AudioGuideService.playbackSpeed` (`GuidePreferencesStore.loadPlaybackSpeed`/`savePlaybackSpeed`) — not cached engine-side state, so there's no "did I remember to re-apply this everywhere the service gets re-instantiated" risk
  - **Settings UI**: new "Vitesse de lecture" section — a `Wrap` of 4 `ChoiceChip`s (0.75x/1x/1.25x/1.5x); the "Tester la voix" preview button now also plays at the configured speed
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 120/120 (3 new tests in `playback_speed_test.dart` confirming the speed reaches whichever engine actually plays); real local Android build succeeded (native `AudioPlayerPlugin.kt` change) — verifying the audio actually plays faster/slower and stays pitch-stable needs a physical device

- [x] **T75** 📈 ⭐⭐ - Add a **script style option** (merged with T48's tone variants)
  - **Verified**: 2026-08-17 (PR #46)
  - **Scope decision**: T75 and T48 both proposed a style/tone picker (T75: academic vs. storytelling; T48: child, expert, storytelling, concise) — merged into a single picker rather than building two overlapping ones. Chose 4 styles covering both tasks' examples without inventing new use cases (no "child" mode): **Immersif** (default, unchanged), **Académique**, **Anecdotique**, **Concis**
  - **Scope decision**: applies to both the cloud path (`GeminiApiService`) and the on-device fallback (`GeminiNanoService`/`GeminiNanoPlugin.kt`) — the latter needed new native Kotlin work (the prompt for Nano's 3-segment pipeline lives entirely in Kotlin, not Dart) rather than just the simpler cloud-only option
  - **What was done**: `AIService.analyzeImage()` gained an optional `style` parameter (`'immersive'` (default) / `'academic'` / `'anecdotal'` / `'concise'`), threaded from a new `SettingsService.scriptStyle` (persisted, defaults to `'immersive'`) through `analysis_runner.dart` → `AudioGuideService.analyzeAndPlay()` → both `GeminiApiService`/`GeminiNanoService`. `GeminiApiService._styleGuidance()` swaps the tone/structure instruction and word-count target (concise: 100-150 words vs. the default 300-400) in the single JSON prompt; `GeminiNanoPlugin.kt`'s three segment-prompt builders (`buildSeg1/2/3Prompt`) each gained a `style` parameter adjusting tone and sentence count. The default (`null`/`'immersive'`) case reuses the exact original prompt text verbatim in both, so the default experience is unchanged
  - **Settings UI**: new "Style du script" section (`settings_screen.dart`) — a `Wrap` of 4 `ChoiceChip`s (not a `SegmentedButton`, to avoid overflow risk with 4 labelled options on narrow screens, unlike the existing 2-option voice picker)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 117/117 (5 new tests in `script_style_test.dart` asserting the actual outgoing prompt text per style, via the `fake_dio_adapter` support helper); real local Android build succeeded (native Kotlin change)

- [x] **T45** 📈 ⭐⭐ - Define a **retention policy** for images, WAV files, caches, temp files
  - **Verified**: 2026-08-17 (PR #45)
  - **Scope decision**: split into "fix the actual leak" vs. "auto-expire old history entries" — chose the former only. Auto-purging saved guides after N days/entries is a real product decision with UX risk (a user could lose a guide they wanted to keep), not something to decide unilaterally; not pursued here
  - **Root cause**: `HistoryService._copyImageToPermanentStorage()` copies the `image_picker` temp capture to permanent storage but never deletes the source — every photo taken left an orphaned temp file behind indefinitely, with no bound
  - **What was done**: the temp file can only be deleted once nothing still reads from it — `_captureOnly()` (T78's offline-capture flow) deletes it right after the permanent copy, since nothing else touches it afterward. The main analyze-now flow is trickier: `PlayerScreen` displays `imageFile` directly and offers "save to gallery" from it for the screen's whole lifetime, and the *same* `imageFile` parameter is reused by retry/captured-launch flows where it's already the entry's *permanent* image (must never be deleted). Added an explicit `deleteImageOnDispose` flag (`PlayerScreen` → `runAnalysisAndNavigate` → `AudioGuideService`'s `home_screen.dart`/`_pickImage` call site), defaulting `false` everywhere except the one call site that genuinely owns a temp file — retry/captured-launch flows (both screens) leave it at the default, so history thumbnails are never at risk
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 112/112 (pure Dart change, no native/manifest/build-script edits, so no local Android build needed). No existing test covers `PlayerScreen` (this codebase has no widget tests yet) — spot-checked the file-existence guards logically; worth confirming on-device that a temp capture disappears after leaving the player and that a history retry still shows its thumbnail afterward

- [x] **T85** 📈 ⭐⭐⭐⭐ - Run the **analysis in the background** and **notify** when the audio is ready
  - **Verified**: 2026-08-17 (PR #43)
  - **Context**: user reports of the app freezing/dying when backgrounded alongside GPS-heavy apps (AllTrails, Ingress) during an analysis. Nothing protected the process before this — no foreground service, no wakelock — so Android could kill it at any point (memory pressure, Doze, battery optimization), silently dropping the analysis with no signal beyond a `pending` history entry the user might find later
  - **What was done**: a minimal native Android foreground service (`AnalysisForegroundService.kt`, `ForegroundServicePlugin.kt`, following the existing hand-rolled-plugin pattern rather than pulling in `flutter_background_service` — the analysis already ran fine at the Dart level even when backgrounded, only the OS process itself was at risk) now runs for the whole duration of `AudioGuideService.analyzeAndPlay()` and `generateAudioForScript()` (GPS+AI+TTS or TTS-only), holding a low-priority "AudioLens est actif en arrière-plan" notification (`foregroundServiceType="dataSync"`, the closest documented fit for a network/AI background task). `flutter_local_notifications` (new dependency) posts a "Votre audioguide est prêt" / "L'analyse a échoué" notification on completion, but only when the user isn't already looking at the app (`WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed`) — a clean cancellation doesn't trigger a "failed" notification, since the user asked to stop
  - **Test safety**: both Dart wrappers (`AnalysisForegroundService`, `AudioReadyNotifier`) swallow platform-channel errors by design, not just for test convenience — a foreground-service/notification hiccup must never break the actual analysis, and platforms without this concept (iOS) should just no-op. This kept all ~109 pre-existing tests (which construct `AudioGuideService` without mocking these new channels) passing unmodified
  - **Build changes**: `flutter_local_notifications` requires core library desugaring (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`), patched into `build.gradle.kts` alongside the existing genai-prompt dependency block, in both `scripts/build_android_local.sh` and `.github/workflows/build-android.yml` — discovered via a real local build failing on `checkDebugAarMetadata` before this was added. New `<uses-permission>` entries (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`) and the `<service>` declaration are patched the same guarded-sed way as every other manifest addition in this repo (`android/` isn't committed, regenerated fresh every build)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 112/112 (3 new tests in `background_execution_test.dart`; 1 pre-existing real-wall-clock-timing test flaked once under load, unrelated to this change, confirmed passing in isolation); real local **debug and release** builds both succeeded — verified via `aapt dump xmltree` that `foregroundServiceType="dataSync"` actually landed on the merged manifest's `<service>` element, and via `aapt dump badging` that the release APK stays non-debuggable (T79)
  - **Requires real-device verification** (same precedent as T89): whether the process genuinely survives backgrounding under real memory pressure, and whether the notifications appear as expected, cannot be confirmed in this environment — needs testing on a physical device, ideally alongside AllTrails/Ingress per the original report
  - **Fast-follow (2026-08-17, PR #44)**: real-device testing found the notification's small icon was the full-color `ic_launcher` reused as-is — Android forces notification icons to render as a flat white silhouette from the alpha channel alone, which made it an unrecognizable blob, indistinguishable from other apps'. Added a dedicated monochrome vector icon (`res/mipmap-anydpi-v26/ic_notification.xml`, mirroring the launcher's headphone + soundwave mark, simplified for legibility at status-bar size) and pointed both the foreground service and `AudioReadyNotifier` at it instead

- [x] **T70** 📈 ⭐⭐ - Migrate to **dio** for cancellable HTTP requests
  - **Verified**: 2026-08-17 (PR #42)
  - **Context**: `GeminiApiService`/`GeminiTtsService` used `http` + `Future.timeout()` — that combo stops the *caller* from waiting on a slow/cancelled request, but leaves the request itself running to completion in the background regardless (wasted quota/CPU, and a race where a cancelled analysis could still overwrite `AudioGuideService`'s state after `cancelCurrentAction()` already reset it to idle)
  - **What was done**: both services now use `dio`, with the app's existing `CancelToken` (`utils/cancel_token.dart`) bridged to a fresh `dio.CancelToken` per request — cancelling it genuinely aborts the in-flight socket read, not just the wait. A `DioException(type: cancel)` (from either explicit cancellation or the same-duration timeout, which now also cancels the socket instead of just throwing) is mapped to `CancelledException`, which is treated as "stop cleanly" rather than "this attempt failed" throughout the call chain: `GeminiApiService`'s per-model retry loop rethrows it instead of trying the next model, `TtsOrchestrator.speak()` rethrows it instead of falling back to the native voice, and `AudioGuideService`'s Nano-fallback catch rethrows it instead of retrying locally. `AIService.analyzeImage()` gained an optional `cancelToken` parameter (ignored by `GeminiNanoService`, which isn't network-based)
  - **Test coverage**: new `t70_cancellation_test.dart` proves the abort is real, not just that the caller stops waiting — a fake adapter that would take 5s to "complete" is actually interrupted in well under a second once the token cancels, both at the `GeminiApiService` level and end-to-end through `AudioGuideService.cancelCurrentAction()` (asserts the service lands on `idle`, not `error`). Existing `http`/`MockClient`-based tests migrated to a small shared `FakeHttpClientAdapter` (`test/support/fake_dio_adapter.dart`)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 109/109 (2 new tests; 1 pre-existing test — a real-wall-clock-timing assertion in `tts_chunking_test.dart`, unrelated to this change — is separately flaky under load, confirmed by re-running in isolation)

- [x] **T86** 🌱 ⭐ - Fix Ko-fi **icon contrast** on the home screen
  - **Verified**: 2026-08-16 (PR #40)
  - **Confirmed by**: a screenshot showing the Ko-fi icon visibly darker than the history/settings icons right next to it on the home screen's icon row — all three sit on the same page-level gradient background, so the mismatch traced to styling, not backdrop: history/settings `IconButton`s use the theme's implicit default color, while `KofiButton` hardcodes `Colors.grey[600]` (chosen to read as subtly de-emphasized against the plain `AppBar`s on the other 5 screens where it shows, and left unchanged there)
  - **What was done**: `home_screen.dart` now passes `iconColor: theme.colorScheme.onSurfaceVariant` to `KofiButton` (using the override param the widget already supported) — matches its neighbors' contrast on this screen specifically, without touching the shared default used elsewhere
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 107/107

- [x] **T89** 📈 ⭐⭐⭐ - Replace **Piper** (sherpa_onnx) with the **native Android TTS engine**
  - **Verified**: 2026-08-16 (PR #39)
  - **Context**: started as "investigate native TTS as a better-quality Piper alternative" while chasing Gemini TTS 429s. Real-device A/B testing (added in earlier PRs #35/#37/#38: a comparison UI, then a voice picker, then surfacing voices that silently produced no audio) showed the native voice was clearly better — user's verdict: "la native Android est bien meilleure. elle a juste une voix d'annonce SNCF" (the default voice was flat/robotic; `fr-fr-x-frc-network` sounded much better suited to a museum guide)
  - **Decision**: replace Piper entirely rather than keep both — offers a female voice (`fr-fr-x-frc-network`, default) and male (`fr-fr-x-frd-network`) picker in Settings instead
  - **APK size result**: release APK went from **~77 MB to 41.8 MB** (real local release build, throwaway keystore, same flow as CI) — Piper's `assets/tts/` (36 MB voice model + espeak-ng-data) and `sherpa_onnx`'s native libs (~43 MB, arm + arm64) are both gone; verified zero `sherpa`/`onnx`/`espeak` artifacts remain in the built APK
  - **What was done**:
    - `NativeTtsService` (`lib/services/native_tts_service.dart`) is now the app's sole local/offline TTS engine, wrapping `flutter_tts`. Same public shape as the old `TtsService` (`onComplete`/`onProgress`/`isPlaying`/`speak`/`pause`/`stop`) so `TtsOrchestrator` only needed a different engine plugged in (`piper:` → `nativeTts:`), not restructuring
    - Gender preference (`GuidePreferencesStore.loadTtsVoiceGender`/`saveTtsVoiceGender`, `'female'`/`'male'`) is applied lazily on first real use (matching Piper's old lazy-init pattern) — a plain field assignment in `AudioGuideService.init()`, never touching the platform channel during app startup, so no existing test needed a TTS mock added just because `.init()` runs
    - `applyPreferredVoice()` checks the device's actual voice catalog before selecting one (`frenchVoices()`) — if the preferred gendered voice isn't really available (T89's "catalog-listed but silently produces no sound" quirk), it leaves the engine's own default French voice in place instead of risking a silent no-op
    - Pause/resume: Android's TextToSpeech has no true pause/resume — `flutter_tts` fakes it by remembering how much text was already spoken (via its word-boundary progress callback) and expects the *same* text passed to `speak()` again to continue, which `NativeTtsService.resume()` wraps. Also fixed a pre-existing bug in `AudioGuideService.togglePause()`: it checked "is Gemini TTS configured" instead of "did Gemini TTS actually play this time" (`lastTtsModel == 'gemini-tts'`), so pausing after a fallback used to pause nothing while the fallback engine kept talking
    - `cancelCurrentAction()` now stops both engines explicitly — native TTS manages its own playback internally, unlike Piper/Gemini TTS's WAV files which shared the `audio_guide/audio_player` channel
    - History caching: native TTS entries don't produce a cacheable WAV file (`flutter_tts` plays directly, no file); replay just re-synthesizes, which is fine since it's instant and free, unlike Gemini TTS's quota-limited calls
    - Settings → "Voix" section: a Féminine/Masculine segmented picker plus a "Tester la voix" preview button, replacing the earlier T89 comparison UI (which is no longer needed now that the decision is made)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 107/107 (4 test files updated: `_FakePiper extends TtsService` → `_FakeNativeTts extends NativeTtsService` throughout); real local **release** build (not just debug) confirmed the APK builds, is correctly signed/non-debuggable, and is free of Piper artifacts

- [x] **T90** ⚡ ⭐⭐ - Analysis title (and sometimes the **script** itself) shows **raw JSON** instead of parsed text
  - **Verified**: 2026-08-16 (PR #34)
  - **Context**: not the first attempt at this — earlier fixes (the naive `text.indexOf('{')`/`lastIndexOf('}')` extraction + sentence-split fallback) still had gaps, per repeated real-world reports (~1/20 analyses). Mid-PR, the user reported the *script* (not just the title) sometimes shows as raw JSON too — the first version of this fix guarded the title but still fell back to raw `text` (still JSON-shaped) as the script when the script field wasn't recoverable
  - **What was done**: `gemini_api_service.dart`'s title/script parsing now has three layers instead of one:
    1. `_extractJsonObject` — a balanced-brace scan that tracks whether it's inside a string literal, so a `{`/`}` inside the model's own `script` text (or a ` ```json ` fence around the object) no longer throws off the match, unlike the old indexOf/lastIndexOf pair
    2. If full `jsonDecode` still fails (e.g. an unescaped quote inside a field breaks JSON syntax even with correct brace balance), a regex fallback recovers `title`/`script` independently — but now **both** must be recovered, not just `title`, or the result is discarded
    3. Last-resort guard: if the response still looks JSON-shaped (`{`-prefixed or a `"title"`/`"script"` key literal present) but neither layer above could fully recover it, the analysis **throws** instead of ever showing raw JSON as the title or reading it aloud as the script — worse to fail loudly (existing retry flow already handles this) than to silently show/speak broken JSON as if it were real content. A true plain-text response (model ignored the JSON instruction entirely, no JSON markers at all) still falls through to the original sentence-split heuristic unchanged — that's legitimate readable content, just not in the expected shape
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 107/107 (8 cases in `gemini_title_parsing_test.dart`: fenced JSON, braces inside script, unescaped quote inside script recovered via regex, plain-text fallback, and 3 throw-instead-of-leak cases covering both the title-side and script-side gaps)

- [x] **T88** ⚡ ⭐⭐⭐ - Thumbnails sometimes display **upside down / sideways**
  - **Verified**: 2026-08-16 (PR #32)
  - **Root cause found**: not an AudioLens bug at all — a Flutter engine/Skia rendering bug in **Flutter 3.32.2**, the version CI was pinned to. `.github/workflows/build-android.yml`/`test.yml` now pin **3.44.9**
  - **How this was found**: 8+ hypotheses (EXIF orientation in every combination, decode size, aspect-ratio mismatch, `ColorFiltered`, `image_picker` resize, missing list `key`s, byte-for-byte grid code reproduction, software vs. hardware GPU rendering) were tested and ruled out across two sessions on real Android 16/17 emulators — including with the *actual* affected file, pulled directly off the reporter's Pixel 10 over USB (`adb pull` from the device's saved-to-gallery copy, via the app's existing "Sauvegarder" button — no `run-as` needed since it's shared storage, not app-private). None reproduced it
  - The breakthrough: the user pointed out every test that day had used a **locally-built app** (this dev machine, Flutter 3.44.9) or the **CI-built release APK** (Flutter 3.32.2, pinned in the workflow) — and the bug only ever showed up with the CI build. Built a release APK locally (throwaway keystore, matching CI's `patch_signing.py` + `--target-platform android-arm,android-arm64` flow) and installed it directly on the reporter's Pixel 10 via USB: correct. Confirmed it wasn't debug-vs-release build mode, a device/driver quirk, or anything in AudioLens's code — purely the pinned Flutter SDK version
  - **Diagnostics added along the way, kept even though they didn't end up pinpointing it**: `about_analysis_screen.dart`'s "Copier les infos de debug" now includes the image's raw EXIF orientation tag, Flutter's actual decoded dimensions, file size, and 5 sampled pixel colors (top/bottom/left/right/center) — useful for any future image-rendering report
  - **Also added** (real, defensible Flutter practice found while investigating, even though it turned out not to be the cause here): `key: ValueKey(entry.id)` on the home grid's and history list's dynamically-reordered items
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 94/94 (unaffected — this was a CI pipeline config fix, not an app code fix); confirmed on real hardware (Pixel 10) with the actual reported file, not just emulators

- [x] **T87** 🌱 ⭐⭐⭐ - Let the user **pick the location on a map** when a gallery photo has no GPS in its EXIF
  - **Verified**: 2026-08-16 (PR #26)
  - **Context**: `LocationContextResolver.resolve()` fell back to the device's *real-time* GPS position when a photo had no EXIF GPS — reasonable for a fresh camera capture, misleading for a gallery photo (could be old, from anywhere)
  - **What was done**:
    - `flutter_map` + `latlong2` added (OpenStreetMap tiles, no API key — matches the project's existing OSM-based stack: Nominatim, Overpass)
    - `lib/screens/map_picker_screen.dart` (new): tap-to-drop-pin map, best-effort centers on the device's current position purely as a convenient starting point (never used as the actual answer)
    - `home_screen.dart`: when picking from the gallery and EXIF has no GPS, pushes the map picker before starting analysis; if the user picks a spot, it flows through as `knownCoordinates` (source `'map'`) — the exact same plumbing T78 built for deferred-capture coordinates (`AudioGuideService.analyzeAndPlay` → `LocationContextResolver.resolveFromCoordinates`), already covered by `deferred_capture_test.dart`. If declined, behavior is unchanged (falls back to real-time GPS as before)
    - `about_analysis_screen.dart`: added the `'map'` GPS source label (`🗺️ Choisie sur la carte`) — the existing `_gpsSourceLabel` switch already had an "Inconnu" fallback so nothing would have broken, but this is the honest label
  - **Camera captures with no GPS** (permission denied, no signal): unchanged, still fall back to real-time GPS — out of scope, only the gallery case was misleading
  - **Verified for real**: local Android build + emulator (Android 17, matching the reporter's device) — pushed a GPS-less test photo into the gallery, picked it through the real app, confirmed the map picker opens, real OSM tiles load, tap drops a pin at the right spot, "Confirmer" returns it and analysis proceeds (up to the expected "no API key" error in this test environment — nothing to verify past that point, `resolveFromCoordinates` is already tested)
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 95/95 (unchanged — the new code is UI-flow wiring with no widget-test harness in this project yet, same gap as T14; verified via the real build instead)

- [x] **T14** 🌱 ⭐⭐ - Add a **playback display mode** showing the plain photo (instead of overlaid text)
  - **Verified**: 2026-08-16 (PR #21)
  - **Design confirmed with the user first**: a per-screen toggle (not persisted, not a global setting) in `player_screen.dart`'s top bar, next to the Ko-fi button
  - **What was done**: `_PlayerScreenState._photoMode` (new); when on, hides the state label, title, location row, save/copy action row, fallback banners, and the scrollable script, and switches the background gradient from the heavy bottom-weighted one (needed for text contrast) to a light scrim only at the very top/bottom edges (just enough for the back/toggle/Ko-fi icons and playback controls to stay legible) — leaving the photo shown clean. Playback controls (pause/stop) and the top bar stay visible in both modes. Resets to off automatically when a new analysis starts (mirrors the existing `_readingProgress` reset), so the toggle can't leave a stale "photo mode" showing over unrelated new content. The toggle icon itself only appears once `guide.lastResult != null` (same guard as the text content it replaces)
  - **Not verified visually**: no Android emulator/device is set up in this environment — verification here is `flutter analyze`/`flutter test` (unaffected, this is a pure widget-state change with no new service logic) and a careful read of the diff, not an actual on-screen check. Worth a quick look on a real device before considering this fully done
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 89/89 (unchanged — no new unit-testable logic; the project has no widget-test harness for `player_screen.dart`'s Provider-dependent tree yet)

- [x] **T09** 📈 ⭐⭐⭐ - Improve **local storage robustness** and migrations
  - **Verified**: 2026-08-16 (PR #20)
  - **Merged from**: storage robustness + SQLite migration tests (ex-T44)
  - **Investigated first**: read `sqflite_common`'s source (`database_mixin.dart`) before writing anything — `openDatabase` already wraps the entire `onCreate`/`onUpgrade` callback in one exclusive SQLite transaction (`await transaction((txn) async { ... onUpgrade ...; await setVersion(...); }, exclusive: true)`). A failure partway through `history_service.dart`'s multi-`ALTER TABLE` upgrade block was assumed to be a real risk (partial columns added, version not bumped, "duplicate column" crash-loop on retry) — it isn't; sqflite already rolls it back atomically and never bumps the version on failure. Confirmed empirically, not just by reading source (see below)
  - **What was done**:
    - `history_service.dart`: `HistoryService.init()` now takes an optional `dbPath` param (same DI pattern used elsewhere) so tests can point it at an isolated file instead of the real app database
    - `test/history_service_migration_test.dart` (new): hand-reconstructed the historical v1-v5 schemas from the `onUpgrade` ALTER sequence, migrates each one to v6 through the real `HistoryService.init()` path, and checks data survives with sane defaults on new columns — this path had zero test coverage before (only `HistoryEntry` serialization was tested, never the actual `openDatabase`/migration flow)
    - Same file: a dedicated test reproduces the transaction/rollback guarantee directly (2-step `onUpgrade` that throws after the first `ALTER`) and confirms the DB is left at the old version with no partial column — this is what actually verifies the "transactions, rollbacks" part of the task, since sqflite already provides it and there was nothing to add in `history_service.dart` itself for that half
    - `sqflite_common_ffi` added as a dev dependency (needed to run real SQLite against a file in `flutter test`, no platform channel available there) — added `libsqlite3-0` install step to `test.yml` (`ubuntu-latest` usually has it already, pinned explicitly rather than relying on that)
  - **Not done**: `HistoryService`'s CRUD methods (`addPendingEntry`, `completeEntry`, etc.) remain untested — that's T68's broader scope, noted there
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 89/89 (7 new: `history_service_migration_test.dart`)

- [x] **T07** 📈 ⭐⭐⭐ - **Centralize configuration** (AI, TTS, GPS, etc.)
  - **Verified**: 2026-08-16 (PR #19)
  - **Context**: `RemoteConfig` already defines most values centrally, but several fields were fetched and never actually read anywhere — the original evidence (`home_screen.dart` hardcoding `imageQuality`/`maxWidth`) turned out to be one of three
  - **What was done**:
    - `home_screen.dart`: `ImagePicker` now reads `RemoteConfigService.current.imageQuality`/`imageMaxWidth` instead of hardcoded `85`/`1280`
    - `guide_progress_estimator.dart`: `_maxSamples` (hardcoded `5`) and the progress-simulation tick interval (hardcoded `150ms`) now default from `RemoteConfig.timingHistorySize`/`progressSimulationIntervalMs`, both previously unused anywhere in the codebase — via optional constructor params (`maxSamples`, `simulationIntervalMs`) rather than reading the global directly, so tests can override them
    - `location_service.dart`: **real bug found while auditing `locationTimeoutSeconds`** — it was defined in `RemoteConfig` (default 10s) but never applied anywhere; the native `requestLocation` channel call (`LocationPlugin.kt`) had no timeout on either side (Kotlin or Dart), so a GPS fix that never resolves (e.g. indoors, no signal) could hang the pipeline indefinitely with no way out short of force-quitting the app. `getCurrentLocation()`/`getCurrentRawCoordinates()` now wrap the channel call in `.timeout(...)`, defaulting to the config value via an optional `timeout` param (same DI pattern as the existing `client` param) so tests don't have to wait on the real default
  - **Not changed**: HTTP call timeouts scattered across `gemini_api_service.dart`/`gemini_tts_service.dart`/`poi_service.dart`/`wikipedia_service.dart` (6-60s, each used once) — these aren't duplicated constants, just not configurable; centralizing them wasn't part of this task's actual evidence and would be scope creep
  - **Final validation**: `flutter analyze` → 0 issues; `flutter test` → 82/82 (4 new: `location_timeout_test.dart` covering the real hang bug, 1 in `guide_progress_estimator_test.dart`)

- [x] **T83** 📈 ⭐⭐ - **Speed up the Android CI build**
  - **Verified**: 2026-08-16 (already done, noticed during a follow-up question — the fix landed on 2026-08-15 as commit `0e0f8be` but TODO.md/CHANGELOG.md were never updated to reflect it)
  - **What was done** (commit `0e0f8be`, "T83: cache Gradle/pub/NDK across CI runs, drop unused NDK, restrict ABIs"): `actions/cache` added for Gradle (`~/.gradle/caches`), the pub cache, and the Android NDK; build restricted to `--target-platform android-arm,android-arm64` (dropping armeabi/x86/x86_64, only useful for emulators); the unused NDK 26 install dropped, keeping only NDK 27
  - **Verified for real**: compared successful `build-android.yml` run durations before/after the commit via `gh run list` — 6.5–8.3 min before (16 runs, 2026-07-25 to 2026-08-15 17:20), consistently 3.7–5.6 min after (18 runs since) — the "not verified" note from the original task no longer applies

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
  - **Parked (2026-08-16)**: real-world testing showed splitting into several Gemini TTS calls reliably hits rate limiting on a real account — even after raising `chunkMaxChars` 280→700 (fewer calls) and tuning the 429 retry twice, it kept happening, and the resulting mid-script fallback to Piper was judged a worse experience than the plain wait `speak()` gives. `AudioGuideService._synthesizeAndPlay` now calls `speak()` again instead of `speakChunked()`; nothing here was deleted — `TtsOrchestrator.speakChunked()`, `text_chunker.dart`, and their tests are untouched and ready to swap back in, either once quota isn't the bottleneck or alongside T89 (native Android TTS as a fallback that isn't rate-limited)

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
  - **Fast-follow (2026-08-18, Play Store prep)**: the disclaimer had two gaps surfaced while reviewing T84 (Play Store publication) — it was still French-only (`about_analysis_screen.dart` was deliberately excluded from T67's i18n extraction as a debug screen), and only reachable via a small "info" icon on the history detail screen, not shown where the AI-generated content is actually delivered. Fixed both: the existing banner's text is now localized (`AppLocalizations.aboutAnalysisAiDisclaimer`), and a second, shorter disclosure ("Contenu généré par IA" / "AI-generated content", `playerAiGeneratedDisclosure`) now shows persistently on `player_screen.dart` itself, next to the title/location metadata, for every guide played

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
