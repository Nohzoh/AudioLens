# Todo list - AudioLens

Tâches terminées et retours de tests archivés dans [`CHANGELOG.md`](CHANGELOG.md).

---

## 📌 Légende
- **Statuts** : ` ` À faire | `~` En cours | `x` Terminé
- **Priorités** : 🔥 Critique | ⚡ Haut | 📈 Moyen | 🌱 Bas
- **Effort** : ⭐ (1-2h) | ⭐⭐ (1/2j) | ⭐⭐⭐ (1j) | ⭐⭐⭐⭐ (2-3j) | ⭐⭐⭐⭐⭐ (5j+)
- **IDs** : séquence unique partagée avec `CHANGELOG.md` — vérifier le plus grand ID des deux fichiers avant d'en créer un nouveau (`grep -o 'T[0-9]\+' TODO.md CHANGELOG.md`)

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
