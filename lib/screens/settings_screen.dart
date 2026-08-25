import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'logs_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../constants/output_languages.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/remote_config_service.dart';
import '../services/secure_key_storage.dart';
import '../services/settings_service.dart';
import '../widgets/kofi_button.dart';
import '../utils/build_info.dart';
import '../utils/date_format_utils.dart';

const _ttsPreviewSample =
    'Voici un exemple de la voix qui sera utilisée pour vos guides audio. '
    'Remarquez le rythme et l\'intonation sur cette phrase.';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    final guide = context.read<AudioGuideService>();
    _apiKeyController.text = guide.geminiApiKey ?? '';
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testVoice() async {
    final guide = context.read<AudioGuideService>();
    final played = await guide.nativeTtsService
        .speakAndWaitForResult(_ttsPreviewSample, speed: guide.playbackSpeed);
    if (!played && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.settingsNoVoiceProduced),
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final guide = context.read<AudioGuideService>();
    try {
      await guide.setGeminiApiKey(_apiKeyController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsSaved)),
        );
      }
    } on SecureStorageUnavailableException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.secureStorageUnavailable),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    _apiKeyController.clear();
    final guide = context.read<AudioGuideService>();
    await guide.setGeminiApiKey('');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.settingsApiKeyDeleted)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guide = context.watch<AudioGuideService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Consumer<SettingsService>(
            builder: (context, settings, _) => KofiButton(
              show: settings.showKofiButton,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // #145
          _SectionHeader(l10n.settingsAppearanceSection),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) => SegmentedButton<ThemeMode>(
              // #216: needs BOTH of these, not just one — dropping only the
              // per-segment icons still left the selected segment's
              // checkmark (showSelectedIcon defaults to true) eating into
              // "Système"'s width on a real device, confirmed by the user
              // after the first attempt (icons removed alone) still
              // wrapped. Selection is already unambiguous from the
              // segment's own background/text color change.
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l10n.settingsThemeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l10n.settingsThemeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l10n.settingsThemeDark),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  settings.setThemeMode(selection.first),
            ),
          ),
          const SizedBox(height: 32),

          // Provider status
          _SectionHeader(l10n.settingsActiveAiEngine),
          const SizedBox(height: 8),
          _ProviderCard(
            icon: Icons.phone_android,
            name: 'Gemini Nano',
            description: l10n.settingsNanoDescription,
            isActive: guide.activeProvider == AIProvider.geminiNano,
            isAvailable: guide.nanoAvailable,
            onTap: guide.nanoAvailable
                ? () => guide.setActiveProvider(AIProvider.geminiNano)
                : null,
          ),
          const SizedBox(height: 8),
          _ProviderCard(
            icon: Icons.cloud_outlined,
            name: 'Gemini API',
            description: l10n.settingsApiDescription,
            isActive: guide.activeProvider == AIProvider.geminiApi,
            isAvailable: guide.geminiApiKey?.isNotEmpty == true,
            onTap: guide.geminiApiKey?.isNotEmpty == true
                ? () => guide.setActiveProvider(AIProvider.geminiApi)
                : null,
          ),

          const SizedBox(height: 32),

          // Gemini API key
          _SectionHeader(l10n.settingsApiKeySectionTitle),
          const SizedBox(height: 8),
          Text(
            l10n.settingsGetFreeKey,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.54)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'AIza...',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  if (_apiKeyController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.settingsSave),
          ),

          const SizedBox(height: 32),

          // Active config section
          _SectionHeader(l10n.settingsActiveConfig),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final cfg = RemoteConfigService.current;
            final loadedAt = RemoteConfigService.loadedAt;
            final fromRemote = RemoteConfigService.loadedFromRemote;
            final theme = Theme.of(context);
            final dimText = theme.colorScheme.onSurface.withValues(alpha: 0.38);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      fromRemote ? Icons.cloud_done : Icons.cloud_off,
                      size: 14,
                      color: fromRemote ? Colors.greenAccent : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      fromRemote
                          ? l10n.settingsConfigFromGithub
                          : l10n.settingsConfigDefaultOffline,
                      style: TextStyle(
                        color: fromRemote ? Colors.greenAccent : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ]),
                  if (loadedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsUpdatedAt(formatLocalDateTime(
                          loadedAt, Localizations.localeOf(context).toString())),
                      style: TextStyle(color: dimText, fontSize: 11),
                    ),
                  ],
                  if (_appVersion != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsVersionLabel(_appVersion!),
                      style: TextStyle(color: dimText, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsBuildLabel(formatBuildDate(
                        buildDate,
                        Localizations.localeOf(context).toString(),
                        l10n.settingsBuildDateUnavailable)),
                    style: TextStyle(color: dimText, fontSize: 11),
                  ),
                  Divider(
                      height: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
                  _ConfigRow(l10n.settingsConfigModel, cfg.geminiModel),
                  _ConfigRow(l10n.settingsConfigFallbacks, cfg.geminiModelFallbacks.join(', ')),
                  _ConfigRow(l10n.settingsConfigTtsModel, cfg.geminiTtsModel),
                  _ConfigRow(l10n.settingsConfigTtsVoice, cfg.geminiTtsVoice),
                  _ConfigRow(l10n.settingsConfigMaxTokens, cfg.geminiMaxTokens.toString()),
                  _ConfigRow(
                      l10n.settingsConfigThinkingBudget, cfg.geminiThinkingBudget.toString()),
                  _ConfigRow(
                      l10n.settingsConfigWikipediaRadius, '${cfg.wikipediaRadiusMeters}m'),
                  _ConfigRow(l10n.settingsConfigTtsSpeed, cfg.ttsSpeed.toString()),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l10n.settingsRefreshConfig),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: () async {
              await RemoteConfigService.forceRefresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                    RemoteConfigService.loadedFromRemote
                        ? l10n.settingsConfigUpdatedFromGithub
                        : l10n.settingsConfigUnreachable,
                  )),
                );
                (context as Element).markNeedsBuild();
              }
            },
          ),

          const SizedBox(height: 32),

          // Developer tools
          _SectionHeader(l10n.settingsTools),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: Text(l10n.settingsViewLogs),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LogsScreen())),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.code, size: 16),
            label: Text(l10n.settingsViewSourceCode),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/Nohzoh/AudioLens'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 16),
          Consumer<SettingsService>(
            builder: (context, settings, _) => SwitchListTile(
              title: Text(l10n.settingsShowKofiButton),
              subtitle: Text(l10n.settingsKofiButtonSubtitle),
              value: settings.showKofiButton,
              onChanged: (value) => settings.setShowKofiButton(value),
            ),
          ),
          Consumer<SettingsService>(
            builder: (context, settings, _) => SwitchListTile(
              title: Text(l10n.settingsAutoGenerateAudio),
              subtitle: Text(l10n.settingsAutoGenerateAudioSubtitle),
              value: settings.autoGenerateAudio,
              onChanged: (value) => settings.setAutoGenerateAudio(value),
            ),
          ),
          Consumer<SettingsService>(
            builder: (context, settings, _) => Column(
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsAutoPurge),
                  subtitle: Text(l10n.settingsAutoPurgeSubtitle),
                  value: settings.autoPurgeEnabled,
                  onChanged: (value) => settings.setAutoPurgeEnabled(value),
                ),
                if (settings.autoPurgeEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final days in const [7, 14, 30, 90])
                          ChoiceChip(
                            label: Text(l10n.settingsAutoPurgeDaysOption(days)),
                            selected: settings.autoPurgeDays == days,
                            onSelected: (_) => settings.setAutoPurgeDays(days),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _SectionHeader(l10n.settingsVoiceSection),
          const SizedBox(height: 8),
          Consumer<AudioGuideService>(
            builder: (context, guide, _) => SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'female',
                  label: Text(l10n.settingsVoiceFemale),
                  icon: const Icon(Icons.face_3),
                ),
                ButtonSegment(
                  value: 'male',
                  label: Text(l10n.settingsVoiceMale),
                  icon: const Icon(Icons.face_6),
                ),
              ],
              selected: {guide.ttsVoiceGender},
              onSelectionChanged: (selection) =>
                  guide.setTtsVoiceGender(selection.first),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text(l10n.settingsTestVoice),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: _testVoice,
          ),

          const SizedBox(height: 32),

          _SectionHeader(l10n.settingsPlaybackSpeed),
          const SizedBox(height: 8),
          Consumer<AudioGuideService>(
            builder: (context, guide, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  (speed: 0.75, label: '0.75x'),
                  (speed: 1.0, label: '1x'),
                  (speed: 1.25, label: '1.25x'),
                  (speed: 1.5, label: '1.5x'),
                ])
                  ChoiceChip(
                    label: Text(option.label),
                    selected: guide.playbackSpeed == option.speed,
                    onSelected: (_) => guide.setPlaybackSpeed(option.speed),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          _SectionHeader(l10n.settingsScriptStyleSection),
          const SizedBox(height: 4),
          Text(
            l10n.settingsScriptStyleSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.settingsStyleImmersive),
                  selected: settings.scriptStyle == 'immersive',
                  onSelected: (_) => settings.setScriptStyle('immersive'),
                ),
                ChoiceChip(
                  label: Text(l10n.settingsStyleAcademic),
                  selected: settings.scriptStyle == 'academic',
                  onSelected: (_) => settings.setScriptStyle('academic'),
                ),
                ChoiceChip(
                  label: Text(l10n.settingsStyleAnecdotal),
                  selected: settings.scriptStyle == 'anecdotal',
                  onSelected: (_) => settings.setScriptStyle('anecdotal'),
                ),
                ChoiceChip(
                  label: Text(l10n.settingsStyleConcise),
                  selected: settings.scriptStyle == 'concise',
                  onSelected: (_) => settings.setScriptStyle('concise'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // #130
          _SectionHeader(l10n.settingsOutputLanguageSection),
          const SizedBox(height: 4),
          Text(
            l10n.settingsOutputLanguageSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Consumer<SettingsService>(
            builder: (context, settings, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final language in outputLanguageLocales.keys)
                  ChoiceChip(
                    label: Text(language),
                    selected: settings.outputLanguage == language,
                    onSelected: (_) => settings.setOutputLanguage(language),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.54)),
                  const SizedBox(width: 8),
                  Text(l10n.settingsAboutGeminiApi,
                      style: theme.textTheme.labelMedium),
                ]),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsGeminiApiBullets,
                  style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
                      fontSize: 13,
                      height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            letterSpacing: 1.2,
          ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final bool isActive;
  final bool isAvailable;
  final VoidCallback? onTap;

  const _ProviderCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.isActive,
    required this.isAvailable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? theme.colorScheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      // ListTile paints its background/ink splashes on the nearest Material
      // ancestor — without this, the outer DecoratedBox (from this
      // AnimatedContainer) hides them, making the tap ripple invisible
      // (Flutter's own debug assertion catches this; surfaced by T105's
      // new settings_screen_test.dart, which actually exercises a tap).
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(
            icon,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface
                    .withValues(alpha: isAvailable ? 0.70 : 0.24),
          ),
          title: Text(
            name,
            style: TextStyle(
              color: theme.colorScheme.onSurface
                  .withValues(alpha: isAvailable ? 1.0 : 0.38),
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            isAvailable ? description : '$description\n${l10n.settingsNotConfiguredSuffix}',
            style: TextStyle(
              color: theme.colorScheme.onSurface
                  .withValues(alpha: isAvailable ? 0.54 : 0.24),
              fontSize: 12,
            ),
          ),
          trailing: isActive
              ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
              : isAvailable
                  ? Icon(Icons.radio_button_unchecked,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.38))
                  : Icon(Icons.lock_outline,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.24)),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfigRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
                    fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
