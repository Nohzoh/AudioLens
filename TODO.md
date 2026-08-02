# Todo list - Audio Guide

---

## 📌 Légende
- **Statuts** : ` ` À faire | `~` En cours | `x` Terminé
- **Priorités** : 🔥 Critique | ⚡ Haut | 📈 Moyen | 🌱 Bas
- **Effort** : ⭐ (1-2h) | ⭐⭐ (1/2j) | ⭐⭐⭐ (1j) | ⭐⭐⭐⭐ (2-3j) | ⭐⭐⭐⭐⭐ (5j+)

---

## 🔥 Critique / Blocant
*Doit être traité avant toute nouvelle fonctionnalité*



- [x] **T01** 🔥 ⭐⭐⭐ - Corriger le **freeze du téléphone** lors du lancement de Piper + ajouter un **bouton d’annulation**
  - **Lié à** : T43 (annulations interruptibles)
  - **Validé** : Commit `37f4ccd` (bouton d'annulation + état cancelling + timeout)
  - **Note** : Bouton d'annulation fonctionnel pendant la synthèse. Freeze résiduel nécessite T43 pour annulation interruptible.

---

## ⚡ Haut impact / Court terme
*À traiter dans les 1-2 semaines*

- [ ] **T41** ⚡ ⭐ - Synchroniser le **README** avec le produit actuel
  - **Contenu à mettre à jour** : Gemini Nano/API, TTS Gemini/Piper, état Android, architecture

- [x] **T43** ⚡ ⭐⭐⭐ - Rendre les **annulations vraiment interruptibles** (appels HTTP, étapes longues du pipeline)
  - **Lié à** : T01 (freeze Piper)
  - **Validé** : Commit `4a9b211` (CancelToken system, checks avant chaque étape, passage aux services TTS)
  - **Note** : Annulations basées sur checks avant chaque étape. HTTP natif non supporté (nécessite package dio).

- [ ] **T46** ⚡ ⭐⭐⭐ - Ajouter des **tests de fallback** IA/TTS/GPS
  - **Cas à couvrir** : Modèle Gemini principal → fallback, Gemini TTS → Piper, GPS refusé
  - **Dépend de** : T02, T03 (déjà terminés)

- [ ] **T47** ⚡ ⭐⭐ - Ajouter une **fiche technique d’analyse**
  - **Contenu** : Modèle utilisé, fallback, GPS, Wikipedia, durée, source
  - **Dépend de** : T46

- [ ] **T63** ⚡ ⭐ - **Unifier le nom du projet**
  - Choisir entre "AudioLens" ou "Audio Guide"
  - Mettre à jour `main.dart`, `pubspec.yaml`, `README.md`, assets
  - **Recommandation** : Garder **"Audio Guide"** (plus clair)

- [ ] **T66** ⚡ ⭐ - Remplacer tous les **.withOpacity()** par **.withValues()**
  - Fichiers concernés : `history_screen.dart`, `home_screen.dart`, `player_screen.dart`, `onboarding_screen.dart`, `settings_screen.dart`, widgets/*

- [ ] **T66** ⚡ ⭐ - Nettoyer la **configuration des assets** dans pubspec.yaml
  - Supprimer les doublons (`assets/tts/` apparaît 2 fois)
  - Vérifier que tous les assets existent

---

## 📈 Moyen impact / Moyen terme
*À traiter dans les 1-2 mois*

- [ ] **T06** 📈 ⭐⭐⭐⭐ - **Refactoriser l’architecture** et nettoyer le code legacy
  - **Fusion de** : T06 (clarifier pipeline) + T08 (nettoyer doublons)
  - **Cible** : Pipeline IA/GPS/TTS modulaire, responsabilités séparées (screens/services/persistence)

- [ ] **T07** 📈 ⭐⭐⭐ - **Centraliser la configuration** (IA, TTS, GPS, etc.)
  - **Où** : `RemoteConfigService` ou nouveau fichier dédié
  - **Objectif** : Éviter la duplication des constants

- [ ] **T09** 📈 ⭐⭐⭐ - Améliorer la **robustesse du stockage local** et des migrations
  - **Fusion de** : T09 (robustesse) + T44 (tests migrations SQLite)
  - **À faire** : Transactions SQLite, rollbacks, tests sur anciennes versions de la base

- [ ] **T10** 📈 ⭐⭐ - **Sécuriser le stockage des clés API** avec flutter_secure_storage
  - Remplacer `SharedPreferences` pour `gemini_api_key`
  - Ajouter la dépendance `flutter_secure_storage`
  - Migrer les clés existantes
  - **Cible** : Aucune clé en clair dans `SharedPreferences`

- [ ] **T45** 📈 ⭐⭐ - Définir une **politique de rétention** pour images, WAV, caches, fichiers temporaires
  - **Lié à** : T11 (nettoyer fichiers temporaires → intégré ici)

- [ ] **T70** 📈 ⭐⭐ - Migrer vers **dio** pour des requêtes HTTP cancellables
  - **Lié à** : T43 (annulations interruptibles)
  - **Pourquoi** : Le package `http` ne supporte pas l'annulation native. `dio` offre `cancel()` sur les requêtes
  - **Services concernés** : GeminiApiService, GeminiTtsService
  - **Impact** : Permettra une vraie interruptibilité des appels cloud

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
  - **Fusion de** : T20 (reprise/cache) + T52 (badge + explication des fonctions disponibles/indisponibles)

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

---

## 📊 Retours de tests

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
