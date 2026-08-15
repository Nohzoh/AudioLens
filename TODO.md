# Todo list - AudioLens

---

## 📌 Légende
- **Statuts** : ` ` À faire | `~` En cours | `x` Terminé
- **Priorités** : 🔥 Critique | ⚡ Haut | 📈 Moyen | 🌱 Bas
- **Effort** : ⭐ (1-2h) | ⭐⭐ (1/2j) | ⭐⭐⭐ (1j) | ⭐⭐⭐⭐ (2-3j) | ⭐⭐⭐⭐⭐ (5j+)

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

- [ ] **T09** 📈 ⭐⭐⭐ - Améliorer la **robustesse du stockage local** et des migrations
  - **Fusion de** : robustesse du stockage + tests de migrations SQLite (ex-T44)
  - **À faire** : Transactions SQLite, rollbacks, tests sur anciennes versions de la base

- [ ] **T45** 📈 ⭐⭐ - Définir une **politique de rétention** pour images, WAV, caches, fichiers temporaires
  - **Intègre** : le nettoyage des fichiers temporaires (ex-T11)

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

---

## 🌱 Bas impact / Long terme
*Backlog pour améliorations futures*

- [ ] **T12** 🌱 ⭐⭐⭐ - Fusionner la **galerie et l’historique**
  - **Option** : Rendre l’historique la vue principale avec accès à la nouvelle analyse et à la config

- [ ] **T13** 🌱 ⭐⭐ - Permettre la **re-demande d’une ancienne analyse échouée** depuis l’historique

- [ ] **T14** 🌱 ⭐⭐ - Ajouter un **mode d’affichage de lecture** avec la photo normale (au lieu du texte superposé)

- [ ] **T15** 🌱 ⭐ - Permettre la **configuration de la vitesse de lecture**

- [ ] **T16** 🌱 ⭐⭐ - Ajouter un **mode sans TTS** (localisation + analyse + génération du script uniquement)

- [ ] **T17** 🌱 ⭐⭐ - Ajouter un **mode d’analyse plus détaillé ou plus court**

- [ ] **T18** 🌱 ⭐⭐⭐ - Permettre le **choix de langue/style de voix**

- [ ] **T19** 🌱 ⭐⭐ - Ajouter le **partage/export** du texte ou de l’audio

- [ ] **T20** 🌱 ⭐⭐⭐ - **Améliorer l’expérience hors ligne**
  - **Fusion de** : reprise/cache + badge/explication des fonctions disponibles/indisponibles (ex-T52)

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
  - Cible : LocationService, WikipediaService, ExifLocationService, MediaPipeService
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

---

## ✅ Terminé

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
  - **Note** : `assets/images/google.png` référencé dans `app_settings.dart` mais absent (code mort, à nettoyer dans T06)
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
  - ⚠️ **À noter** : `assets/images/google.png` référencé mais absent (code mort, à nettoyer dans T06)
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
