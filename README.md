# 🎧 AudioLens

Une application mobile d'audio guide alimentée par l'IA. Prenez une photo d'un lieu et obtenez instantanément une explication audio.

## Fonctionnalités

- 📸 Capture photo pour identifier les lieux
- 🗺️ Géolocalisation intelligente : coordonnées **EXIF** de la photo, puis **GPS temps réel** en secours
- 📖 Enrichissement **Wikipedia** pour contextualiser le lieu
- 🤖 Analyse par IA : **Gemini API** (cloud) ou **Gemini Nano** (local, sur l'appareil)
- 🔊 Génération audio : **Gemini TTS** (cloud) avec **Piper** en secours (TTS local hors-ligne)
- 🧭 Détection de position : l'appareil a besoin d'un accès aux coordonnées si la photo ne contient pas d'EXIF
- 📜 **Historique** des analyses (SQLite) avec re-lecture et relance
- 🧾 **Fiche technique d'analyse** (modèle, fallback, GPS, durée)
- 📋 **Écran de logs** intégré pour le débogage sur le terrain
- 🆓 Bouton **Ko-fi** pour soutenir le projet

## Architecture

```
Photo → EXIF GPS → GPS temps réel → Wikipedia → IA (vision) → LLM (script) → TTS → Audio
```

Détails et diagrammes du pipeline dans [`ARCHITECTURE.md`](ARCHITECTURE.md).

### Modes disponibles
- **☁️ Cloud** : Utilise votre compte **Google (Gemini API)** — meilleure qualité (~400 mots)
- **📱 Local** : Modèle embarqué **Gemini Nano** — fonctionne sans internet (~180 mots)
- **⚡ Hybride** : Cloud si disponible, **fallback local** sinon

### Fournisseurs IA
| Fournisseur | Localisation | Modèle |
|---|---|---|
| **Gemini API** | Cloud | Configurable (`config.json`, défaut `gemini-3.6-flash`) |
| **Gemini Nano** | Sur l'appareil | Modèle local Android |

### Text-to-Speech
| Moteur | Localisation | Rôle |
|---|---|---|
| **Gemini TTS** | Cloud | Primaire quand une clé API est configurée |
| **Piper** (sherpa-onnx) | Local | Secours automatique + mode hors-ligne |

## Plateformes

Application **Android** uniquement. Buildé automatiquement via **GitHub Actions** à chaque push sur `main`.

## Build

```bash
flutter pub get
flutter build apk --debug
```

## Configuration

La configuration (modèles, fallbacks, TTS, GPS) est centralisée dans [`config.json`](config.json) et chargée à distance par `RemoteConfigService` avec des valeurs par défaut intégrées en secours.
