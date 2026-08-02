# 🎧 Audio Guide

Une application mobile d'audio guide alimentée par l'IA. Prenez une photo d'un lieu et obtenez instantanément une explication audio.

## Fonctionnalités

- 📸 Capture photo pour identifier les lieux
- 🤖 Analyse par IA (locale ou cloud)
- 🔊 Génération audio du commentaire
- 📱 Fonctionne hors-ligne (avec modèles locaux)
- ☁️ Support **Gemini API** (Google)

## Architecture

```
Photo → Vision Model → LLM (script) → TTS → Audio
```

### Modes disponibles
- **☁️ Cloud** : Utilise votre compte **Google (Gemini API)**
- **📱 Local** : Modèles embarqués (Gemini Nano), fonctionne sans internet
- **⚡ Hybride** : Cloud si disponible, local sinon

## Build

```bash
flutter pub get
flutter build apk --debug
```

L'APK est automatiquement buildé via GitHub Actions à chaque push sur `main`.
