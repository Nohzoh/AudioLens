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

- [ ] **T75** 📈 ⭐⭐ - Ajouter une **option de style de script** (suggestion d'un ami)
  - **Exemples** : style "académique/historique" vs style qui met en avant les **anecdotes et le storytelling**
  - **À faire** : sélecteur de style dans les paramètres (et/ou onboarding), transmission du style au prompt IA (`gemini_api_service.dart` + `gemini_nano_service.dart`), persistance via `SettingsService`
  - **Lié à** : T48 (variantes de ton) — envisager une fusion pour éviter le doublon

---

## 🌱 Bas impact / Long terme
*Backlog pour améliorations futures*

- [ ] **T84** 🌱 ⭐⭐⭐⭐⭐ - **Publication sur le Play Store**
  - **Ajouté** : 2026-08-15
  - **Déjà acquis** (bon point de départ) : signature release fonctionnelle (T79), `allowBackup=false` (T80), clé API protégée par allowlist (T81), stockage sécurisé de la clé (T10), disclaimer "contenu généré par IA" déjà dans l'appli (T72), `applicationId` stable `com.audiolens.audiolens` (T63)
  - **Décisions/démarches non techniques à faire d'abord** :
    - Créer un **compte développeur Google Play** (25$, paiement unique) — prérequis absolu, aucune tâche technique ne peut être testée en réel avant
    - **Politique de confidentialité** hébergée publiquement et un lien à fournir dans la fiche Play Console — obligatoire vu les permissions demandées (caméra, localisation) et le fait que photos + position sont envoyées à l'API Gemini (partage de données à un tiers)
    - **Formulaire "Data safety"** de Play Console : déclarer précisément quelles données sont collectées/partagées (photo, GPS, script) et avec qui (Google Gemini)
    - **Déclaration des permissions sensibles** (`ACCESS_FINE_LOCATION`, `CAMERA`) — justification demandée par Google, la localisation est particulièrement scrutée
    - Vérifier si les **politiques Play sur les apps génératives IA** imposent des déclarations supplémentaires au-delà du disclaimer déjà présent (T72)
  - **À faire, technique** :
    - **AAB au lieu d'APK** : Play Store exige un `.aab` (`flutter build appbundle --release`), pas l'APK actuel — nouveau job ou étape CI dédiée
    - **Stratégie de versionCode** : `pubspec.yaml` est figé à `0.1.0+1` depuis le début, jamais incrémenté — chaque upload Play Console doit avoir un `versionCode` strictement croissant, à automatiser (ex. `versionCode` basé sur le numéro de run CI ou un compteur committé)
    - **Icône d'application manquante** : `assets/images/` est vide (juste un `.gitkeep`) — l'appli tourne aujourd'hui avec l'icône Flutter par défaut (`android/app/src/main/res/mipmap-*/ic_launcher.png`, régénérée à chaque bootstrap CI). Un vrai icône est indispensable avant toute soumission
    - **Assets de fiche store** : description courte/longue, catégorie, graphique de mise en avant, captures d'écran
    - **Automatiser l'upload** vers Play Console depuis la CI (ex. action `r0adkll/upload-google-play`, clé de compte de service en secret) — à faire seulement une fois le compte développeur créé
  - **Recommandation** : ne pas traiter comme une tâche unique — les démarches non techniques (compte, politique de confidentialité, data safety) bloquent et doivent être faites avant toute automatisation CI

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
  - **Mis à jour** : 2026-08-15 — `MediaPipeService` retiré de la cible (supprimé en T06) ; `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService` ajoutés (nés du refactor T06, encore sans test dédié — `HistoryService` en particulier n'a aucun test, pertinent pour T09)
  - Cible : `LocationService`, `WikipediaService`, `ExifLocationService`, `HistoryService`, `TtsOrchestrator`, `LocationContextResolver`, `RemoteConfigService`
  - Objectif : 80% de couverture sur les services critiques

---

## 📝 À compléter au fil du projet

- [ ] **T34** - Ajouter de **nouvelles idées d’amélioration** (issue tracker ?)
- [ ] **T35** - **Prioriser les tâches** par impact / effort (tableau ROI ?)
- [ ] **T36** - **Suivre l’avancement** des implémentations (tableau Kanban ?)
- [ ] **T37** - Ajouter une **baseline de couverture de tests** et la conserver
