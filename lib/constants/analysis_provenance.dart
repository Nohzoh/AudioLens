/// #138: stamped onto every `HistoryEntry` at completion time, alongside
/// the existing `aiModel`/`ttsModel` fields, so an old entry's exact
/// prompt/output-schema shape is recorded — without this, an entry
/// generated months ago becomes hard to reproduce or reason about once
/// the prompts (cloud and on-device) evolve.
///
/// Bump this deliberately whenever the prompt structure or the
/// title/script JSON output shape meaningfully changes in
/// `gemini_api_service.dart`, `gemini_nano_service.dart`, or
/// `GeminiNanoPlugin.kt` — not on unrelated changes to those files.
const promptSchemaVersion = 'v1';
