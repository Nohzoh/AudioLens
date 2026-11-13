import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/output_languages.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/genai_tts_service.dart';
import '../services/guide_preferences_store.dart';
import '../services/settings_service.dart';

/// #522: choice of the on-device generative voice used when the Gemini
/// voice is not available — automatic (by gender), one of the installed
/// voices of the output language, or off. Hidden on phones without any.
class GenerativeVoiceSetting extends StatefulWidget {
  const GenerativeVoiceSetting({super.key, this.loadVoices, this.downloadVoice});

  /// Lists the voices for a locale; injectable for tests.
  final Future<List<GenAiVoice>> Function(String locale)? loadVoices;

  /// #552: downloads a voice, true when installed; injectable for tests.
  final Future<bool> Function(String locale, String name)? downloadVoice;

  @override
  State<GenerativeVoiceSetting> createState() => _GenerativeVoiceSettingState();
}

class _GenerativeVoiceSettingState extends State<GenerativeVoiceSetting> {
  Future<List<GenAiVoice>>? _voices;
  String? _locale;

  /// #552: the voice being downloaded, if any.
  String? _downloading;

  Future<void> _download(String name) async {
    final locale = _locale;
    if (locale == null || _downloading != null) return;
    setState(() => _downloading = name);
    final download =
        widget.downloadVoice ?? context.read<AudioGuideService>().downloadGenerativeVoice;
    final ok = await download(locale, name);
    if (!mounted) return;
    setState(() {
      _downloading = null;
      _voices = null;
      _locale = null; // reload the list
    });
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.generativeVoiceDownloadFailed)),
      );
    }
  }

  void _load(String locale) {
    if (_locale == locale && _voices != null) return;
    _locale = locale;
    final loader = widget.loadVoices ?? context.read<AudioGuideService>().generativeVoices;
    _voices = loader(locale);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final language = context.watch<SettingsService>().outputLanguage;
    _load(outputLanguageLocales[language] ?? 'fr-FR');
    final guide = context.watch<AudioGuideService>();

    return FutureBuilder<List<GenAiVoice>>(
      future: _voices,
      builder: (context, snapshot) {
        final voices = snapshot.data ?? const <GenAiVoice>[];
        final installed = voices.where((v) => v.status == 'available').toList();
        final downloadable = voices.where((v) => v.status == 'downloadable').toList();
        if (installed.isEmpty && downloadable.isEmpty) return const SizedBox.shrink();
        String gender(GenAiVoice v) => switch (v.gender) {
              'female' => l10n.generativeVoiceFemale,
              'male' => l10n.generativeVoiceMale,
              _ => '',
            };
        final choice = guide.generativeVoice;
        // A voice picked for another language counts as automatic here.
        final selected = choice == generativeVoiceOff || installed.any((v) => v.name == choice)
            ? choice
            : generativeVoiceAuto;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.generativeVoiceTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l10n.generativeVoiceExplanation, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.generativeVoiceAuto),
                    selected: selected == generativeVoiceAuto,
                    onSelected: (_) => guide.setGenerativeVoice(generativeVoiceAuto),
                  ),
                  for (final v in installed)
                    ChoiceChip(
                      label: Text([GenerativeVoiceSettingNames.short(v.name), gender(v)]
                          .where((s) => s.isNotEmpty)
                          .join(' · ')),
                      selected: selected == v.name,
                      onSelected: (_) => guide.setGenerativeVoice(v.name),
                    ),
                  ChoiceChip(
                    label: Text(l10n.generativeVoiceOff),
                    selected: selected == generativeVoiceOff,
                    onSelected: (_) => guide.setGenerativeVoice(generativeVoiceOff),
                  ),
                ],
              ),
              // #552: other voices of the language, downloaded on tap.
              if (downloadable.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(l10n.generativeVoiceDownloadTitle, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in downloadable)
                      ActionChip(
                        avatar: _downloading == v.name
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download, size: 18),
                        label: Text([GenerativeVoiceSettingNames.short(v.name), gender(v)]
                            .where((s) => s.isNotEmpty)
                            .join(' · ')),
                        tooltip: l10n.generativeVoiceDownloadTooltip,
                        onPressed: _downloading == null ? () => _download(v.name) : null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Display helpers for [GenerativeVoiceSetting].
abstract final class GenerativeVoiceSettingNames {
  /// `fr-fr-x-star02` → `star02`: the locale is already shown elsewhere.
  static String short(String name) {
    final i = name.lastIndexOf('-');
    return i == -1 ? name : name.substring(i + 1);
  }
}
