# Copilot instructions for Audio Guide

## Project context
- This repository is a Flutter mobile app for AI-powered audio guides.
- The app runs on-device and in the field, often without direct access to logcat.
- Debug information should be usable from the in-app logs screen whenever possible.

## Debugging conventions
- Prefer AppLogger over print/debugPrint for runtime diagnostics.
- Use the existing log categories when relevant:
  - INFO for general flow
  - ERROR for failures
  - TTS for speech generation/playback
  - AI for analysis pipeline events
  - GPS for location events
  - DB for persistence/storage issues
- When adding new behavior, consider whether it should emit a log entry for field debugging.
- Never log secrets, API keys, or sensitive user data.
- Keep log messages short, structured, and actionable.

## UX expectations
- Prefer user-visible feedback over silent failures.
- When an action can take time or block the UI, provide a cancel or fallback path if possible.
- Avoid making the app feel frozen; keep the UI responsive during long operations.
- For failures, surface a clear message in the UI and log the details for debugging.

## Implementation preferences
- Keep the architecture modular: screens, services, and data/persistence should remain separated.
- Prefer small, focused changes over large rewrites.
- When improving the app, think about real-world mobile usage: no laptop, limited connectivity, offline fallback, and field debugging.
- Preserve compatibility with the existing history and logs flows.

## When working on this project
- If a bug affects on-device behavior without logcat access, think first about how to expose it through AppLogger and the logs screen.
- If a new feature changes the analysis pipeline, ensure it remains observable and debuggable.
- If a change impacts TTS, AI, GPS, or history, add relevant logs to help diagnose issues on the field.
- When adding or changing dependencies, verify that their licenses are compatible with the project’s chosen licensing approach before finalizing the change.
