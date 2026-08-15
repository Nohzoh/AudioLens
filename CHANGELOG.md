# Changelog - AudioLens

Historique des tâches terminées et des retours de tests. Les tâches en cours
ou à faire sont dans [`TODO.md`](TODO.md).

Les identifiants (T01, T02...) forment une séquence unique partagée avec
`TODO.md` — avant de créer une nouvelle tâche, vérifier le plus grand ID dans
les deux fichiers (`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`).

---

## ✅ Terminé

- [x] **T13** 🌱 ⭐⭐ - Permettre la **re-demande d'une ancienne analyse échouée** depuis l'historique
  - **Validé** : 2026-08-16 (déjà fait, constaté lors de la revue de tâches)
  - **Constat** : déjà couvert par T78 — `history_screen.dart` : `_HistoryCard.onTap` relance l'analyse (`_retryAnalysis`) quand l'entrée est `pending` ou `failed`. Pas de code écrit pour cette tâche, simple clôture

- [x] **T69** 🌱 ⭐⭐ - **Documenter l'architecture** et les flux
  - **Validé** : 2026-08-16 (PR #12)
  - **Ce qui a été fait** : `ARCHITECTURE.md` — diagramme du pipeline principal (photo → localisation → IA → TTS → audio, avec les branches capture différée T78 et script seul T16), diagramme de résolution de localisation (EXIF/GPS → reverse geocoding → POI → Wikipedia), tableau de persistance, tableau des canaux natifs, diagramme écrans → services. Écrit après T74/T76/T78/T16 pour refléter le pipeline réel, pas sa forme d'avant ces refontes. `README.md` renvoie vers ce fichier au lieu de dupliquer

- [x] **T76** 📈 ⭐⭐⭐⭐ - **Découper le script en morceaux** pour démarrer la lecture audio plus vite
  - **Validé** : 2026-08-16 (PR #11, commit `4c8dd93`)
  - **Contexte** : ~30s (parfois plus) d'attente entre l'affichage du texte et le début de la lecture audio — `GeminiTtsService.speak()` synthétisait tout le script en un seul appel HTTP bloquant
  - **Ce qui a été fait** :
    - `lib/utils/text_chunker.dart` (nouveau) : découpage aux frontières de phrases, 1er morceau court (démarrage rapide), morceaux suivants plus grands (moins d'allers-retours réseau)
    - `GeminiTtsService` : synthèse et lecture séparées (`synthesizeToFile`/`playFile`), `speak()` existant inchangé ; `concatenateWavFiles` (nouveau) pour que le résultat en morceaux reste mis en cache comme une synthèse classique
    - `TtsOrchestrator.speakChunked()` : synthétise le morceau N+1 pendant que le morceau N joue ; en cas d'échec, repli Piper sur tout le script (échec du 1er morceau) ou juste sur le texte restant (échec plus tard) — pas de redite ni de changement de voix en cours de narration. `onChunkStart(index, total)` pilote une vraie progression morceau N/M au lieu du spinner indéterminé
    - `CancelToken.onCancel` (nouveau, `Future` complété par `cancel()`) pour pouvoir faire courir la boucle de lecture contre l'annulation plutôt que de sonder `isCancelled`
  - **Bugs réels trouvés en construisant ceci** :
    - `AudioPlayerPlugin.kt` : `stop()` ne résolvait jamais un appel `playWav` en cours — aurait bloqué indéfiniment l'annulation en cours de morceau, seul le nouveau chemin en morceaux awaite vraiment `playWav`. Corrigé (suivi du `Result` en attente, résolu aussi par `stop`)
    - Une erreur de synthèse pouvait remonter comme erreur Zone non gérée malgré un `try/catch` plus loin — Dart marque une `Future` rejetée comme non gérée si aucun listener n'est attaché au moment du rejet. Corrigé en attachant `.then(onError:)` immédiatement à la création de la `Future`
  - **Vérifié réellement** : build Android local (le fichier Kotlin natif est modifié)
  - **Validation finale** : `flutter analyze` → 0 issue ; `flutter test` → 78/78 (13 nouveaux : `text_chunker_test.dart`, `tts_chunking_test.dart`)

- [x] **T78** 🌱 ⭐⭐⭐⭐ - **Capture différée** : photo + GPS maintenant, analyse (cloud) plus tard
  - **Validé** : 2026-08-16 (PR #9, commit `33c0673`)
  - **Contexte** : demande utilisateur — économiser sa conso data sans se rabattre sur les modèles locaux (qualité moindre) : capturer photo + position tout de suite, lancer l'analyse cloud plus tard (ex. une fois sur wifi)
  - **Ce qui a été fait** :
    - `AnalysisStatus.captured` (nouveau) : photo + GPS brut enregistrés, analyse non lancée — aucune migration DB (`status` déjà en TEXT, colonnes GPS déjà existantes)
    - `LocationService.getCurrentRawCoordinates()` : fix GPS sans reverse geocoding — capture vraiment hors-ligne (le fix GPS lui-même n'a pas besoin de réseau ; `getCurrentLocation()` couplait jusque-là systématiquement le fix à un appel Nominatim)
    - `LocationContextResolver` scindé en résolution de coordonnées (`resolve()` depuis une photo, ou `resolveFromCoordinates()` depuis des coordonnées déjà connues) + enrichissement partagé (`_enrich` : reverse geocoding + POI + Wikipedia) — l'enrichissement tourne maintenant au moment de "lancer l'analyse", avec les coordonnées capturées à l'époque, pas la position actuelle de l'appareil
    - `home_screen.dart` : option "Capturer sans analyser" ; `history_screen.dart` : les entrées capturées ont maintenant un statut visuel et déclenchent l'analyse au tap avec les coordonnées stockées (cet écran ne gérait auparavant aucun tap pending/failed/captured — seule la grille de `home_screen.dart` le faisait ; les deux sont maintenant cohérents)
    - `lib/utils/analysis_runner.dart` (nouveau) : séquence "analyser + persister en historique" extraite et partagée entre les deux écrans
  - **Bonus** : `LocationService` n'avait aucune injection de client HTTP (contrairement à tous les autres services réseau du projet) — ajoutée, nécessaire pour pouvoir vérifier ce changement par un vrai test plutôt qu'à l'inspection
  - **Validation finale** : `flutter analyze` → 0 issue ; `flutter test` → 65/65 (3 nouveaux : `deferred_capture_test.dart`)
  - **T20 retirée (2026-08-16)** : "Améliorer l'expérience hors ligne" (reprise/cache + badge fonctions dispo/indispo) était devenue obsolète — couverte par ce qui précède (capture différée hors-ligne, statuts visuels par entrée)

- [x] **T16** 🌱 ⭐⭐⭐ - Ajouter un **mode sans TTS**, avec **génération audio à la demande** ensuite
  - **Validé** : 2026-08-15 (PR #7, commit `896bb2b`)
  - **Contexte** : demande utilisateur — réglage pour désactiver la génération audio automatique après l'analyse, avec possibilité de demander la synthèse audio plus tard depuis une entrée "script seul" de l'historique
  - **Ce qui a été fait** :
    - `SettingsService.autoGenerateAudio` (défaut `true`), toggle dans les paramètres sur le modèle de `showKofiButton`
    - `AudioGuideService.analyzeAndPlay(imageFile, generateAudio: false)` s'arrête après l'analyse IA, état `GuideState.scriptReady` (nouveau) au lieu de `speaking` — aucune migration DB nécessaire, `HistoryEntry.audioPath` était déjà nullable
    - `AudioGuideService.generateAudioForScript()` (nouveau) : relance uniquement l'étape TTS (`TtsOrchestrator`, donc fallback cloud → Piper) sur un script déjà connu, sans refaire GPS/Wikipedia/IA
    - `history_screen.dart` : indicateur "Script seul" sur les entrées sans audio, bouton "Générer l'audio" qui persiste désormais le résultat via `HistoryService.saveAudioPath` (l'ancien comportement — génération à la volée sans sauvegarde ni fallback — a été remplacé)
  - **Validation finale** : `flutter analyze` → 0 issue ; `flutter test` → 62/62 (7 nouveaux : `script_only_mode_test.dart`)

- [x] **T74** 📈 ⭐⭐⭐ - Améliorer la **détection des lieux et de leur histoire**
  - **Validé** : 2026-08-15 (PR #5, commit `3592327`)
  - **Contexte** : Test réel (bowling de la Matène, 2026-08-12) — l'appli n'a pas évoqué le tournage des *Tontons flingueurs* : le lieu n'avait pas d'article Wikipedia géolocalisé dans le rayon de 200 m, et le nom du commerce (POI) n'était jamais récupéré
  - **Ce qui a été fait** :
    - `PoiService` (nouveau) : recherche Overpass API des POI taggés (leisure/tourism/historic/amenity) proches, sélectionne le plus proche par distance de Haversine
    - `WikipediaService.searchByName` (nouveau) : recherche full-text par nom + ville, fusionnée avec le géosearch existant (`WikipediaService.merge`), fallback fr → en si le français ne trouve rien
    - Prompt `gemini_api_service.dart` : incite explicitement le modèle à utiliser le lieu identifié/l'adresse pour cerner l'endroit réel et chercher des faits marquants (tournages, événements, personnalités) plutôt que de décrire seulement ce qui est visible
    - **Bug corrigé au passage** : `wikipedia_radius_meters`/`max_results`/`extract_chars` de `RemoteConfigService` étaient récupérés mais jamais réellement transmis à `WikipediaService.searchNearby` (l'appel utilisait ses propres valeurs par défaut) — câblés ; rayon par défaut relevé 200 m → 500 m (l'augmenter via `config.json` n'avait auparavant aucun effet, la valeur n'était jamais lue)
  - **Note** : `location_service.dart`/`audio_guide_service.dart` non touchés — la cible d'origine datait d'avant le refactor T06 ; un `PoiService` dédié s'intègre mieux dans cette architecture, et aucun nouveau champ persisté/affiché n'était nécessaire pour corriger le bug réel (l'IA ne mentionnait jamais le lieu)
  - **Validation finale** : `flutter analyze` → 0 issue ; `flutter test` → 55/55 (11 nouveaux : `poi_service_test.dart`, `wikipedia_service_test.dart`)

- [x] **T79** 🔥 ⭐⭐ - La CI distribue un **APK debug**, pas release
  - **Validé** : 2026-08-15 (commits `4011b5e`, `9d9ff11`, `88c196d` — run CI vert [31897372162](https://github.com/Nohzoh/audio-guide/actions/runs/31897372162))
  - **Ce qui a été fait** : `flutter build apk --release` (au lieu de `--debug`) ; vérification CI que l'APK final n'est pas `debuggable` (via `aapt dump badging`)
  - **Détours rencontrés en cours de route** :
    - R8/minification (activée par défaut en release) cassait le build sur des classes manquantes (`javax.lang.model.*`) venant d'une dépendance shaded tirée par les deps MediaPipe/genai mortes (cf. T82) — minification désactivée explicitement dans `scripts/patch_signing.py` en attendant leur suppression
    - Le check anti-debuggable ajouté ne vérifiait en fait rien : `aapt` n'est pas sur le `PATH` du runner CI, donc le `grep` matchait toujours sur une entrée vide et affichait "non debuggable" quoi qu'il arrive — corrigé en localisant le binaire sous `$ANDROID_HOME/build-tools`
  - **Vérifié réellement** : run CI final montre `aapt dump badging` fonctionnel (package/version/sdkVersion affichés) et confirme l'absence du flag `application-debuggable`

- [x] **T80** ⚡ ⭐⭐ - `allowBackup` forcé à `true` en CI avec une classe `backupAgent` probablement fausse
  - **Validé** : 2026-08-15 (commit `4011b5e`)
  - **Ce qui a été fait** : les 4 `sed` chaînés (avec `backupAgent` bogué et repli silencieux `|| true`) remplacés par un seul patch explicite `android:allowBackup="false"` — décision : pas de backup automatique tant que l'historique (GPS, photos) n'a pas de règles d'exclusion dédiées. Répliqué dans `scripts/build_android_local.sh` pour cohérence CI/local

- [x] **T81** ⚡ ⭐⭐⭐ - `RemoteConfigService` peut rediriger la clé API vers une URL arbitraire, sans validation
  - **Validé** : 2026-08-15 (commit `4011b5e`)
  - **Ce qui a été fait** : `RemoteConfigService.isAllowedApiUrl()` — allowlist (`generativelanguage.googleapis.com`) vérifiée avant d'utiliser un `gemini_api_url` reçu de la config distante, sinon retour à la valeur par défaut. 4 tests ajoutés (`remote_config_service_test.dart`, premier test de ce service)

- [x] **T82** 📈 ⭐⭐ - Nettoyage complémentaire post-T06 (code mort restant)
  - **Validé** : 2026-08-15 (PR #3, commit `0b14c3b`)
  - **Ce qui a été fait** : `MediaPipePlugin.kt` et son enregistrement dans `MainActivity.kt` supprimés, dépendance Gradle `tasks-genai` retirée (`genai-prompt`, utilisée par `GeminiNanoPlugin.kt`, conservée) ; dépendance Dart inutilisée `google_generative_ai` retirée de `pubspec.yaml` ; conditionnel mort dans `gemini_api_service.dart` supprimé plutôt qu'implémenté (le regex — toute ligne commençant en minuscule et finissant par un point — était trop large et risquait de couper de la narration française légitime, sans aucun test pour détecter une régression)
  - **Bonus trouvé en validant en local** : le patch `allowBackup` (T80) n'était pas idempotent — le relancer sur un manifest déjà patché (sans bootstrap frais) dupliquait l'attribut et cassait le merge du manifest. Corrigé dans les deux scripts (CI + local) avec le même pattern de garde que les blocs permissions/FileProvider
  - **Vérifié réellement** : bootstrap Android local vraiment à froid (`git clean -X` sur `android/` — sans toucher aux fichiers trackés), build debug réussi sans `MediaPipePlugin`. `flutter analyze` → 0 issue, `flutter test` → 44/44

- [x] **T02** - Améliorer la gestion des **erreurs réseau** et du fallback local
- [x] **T03** - Empêcher les **analyses concurrentes** et gérer proprement les retries/cancellations
- [x] **T04** - Vérifier et corriger la **logique de géolocalisation** lors d’une nouvelle analyse après échec
- [x] **T05** - Afficher un **message utilisateur clair** en cas d’échec de l’amélioration de voix (ex. HTTP 429)
  - **Validé** : 2026-08-02
- [x] **T31** - Introduire des **types d’erreurs métier explicites**
- [x] **T32** - Ajouter une **couverture de tests de base** sur les services critiques
- [x] **T33** - Vérifier la **licence du projet** et ajouter/clarifier le fichier de licence
- [x] **T39** 🔥 ⭐⭐ - Corriger les erreurs bloquantes de `flutter analyze`
  - **Validé** : 2026-08-02 (via T39b)
- [x] **T40** 🔥 ⭐⭐ - Corriger l’onboarding pour parler de **Gemini API** au lieu d’Anthropic
  - **Validé** : Inclus dans T60 (commit `0f13e76`)
- [x] **T39b** 🔥 ⭐⭐ - Corriger **toutes les erreurs `flutter analyze`**
  - **Validé** : Commit `c37a3f1`
- [x] **T60** 🔥 ⭐ - Supprimer tout code et références à **Anthropic/OpenAI**
  - **Validé** : Commit `0f13e76`
- [x] **T61** 🔥 ⭐⭐⭐ - Aligner les **fournisseurs cloud** avec l’implémentation réelle
  - **Validé** : Inclus dans T60 (commit `0f13e76`)
- [x] **T62** ⚡ ⭐⭐⭐⭐ - **Compléter les modèles locaux** ou supprimer les écrans inutilisés
  - **Validé** : Commit `c37a3f1`
- [x] **T38** 🌱 ⭐ - Ajouter un **bouton Ko-fi** pour accepter des soutiens volontaires
  - **Validé** : Commit `83a790e` (widget réutilisable, intégration dans toutes les pages, toggle dans les paramètres)
- [x] **T42** 🔥 ⭐⭐⭐ - Ajouter une vérification de **build Android complet** et clarifier le rôle du bootstrap dans GitHub Actions
  - **Validé** : Commit `82d877a`
- [x] **T01** 🔥 ⭐⭐⭐ - Corriger le **freeze du téléphone** lors du lancement de Piper + ajouter un **bouton d’annulation**
  - **Lié à** : T43 (annulations interruptibles)
  - **Validé** : Commit `37f4ccd` (bouton d'annulation + état cancelling + timeout)
  - **Note** : Bouton d'annulation fonctionnel pendant la synthèse. Freeze résiduel nécessite T43.
- [x] **T43** ⚡ ⭐⭐⭐ - Rendre les **annulations vraiment interruptibles** (appels HTTP, étapes longues du pipeline)
  - **Lié à** : T01 (freeze Piper)
  - **Validé** : Commit `4a9b211` (CancelToken system, checks avant chaque étape, passage aux services TTS)
  - **Note** : Annulations basées sur checks avant chaque étape. HTTP natif non supporté (nécessite package dio).
- [x] **T63** ⚡ ⭐ - **Unifier le nom du projet** sur AudioLens
  - **Validé** : Commit `6afd7b9` (pubspec, README, AGENTS, workflow) + renaming complet du package Android (Kotlin files, channels, namespace)
- [x] **T64** ⚡ ⭐⭐ - Nettoyer les **fichiers untracked** et le .gitignore
  - **Validé** : Commit `2e3d404` (nettoyage des untracked files)
- [x] **T65** ⚡ ⭐⭐ - Nettoyer tous les **imports inutilisés** et variables mortes
  - **Validé** : Commit `e176b62` (7 fichiers nettoyés, 0 warnings)
- [x] **T41** ⚡ ⭐ - Synchroniser le **README** avec le produit actuel
  - **Contenu à mettre à jour** : Gemini Nano/API, TTS Gemini/Piper, état Android, architecture
  - **Validé** : 2026-08-08 (README réécrit : pipeline EXIF/GPS → Wikipedia → IA → TTS, fournisseurs IA, TTS, plateforme, config)
- [x] **T66** ⚡ ⭐ - Remplacer tous les **.withOpacity()** par **.withValues()**
  - Fichiers concernés : `history_screen.dart`, `home_screen.dart`, `player_screen.dart`, `onboarding_screen.dart`, `settings_screen.dart`, widgets/*
  - **Validé** : 2026-08-08 (20 occurrences remplacées dans 7 fichiers)
- [x] **T71** ⚡ ⭐ - Nettoyer la **configuration des assets** dans pubspec.yaml
  - Supprimer les doublons (`assets/tts/` apparaissait 2 fois)
  - Vérifier que tous les assets existent
  - **Validé** : 2026-08-08 (doublon supprimé, existence vérifiée)
  - **Note** : `assets/images/google.png` référencé dans `app_settings.dart` mais absent (code mort, nettoyé dans T06)
- [x] **T47** ⚡ ⭐⭐ - Ajouter une **fiche technique d’analyse**
  - **Contenu** : Modèle utilisé, fallback, GPS, Wikipedia, durée, source
  - **Dépend de** : T46 (tests de fallback, toujours à faire)
  - **Validé** : 2026-08-08 (indication de fallback IA/TTS ajoutée à l'écran "À propos", persistance dans `HistoryEntry` + migration DB v6, tests de sérialisation couverts)
- [x] **T46** ⚡ ⭐⭐⭐ - Ajouter des **tests de fallback** IA/TTS/GPS
  - **Cas à couvrir** : Modèle Gemini principal → fallback, Gemini TTS → Piper, GPS refusé
  - **Validé** : 2026-08-08 (15 nouveaux tests : fallback de modèles Gemini via `MockClient`, orchestration TTS→Piper / Cloud→Nano / GPS refusé, parsing EXIF GPS)
  - **Note** : Injection HTTP (`GeminiApiService(client:)`) et de services (`AudioGuideService(ttsService:, geminiTtsService:, geminiApiService:, nanoService:)`) ajoutées, rétro-compatibles, sans nouvelle dépendance

- [x] **T72** 📈 ⭐ - Ajouter un **disclaimer "contenu généré par IA"** (transparence AI Act UE)
  - **Validé** : 2026-08-12 (bandeau `_AiGeneratedBanner` en haut de l'écran "À propos de cette analyse" dans `about_analysis_screen.dart`)
  - **Note** : Libellé "Contenu généré par IA : le script de cette analyse et sa voix ont été créés automatiquement par un modèle d'intelligence artificielle."

- [x] **T73** 📈 ⭐ - Remplacer l'**icône Ko-fi** (cœur) par la **tasse de café standard**
  - **Validé** : 2026-08-12 (`Icons.favorite_border` → `Icons.local_cafe_outlined` dans `lib/widgets/kofi_button.dart`)

- [x] **T10** 📈 ⭐⭐ - **Sécuriser le stockage des clés API** avec flutter_secure_storage
  - **Validé** : 2026-08-12 (nouveau `lib/services/secure_key_storage.dart` : stockage Android Keystore/iOS Keychain chiffré, migration one-shot depuis `SharedPreferences`, repli propre ; `settings_service.dart` + `audio_guide_service.dart` branchés ; 4 tests de migration ajoutés)
  - **Cible atteinte** : Aucune clé en clair dans `SharedPreferences` (supprimée après migration)

- [x] **T06** 📈 ⭐⭐⭐⭐ - **Refactoriser l’architecture** et nettoyer le code legacy
  - **Fusion de** : clarifier le pipeline + nettoyer les doublons (ex-T08)
  - **Validé** : 2026-08-15
  - **1re tranche (2026-08-12)** : code mort supprimé (`app_settings.dart`, `cloud_provider_picker.dart`, `mode_card.dart`, `mediapipe_service.dart`, `image_utils.dart`), getter `aiModelAttempts` retiré, User-Agent centralisé dans `network_config.dart`
  - **2e tranche (2026-08-15)** : `audio_guide_service.dart` (524 → 445 lignes) découpé en 4 classes dédiées — `GuidePreferencesStore` (persistence prefs/timing), `GuideProgressEstimator` (simulation/estimation de progression), `LocationContextResolver` (GPS EXIF/temps réel + enrichissement Wikipedia), `TtsOrchestrator` (Gemini TTS → fallback Piper) — + `utils/error_sanitizer.dart` partagé
  - **Note** : le fallback IA (cloud → nano) reste dans `audio_guide_service.dart` car il mute l'état `activeProvider` du service lui-même — moins isolable proprement que les autres étapes
  - **Cible atteinte** : pipeline modulaire, responsabilités séparées ; `AudioGuideService` ne fait plus que piloter les transitions d'état et notifier l'UI

---

## 📊 Retours de tests

- **2026-08-15 (T79/T80/T81 — audit sécurité CI)**
  - ✅ **T79/T80/T81 validées** : build release signé et non-debuggable confirmé par un run CI réel ([31897372162](https://github.com/Nohzoh/audio-guide/actions/runs/31897372162))
  - 🐛 **2 bugs trouvés en cours de route, invisibles sans exécution réelle** :
    - R8 (minification, activée par défaut en release) cassait le build sur des classes manquantes tirées par les deps MediaPipe/genai mortes — désactivée explicitement en attendant leur suppression (T82)
    - Le check anti-debuggable ajouté ne vérifiait en fait rien : `aapt` absent du `PATH` du runner CI, `grep` matchait toujours sur une entrée vide → toujours "✅ non debuggable" quel que soit le résultat réel. Corrigé en localisant le binaire sous `$ANDROID_HOME/build-tools`
  - ⚙️ **Environnement Android installé en local** (Java 17 via `openjdk@17`, SDK/NDK via `android-commandlinetools`, `gnu-sed`) — `flutter doctor` vert, variables persistées dans `~/.zshrc`. Permet désormais de reproduire les builds CI localement sans attendre un run GitHub Actions
  - 🐛 **Bug trouvé dans `scripts/build_android_local.sh`** : tous les `sed -i` utilisaient la syntaxe GNU, silencieusement cassée sous le `sed` BSD de macOS (`-i` sans argument fait avaler le script comme suffixe de backup, puis tente d'interpréter le chemin du fichier cible comme un script sed). Corrigé en forçant l'usage de `gsed`
  - ⚠️ **Incident mineur** : un `rm -rf android` pour forcer un bootstrap propre a supprimé des fichiers trackés par git (plugins Kotlin natifs) — restauré immédiatement via `git checkout`, rien perdu
  - ✅ **T83 ajoutée** : pistes pour accélérer le build CI (~6-8 min/run), identifiées en observant les runs

- **2026-08-15 (reprise après pause, T06 — 2e tranche)**
  - ✅ **T10 confirmée terminée** : le code était fait mais jamais committé (interruption faute de crédits) ; committé tel quel après vérification (branchement complet, tests verts)
  - ✅ **T06 terminée** : `audio_guide_service.dart` découpé en `GuidePreferencesStore`, `GuideProgressEstimator`, `LocationContextResolver`, `TtsOrchestrator` + `utils/error_sanitizer.dart` partagé (524 → 445 lignes)
  - ✅ **Validation finale** : `flutter analyze` → 0 erreur ; `flutter test` → 40 tests passés (30 existants + 4 `guide_preferences_store_test.dart` + 6 `guide_progress_estimator_test.dart`)
  - ⚠️ **À noter** : signature GPG des commits cassée sur cette machine (gpg absent, clé de signature introuvable) → gpg installé (`brew install gnupg`), nouvelle clé générée et ajoutée à GitHub, config locale du repo corrigée (`user.name`/`user.email` étaient restés sur les valeurs placeholder du template)

- **2026-08-12 (T06 — 1re tranche)**
  - ✅ **T06 (partiel)** : code mort supprimé (`app_settings.dart`, `cloud_provider_picker.dart`, `mode_card.dart`, `mediapipe_service.dart`, `image_utils.dart`), getter `aiModelAttempts` retiré, User-Agent centralisé dans `network_config.dart`
  - ✅ **Validation finale** : `flutter test` → 30 tests passés, 2026-08-12
  - ⚠️ **Reste T06** : modularisation du pipeline IA/GPS/TTS + extraction de la persistence prefs hors de `audio_guide_service.dart`

- **2026-08-12 (T72 / T73 / T10)**
  - ✅ **T72 validée** : Disclaimer "contenu généré par IA" ajouté à la fiche d'analyse (AI Act)
  - ✅ **T73 validée** : Icône Ko-fi remplacée par la tasse de café (`Icons.local_cafe_outlined`)
  - ✅ **T10 validée** : Clé API Gemini stockée via `flutter_secure_storage` (Keystore/Keychain), migration one-shot depuis SharedPreferences, repli dégradé si stockage sécurisé indisponible
  - ✅ **Validation finale** : `flutter test` → 30 tests passés (26 existants + 4 nouveaux `secure_key_storage_test.dart`), 2026-08-12
  - ⚠️ **À noter** : T74 (détection des lieux) créée suite au test réel du bowling de la Matène ; T75 (style de script) créée suite à une suggestion extérieure

- **2026-08-08 (T41 / T66 / T71 / T47 / T46)**
  - ✅ **T41 validée** : README synchronisé avec le produit actuel (pipeline EXIF/GPS → Wikipedia → IA → TTS)
  - ✅ **T66 validée** : `.withOpacity()` → `.withValues()` (20 occurrences dans 7 fichiers)
  - ✅ **T71 validée** : Doublon `assets/tts/` supprimé, tous les assets déclarés existent
  - ✅ **T47 validée** : Indication de fallback IA/TTS dans la fiche d'analyse (persistée en DB v6)
  - ✅ **T46 validée** : Tests de fallback IA/TTS/GPS (15 tests, voir section Terminé)
  - ✅ **Validation finale** : `flutter analyze` → 0 erreur ; `flutter test` → 26 tests passés (2026-08-08)
  - 🐛 **Bug corrigé** : imports de tests restés sur `package:audio_guide/` après le renommage en `audiolens` (T63) → `flutter test` échouait à la compilation (6 fichiers corrigés)
  - ⚠️ **À noter** : `assets/images/google.png` référencé mais absent (code mort, nettoyé dans T06)
  - ⚠️ **À noter** : `test/widget_test.dart` (template cassé, référence `MyApp` inexistant) supprimé

- **2026-08-02**
  - ✅ **T05 validée** : Message d’erreur clair lors de l’amélioration de voix.
  - ✅ **Date de build validée** : Affichage dans les paramètres OK.
  - ⚠️ **T01 à compléter** : Aucun bouton d’annulation visible pendant la synthèse Piper (traitement trop rapide pour reproduire le freeze). **À retester** avec téléphone en charge + apps actives en arrière-plan.

- **2026-08-02 (T60/T39b/T61/T62)**
  - ✅ **T60 validée** : Tout code Anthropic/OpenAI supprimé (commit `0f13e76`)
  - ✅ **T61 validée** : Fournisseurs cloud alignés avec implémentation (Gemini uniquement)
  - ✅ **T62 validée** : Écrans de téléchargement de modèles supprimés (commit `c37a3f1`)
  - ✅ **T39b validée** : `flutter analyze` → **0 erreurs** (commit `c37a3f1`)

- **2026-08-02 (T42)**
  - ✅ **T42 validée** : Bootstrap documenté + vérification APK ajoutée (commit `82d877a`)

- **2026-08-02 (T63)**
  - ✅ **T63 validée** : Nom du projet aligné sur AudioLens (commit `6afd7b9`) + renaming complet du package Android (Kotlin files, MethodChannels, namespace, applicationId)

- **2026-08-02 (T65)**
  - ✅ **T65 validée** : Imports et variables inutilisés nettoyés (commit `e176b62`)

- **2026-08-02 (T64)**
  - ✅ **T64 validée** : Nettoyage des fichiers untracked + .gitignore (commit `2e3d404`)
