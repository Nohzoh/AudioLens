# Agent Instructions for Audio Guide

## Project Context
This is a **Flutter mobile app** for AI-powered audio guides. The app:
- Runs **on-device** in real-world conditions (museums, outdoor visits)
- Often operates **without direct logcat access**
- Must remain **responsive** during long operations (AI analysis, TTS, GPS)
- Relies on **in-app logs screen** for field debugging

**Key technologies**: Flutter, Dart, Gemini Nano/API, Piper TTS, SQLite, EXIF/GPS, Wikipedia API.

---

## Global Guidelines for All Agents

### Code Quality
- Keep the **architecture modular**: separate concerns between screens, services, and persistence
- Prefer **small, focused changes** over large rewrites
- Maintain **backward compatibility** with existing history and logs
- Follow **existing patterns** before introducing new ones

### Debugging & Logging
- **Always use `AppLogger`** instead of `print`/`debugPrint`
- **Log categories** to use when relevant:
  - `INFO` — general flow
  - `ERROR` — failures
  - `TTS` — speech generation/playback
  - `AI` — analysis pipeline events
  - `GPS` — location events
  - `DB` — persistence/storage issues
- **Never log secrets**: API keys, tokens, or sensitive user data
- **Keep logs** short, structured, and actionable
- Ask: *"Can this issue be diagnosed from the in-app logs screen?"*

### User Experience
- **Never fail silently** — surface errors clearly in the UI
- **Provide feedback** for long operations (progress indicators, cancel buttons)
- **Keep the UI responsive** — avoid blocking the main thread
- **Fallback gracefully** — if a feature fails, offer an alternative or clear error
- **Mobile-first mindset**: assume limited connectivity, offline use, no laptop for debugging

### Project-Specific Considerations
- **AI Pipeline** (Gemini Nano/API): changes must remain observable and debuggable
- **TTS** (Piper/Gemini TTS): add logs for playback issues, latency, or failures
- **GPS/Location**: handle permission denials, timeouts, and EXIF fallback
- **Dependencies**: verify license compatibility (project uses open-source licenses)
- **Offline support**: prioritize local-first approaches with cloud fallback

---

## Agent-Specific Notes

### For Coding Agents (Vibe, Cursor, etc.)
- Read relevant files **before editing** (the file itself, its tests, callers)
- Match **existing code style** (indentation, naming, error handling)
- Prefer **minimal changes** — don’t refactor unrelated code
- **Test your changes** where possible
- Use **type-safe patterns** (Dart is strongly typed)

### For GitHub Copilot / Copilot Chat
- Follow the **debugging conventions** strictly (AppLogger usage)
- Remember: **no logcat access in production** — logs must be visible in-app
- Prioritize **field usability** over development convenience

### For Review Agents
- Check that **new features are observable** via logs or UI
- Verify **error paths** are handled and user-visible
- Ensure **offline scenarios** are considered
- Confirm **license compatibility** for new dependencies

---

## Quick Reference
| Area | Key Files | Log Category |
|------|-----------|--------------|
| AI Analysis | `lib/services/gemini_*`, `ai_service.dart` | `AI` |
| TTS | `lib/services/tts_service.dart`, `gemini_tts_service.dart` | `TTS` |
| GPS/Location | `lib/services/location_service.dart`, `exif_location_service.dart` | `GPS` |
| Logging | `lib/utils/app_logger.dart` | `INFO`/`ERROR` |
| Storage | `lib/services/history_service.dart` | `DB` |
