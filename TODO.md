# Todo list - AudioLens

Tâches terminées et retours de tests archivés dans [`CHANGELOG.md`](CHANGELOG.md).

---

## 📌 Légende
- **Statuts** : ` ` À faire | `~` En cours | `x` Terminé
- **Priorités** : 🔥 Critique | ⚡ Haut | 📈 Moyen | 🌱 Bas
- **Effort** : ⭐ (1-2h) | ⭐⭐ (1/2j) | ⭐⭐⭐ (1j) | ⭐⭐⭐⭐ (2-3j) | ⭐⭐⭐⭐⭐ (5j+)
- **IDs** : séquence unique partagée avec `CHANGELOG.md` — vérifier le plus grand ID des deux fichiers avant d'en créer un nouveau (`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`)
- **Ajouté** : chaque nouvelle tâche porte sa date de création (`**Ajouté** : YYYY-MM-DD`) — permet de repérer les tâches basse priorité qui traînent depuis longtemps. Pas de rétro-remplissage pour les tâches déjà existantes sans date connue.

---

## 🔥 Critique / Bloquant
*Doit être traité avant toute nouvelle fonctionnalité*

*Aucune tâche critique en cours.*

---

## ⚡ Haut impact / Court terme
*À traiter dans les 1-2 semaines*

*Aucune tâche en cours.*

---

## 📈 Moyen impact / Moyen terme
*À traiter dans les 1-2 mois*

- [ ] **T07** 📈 ⭐⭐⭐ - **Centraliser la configuration** (IA, TTS, GPS, etc.)
  - **Où** : `RemoteConfigService` ou nouveau fichier dédié
  - **Objectif** : Éviter la duplication des constants
  - **Preuve concrète (2026-08-15)** : `home_screen.dart:60-61` hardcode `imageQuality: 85, maxWidth: 1280` dans l'appel `ImagePicker` au lieu de lire `RemoteConfigService.current.imageQuality`/`imageMaxWidth` — ces deux réglages remote sont récupérés mais jamais appliqués

- [ ] **T82** 📈 ⭐⭐ - Nettoyage complémentaire post-T06 (code mort restant)
  - **Ajouté** : 2026-08-15 (audit du code existant)
  - **À faire** :
    - Code natif mort : `MediaPipePlugin.kt` toujours enregistré dans `MainActivity.kt` et ses dépendances Gradle (`tasks-genai`, `genai-prompt`) toujours ajoutées en CI (`build-android.yml`), alors que `mediapipe_service.dart` (son seul appelant Dart) a été supprimé en T06 — bloat inutile de l'APK
    - Dépendance inutilisée `google_generative_ai` dans `pubspec.yaml` — jamais importée, tous les appels Gemini sont faits à la main via `http`
    - Bug silencieux dans `gemini_api_service.dart:218-223` : un `if` détecte une "phrase anglaise qui a fuité" du raisonnement du modèle mais son corps est vide (juste un commentaire) — la condition ne filtre rien

- [ ] **T09** 📈 ⭐⭐⭐ - Améliorer la **robustesse du stockage local** et des migrations
  - **Fusion de** : robustesse du stockage + tests de migrations SQLite (ex-T44)
  - **À faire** : Transactions SQLite, rollbacks, tests sur anciennes versions de la base

- [ ] **T45** 📈 ⭐⭐ - Définir une **politique de rétention** pour images, WAV, caches, fichiers temporaires
  - **Intègre** : le nettoyage des fichiers temporaires (ex-T11)

- [ ] **T83** 📈 ⭐⭐ - **Accélérer le build CI Android** (~6-8 min par run aujourd'hui)
  - **Ajouté** : 2026-08-15 (observé en surveillant les runs T79/T80/T81)
  - **Pistes, par impact estimé** :
    - **Aucun cache entre les runs** : Gradle (`~/.gradle`), le SDK/NDK Android et le pub cache Flutter sont retéléchargés et reconstruits à froid à chaque push (`android/` n'est pas committé, cf. bootstrap dans `build-android.yml`). `actions/cache` sur `~/.gradle`, et l'option de cache intégrée de `subosito/flutter-action` pour le SDK Flutter/pub, sont le levier le plus probable
    - **Build multi-architecture inutile** : `flutter build apk` compile pour arm64, armeabi, x86 **et** x86_64 par défaut ; x86/x86_64 ne servent qu'à l'émulateur. `sherpa_onnx` a du vrai code natif par ABI à compiler/lier — restreindre aux ABI réels (`--target-platform android-arm,android-arm64` ou `--split-per-abi`) réduirait le travail natif et la taille de l'APK
    - **Deux versions de NDK installées** (`ndk;27.0.12077973` et `ndk;26.3.11579264`) alors qu'un seul (27) semble utilisé par les plugins (confirmé via build local) — à vérifier si la 26 est encore nécessaire
  - **Non vérifié** : pas mesuré concrètement l'effet de chaque piste, à valider avant/après sur un run réel

- [ ] **T70** 📈 ⭐⭐ - Migrer vers **dio** pour des requêtes HTTP cancellables
  - **Lié à** : T43 (annulations interruptibles)
  - **Pourquoi** : Le package `http` ne supporte pas l'annulation native. `dio` offre `cancel()` sur les requêtes
  - **Services concernés** : GeminiApiService, GeminiTtsService
  - **Impact** : Permettra une vraie interruptibilité des appels cloud

- [ ] **T74** 📈 ⭐⭐⭐ - Améliorer la **détection des lieux et de leur histoire**
  - **Contexte** : Test réel (bowling de la Matène, 2026-08-12) — l'appli n'a pas évoqué le tournage des *Tontons flingueurs* : le lieu n'a pas d'article Wikipedia géolocalisé dans le rayon de 200 m, et le nom du commerce (POI) n'est jamais récupéré
  - **À faire** :
    - Récupérer le **nom du lieu** (POI OpenStreetMap via Overpass/Nominatim : `leisure=bowling_alley`, `tourism=*`, `historic=*`, `amenity=*`) et l'ajouter au contexte GPS
    - Wikipedia : rayon plus large (via `config.json`), recherche **full-text par nom de lieu + ville** en plus du geosearch, fallback fr → en
    - Prompt IA : inciter à identifier le lieu réel via l'adresse/les enseignes et à chercher les faits marquants (films, événements, personnalités)
  - **Cible** : `wikipedia_service.dart`, `location_service.dart`, `audio_guide_service.dart`, prompt `gemini_api_service.dart`

- [ ] **T75** 📈 ⭐⭐ - Ajouter une **option de style de script** (suggestion d'un ami)
  - **Exemples** : style "académique/historique" vs style qui met en avant les **anecdotes et le storytelling**
  - **À faire** : sélecteur de style dans les paramètres (et/ou onboarding), transmission du style au prompt IA (`gemini_api_service.dart` + `gemini_nano_service.dart`), persistance via `SettingsService`
  - **Lié à** : T48 (variantes de ton) — envisager une fusion pour éviter le doublon

- [ ] **T76** 📈 ⭐⭐⭐⭐ - **Découper le script en morceaux** pour démarrer la lecture audio plus vite
  - **Ajouté** : 2026-08-15
  - **Contexte** : ~30s (parfois plus) d'attente entre l'affichage du texte et le début de la lecture audio. `GeminiTtsService.speak()` synthétise **tout le script en un seul appel HTTP bloquant** avant de jouer quoi que ce soit (`gemini_tts_service.dart:36-95`) ; `TtsService` (Piper) a un problème similaire malgré son découpage en phrases interne (`_splitSentences`), qui ne sert aujourd'hui qu'au calcul de progression, pas à un démarrage anticipé
  - **Piste** : découper le script (phrases/paragraphes), synthétiser le 1er morceau, lancer sa lecture immédiatement, synthétiser la suite pendant la lecture, enchaîner. Le channel natif `audio_guide/audio_player` (`AudioPlayerPlugin.kt`) résout déjà `playWav` seulement à la fin de la lecture — l'enchaînement séquentiel semble faisable **côté Dart sans changement natif** (produire le morceau suivant pendant que le précédent joue)
  - **Points d'attention** : découpage aux frontières de phrases pour rester naturel à l'oreille ; `CancelToken` doit rester efficace au milieu de la séquence ; le flag `stepProgress = -1.0` (indéterminé) sur l'étape `synthesizing` pourrait devenir une vraie progression (morceau N/M)
  - **Cible** : `gemini_tts_service.dart`, `tts_service.dart`, `tts_orchestrator.dart`

---

## 🌱 Bas impact / Long terme
*Backlog pour améliorations futures*

- [ ] **T77** 🌱 ⭐⭐⭐⭐⭐ - **Portage iOS** — faire fonctionner AudioLens sur iPhone
  - **Ajouté** : 2026-08-15
  - **Contexte** : projet 100% Android aujourd'hui, `ios/` n'existe même pas — il faudra générer le scaffold (`flutter create --platforms=ios .`)
  - **Blocages à trancher avant de commencer** :
    - **Gemini Nano n'a pas d'équivalent iOS** (`GeminiNanoPlugin.kt` s'appuie sur l'API Android AICore) — aucune solution native équivalente identifiée. Décision à prendre : mode local désactivé sur iOS (cloud uniquement) ou remplacement par un autre modèle on-device ?
    - **Compte développeur Apple** (99$/an) nécessaire pour signer/distribuer (TestFlight ou sideload), contrairement à l'APK Android actuel distribué directement en sortie de GitHub Actions
    - **Support iOS de `sherpa_onnx`** (Piper local) à vérifier avant de s'engager — pas confirmé depuis cet environnement
  - **Travail natif à dupliquer en Swift** (3 MethodChannels actifs) :
    - `audio_guide/location` (`LocationPlugin.kt`) → CoreLocation + reverse geocoding, permissions `Info.plist`
    - `audio_guide/audio_player` (`AudioPlayerPlugin.kt`, `MediaPlayer`) → `AVAudioPlayer`
    - `audio_guide/gemini_nano` (`GeminiNanoPlugin.kt`) → bloqué par le point Gemini Nano ci-dessus
  - **CI** : nouveau workflow (`build-ios.yml`), runner macOS (payant/limité sur GitHub Actions), certificats/provisioning en secrets
  - **Recommandation** : ne pas traiter comme une tâche unique — découper en sous-tâches une fois les blocages ci-dessus tranchés

- [ ] **T12** 🌱 ⭐⭐⭐ - Fusionner la **galerie et l’historique**
  - **Option** : Rendre l’historique la vue principale avec accès à la nouvelle analyse et à la config

- [ ] **T13** 🌱 ⭐⭐ - Permettre la **re-demande d’une ancienne analyse échouée** depuis l’historique

- [ ] **T14** 🌱 ⭐⭐ - Ajouter un **mode d’affichage de lecture** avec la photo normale (au lieu du texte superposé)

- [ ] **T15** 🌱 ⭐ - Permettre la **configuration de la vitesse de lecture**

- [ ] **T16** 🌱 ⭐⭐⭐ - Ajouter un **mode sans TTS** (localisation + analyse + génération du script uniquement), avec **génération audio à la demande** ensuite
  - **Contexte** : demande utilisateur — un réglage pour désactiver la génération audio automatique après l'analyse, avec possibilité de demander la synthèse audio plus tard depuis une entrée "script seul" de l'historique
  - **Bonne nouvelle** : le modèle de données le permet déjà sans migration — `HistoryEntry.audioPath` est nullable et `hasAudio` teste déjà `audioPath != null` (`history_service.dart`)
  - **À faire** :
    - Réglage dans `SettingsService` (persistance `SharedPreferences`, sur le modèle de `showKofiButton`)
    - `AudioGuideService.analyzeAndPlay` : si le réglage est actif, s'arrêter après l'étape `analyzing` (skip `TtsOrchestrator.speak`), état final différent de `speaking` (ex. `scriptReady`)
    - Écran historique (`history_screen.dart`) : affichage distinct pour une entrée sans `audioPath`, bouton "Générer l'audio" qui relance uniquement l'étape TTS (`TtsOrchestrator` + `script` déjà en base) sur le script existant, sans refaire GPS/Wikipedia/IA
  - **Lié à** : T13 (re-demande d'une analyse échouée) et T50 (relancer avec nouveau style/voix) — mécanique de "relance partielle" voisine, à regarder ensemble
  - **Note (2026-08-15)** : `HistoryService` a déjà le pattern `pending`/`failed`/`addPendingEntry`/`completeEntry` — bonne base à réutiliser plutôt qu'un nouveau mécanisme

- [ ] **T17** 🌱 ⭐⭐ - Ajouter un **mode d’analyse plus détaillé ou plus court**

- [ ] **T18** 🌱 ⭐⭐⭐ - Permettre le **choix de langue/style de voix**

- [ ] **T19** 🌱 ⭐⭐ - Ajouter le **partage/export** du texte ou de l’audio

- [ ] **T20** 🌱 ⭐⭐⭐ - **Améliorer l’expérience hors ligne**
  - **Fusion de** : reprise/cache + badge/explication des fonctions disponibles/indisponibles (ex-T52)

- [ ] **T78** 🌱 ⭐⭐⭐⭐ - **Capture différée** : photo + GPS maintenant, analyse (cloud) plus tard
  - **Ajouté** : 2026-08-15
  - **Contexte** : demande utilisateur — économiser sa conso data sans se rabattre sur les modèles locaux (qualité moindre) : capturer photo + position tout de suite, lancer l'analyse cloud plus tard (ex. une fois sur wifi)
  - **Différent de T20** : T20 dégrade gracieusement quand le réseau manque ; ici on **choisit délibérément** de différer les étapes réseau, réseau disponible ou non
  - **Point d'attention** : même la résolution GPS actuelle fait un appel réseau (reverse geocoding Nominatim dans `LocationService._reverseGeocode`). Pour une capture vraiment 100% hors-ligne, ne stocker à la capture que les **coordonnées brutes** (EXIF ou fix GPS), et différer reverse geocoding + Wikipedia + IA + TTS à la relance — `LocationContextResolver.resolve()` (T06) devrait accepter des coordonnées déjà connues en entrée plutôt que de toujours repartir d'un fichier image
  - **À faire** :
    - Nouveau statut `HistoryEntry`/`AnalysisStatus` pour "capturé, analyse non lancée" (distinct de `pending`, qui semble désigner l'analyse en cours)
    - Écran de capture : bouton "Capturer sans analyser" à côté du flux actuel (`home_screen.dart:_pickImage` appelle `analyzeAndPlay` directement aujourd'hui)
    - Écran historique : bouton "Lancer l'analyse" sur une entrée capturée, qui déclenche le pipeline complet à partir des coordonnées déjà stockées
  - **Lié à** : T16 (génération audio à la demande) — même mécanique sous-jacente de "relance partielle du pipeline depuis l'historique", à concevoir ensemble plutôt que deux systèmes séparés
  - **Note (2026-08-15)** : comme pour T16, `HistoryService` a déjà le pattern `pending`/`failed`/`addPendingEntry`/`completeEntry` — bonne base à réutiliser

- [ ] **T21** 🌱 ⭐⭐ - Ajouter des **interactions plus riches** dans l’écran de lecture

- [ ] **T22** 🌱 ⭐ - Permettre la **mise en pause** pendant la lecture audio depuis la galerie

- [ ] **T23** 🌱 ⭐⭐⭐ - Améliorer l’**accessibilité visuelle**
  - **À découper en sous-tâches** : Contrastes, tailles de boutons, lisibilité

- [ ] **T24** 🌱 ⭐⭐⭐⭐ - Préparer une **base d’internationalisation** (i18n)

- [ ] **T48** 🌱 ⭐⭐ - Ajouter des **variantes de ton d’analyse** (enfant, expert, storytelling, synthétique)

- [ ] **T49** 🌱 ⭐⭐ - Permettre de **choisir la langue de sortie** indépendamment de la langue de l’interface

- [ ] **T50** 🌱 ⭐⭐⭐ - **Relancer une ancienne analyse** avec un nouveau style/longueur/langue/modèle

- [ ] **T51** 🌱 ⭐⭐⭐ - Ajouter des **favoris ou collections de visites** (ex. Louvre, Rome, voyage personnel)

- [ ] **T67** 🌱 ⭐⭐⭐ - **Extraire tous les textes statiques** pour l’i18n
  - Préparer le terrain pour T24 (internationalisation)
  - Utiliser le package `intl` (déjà présent)
  - Créer des fichiers `.arb` pour français/anglais

- [ ] **T68** 🌱 ⭐⭐⭐ - **Étendre la couverture de tests** aux services non testés
  - **Mis à jour** : 2026-08-15 — `MediaPipeService` retiré de la cible (supprimé en T06) ; `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService` ajoutés (nés du refactor T06, encore sans test dédié — `HistoryService` en particulier n'a aucun test, pertinent pour T09)
  - Cible : `LocationService`, `WikipediaService`, `ExifLocationService`, `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService`
  - Objectif : 80% de couverture sur les services critiques

- [ ] **T69** 🌱 ⭐⭐ - **Documenter l’architecture** et les flux
  - Ajouter un fichier `ARCHITECTURE.md`
  - Diagramme : `Photo → AIService → TTS → Audio`
  - Diagramme : `Géolocalisation (EXIF → GPS → Wikipedia)`

---

## 📝 À compléter au fil du projet

- [ ] **T34** - Ajouter de **nouvelles idées d’amélioration** (issue tracker ?)
- [ ] **T35** - **Prioriser les tâches** par impact / effort (tableau ROI ?)
- [ ] **T36** - **Suivre l’avancement** des implémentations (tableau Kanban ?)
- [ ] **T37** - Ajouter une **baseline de couverture de tests** et la conserver
