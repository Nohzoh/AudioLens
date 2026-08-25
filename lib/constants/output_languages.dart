/// #130: languages the narration can be generated in, independent of the
/// app's own interface language.
///
/// Display name -> BCP-47 locale code. The display name is used in three
/// places at once: as the label shown in Settings, as the persisted
/// `SettingsService.outputLanguage` value, and verbatim as the language
/// name given to the model in the analysis prompt (Gemini reliably follows
/// "respond in Español" even though the rest of the prompt is French) — one
/// canonical string, no separate translation table to keep in sync. The
/// locale code is only needed by [NativeTtsService], which speaks live and
/// therefore needs a real BCP-47 code, not just a display name.
///
/// Declaration order here is also the order offered in Settings — Dart's
/// const map literals preserve insertion order.
const Map<String, String> outputLanguageLocales = {
  'Français': 'fr-FR',
  'English': 'en-US',
  'Español': 'es-ES',
  'Deutsch': 'de-DE',
  'Italiano': 'it-IT',
  'Português': 'pt-PT',
  'Nederlands': 'nl-NL',
  '日本語': 'ja-JP',
};

/// Matches the narration's de-facto behavior before this setting existed —
/// kept as French rather than switching to the device locale, so existing
/// installs don't get a surprise change in narration language on upgrade.
const defaultOutputLanguage = 'Français';
