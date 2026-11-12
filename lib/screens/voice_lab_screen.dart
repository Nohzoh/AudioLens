import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../services/genai_tts_service.dart';
import '../services/native_tts_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_sanitizer.dart';

/// #485: debug tool (Settings > Tools) to try ML Kit's on-device
/// generative Text to Speech on this phone and report what it does —
/// which voices exist, whether their model is installed, how long the
/// first audio takes, and what the audio data looks like. The guide's
/// voice chain doesn't use this engine yet; this screen exists to find
/// out whether and how it can.
class VoiceLabScreen extends StatefulWidget {
  const VoiceLabScreen({super.key, GenAiTtsService? service, this.nativeVoiceNames})
      : _service = service;

  final GenAiTtsService? _service;

  /// Names of the voices the device's native TTS engine reports for a
  /// locale prefix. Injectable for tests; defaults to flutter_tts.
  final Future<List<String>> Function(String localePrefix)? nativeVoiceNames;

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _VoiceLabScreenState extends State<VoiceLabScreen> {
  late final GenAiTtsService _tts = widget._service ?? GenAiTtsService();
  final _localeController = TextEditingController(text: 'fr-FR');
  final _textController = TextEditingController(
    text: 'Bienvenue devant ce monument. Prenez le temps d\'observer sa façade, '
        'ses lignes et la lumière qui joue sur la pierre.',
  );

  List<GenAiVoice>? _voices;
  String? _voice;
  String? _error;
  bool _busy = false;
  GenAiTtsProbe? _probe;
  String? _downloadLog;
  List<String>? _nativeNames;
  String? _lastCrash;

  Future<List<String>> _defaultNativeVoiceNames(String prefix) async {
    final voices = await NativeTtsService().voicesForLocale(prefix);
    return [for (final v in voices) v['name'] ?? ''];
  }

  @override
  void initState() {
    super.initState();
    AppLogger.nav('VoiceLabScreen opened');
    _loadLastCrash();
    _loadVoices();
  }

  @override
  void dispose() {
    AppLogger.nav('VoiceLabScreen closed');
    _tts.stop().catchError((_) {});
    _localeController.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// #501: a previous probe may have crashed the app; its stack trace
  /// was saved for this moment.
  Future<void> _loadLastCrash() async {
    try {
      final crash = await _tts.lastCrash();
      if (!mounted || crash == null) return;
      setState(() => _lastCrash = crash);
      AppLogger.error('Voice Lab: a previous probe crashed the app (trace available in the lab)');
    } catch (_) {
      // Older platform side or no plugin: nothing to show.
    }
  }

  String get _locale => _localeController.text.trim();

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      AppLogger.error('Voice Lab: ${sanitizeError(e.toString())}');
      if (mounted) setState(() => _error = e is PlatformException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadVoices() => _run(() async {
        final voices = await _tts.voices(_locale);
        if (!mounted) return;
        setState(() {
          _voices = voices;
          if (!voices.any((v) => v.name == _voice)) {
            _voice = voices.isEmpty ? null : voices.first.name;
          }
        });
        AppLogger.tts('Voice Lab: ${voices.length} voice(s) listed');
        // What the app's existing native voice can see for the same
        // language — to tell whether it could select these voices itself.
        try {
          final prefix = _locale.split('-').first;
          final names =
              await (widget.nativeVoiceNames ?? _defaultNativeVoiceNames)(prefix);
          if (mounted) setState(() => _nativeNames = names);
        } catch (_) {
          if (mounted) setState(() => _nativeNames = null);
        }
      });

  /// One line saying whether the native engine lists [voice].
  String _nativeVisibility(GenAiVoice voice, AppLocalizations l10n) {
    final engineName = voice.engineName;
    final names = _nativeNames;
    if (engineName == null || names == null) return l10n.voiceLabNativeUnknown;
    return names.contains(engineName)
        ? l10n.voiceLabNativeListed(engineName)
        : l10n.voiceLabNativeNotListed(engineName, names.length);
  }

  Future<void> _download() => _run(() async {
        final statuses = await _tts.download(_locale, _voice!);
        if (!mounted) return;
        setState(() => _downloadLog = statuses.join(' → '));
        final voices = await _tts.voices(_locale);
        if (mounted) setState(() => _voices = voices);
      });

  Future<void> _synthesize() => _run(() async {
        setState(() => _probe = null);
        final probe = await _tts.probe(
          locale: _locale,
          voice: _voice!,
          text: _textController.text.trim(),
        );
        if (!mounted) return;
        setState(() => _probe = probe);
        AppLogger.tts('Voice Lab: probe done, ${probe.chunkCount} chunk(s), '
            'first at ${probe.firstChunkMs ?? -1} ms, error: ${probe.error != null}');
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final voices = _voices;
    final selected = voices?.where((v) => v.name == _voice).firstOrNull;
    final probe = _probe;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.voiceLabTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.voiceLabIntro, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          if (_lastCrash != null) ...[
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.voiceLabCrashTitle, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(
                      _lastCrash!,
                      maxLines: 12,
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(l10n.voiceLabCopyReport),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: _lastCrash!)),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            _tts.clearCrash().catchError((_) {});
                            setState(() => _lastCrash = null);
                          },
                          child: Text(l10n.voiceLabCrashDismiss),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _localeController,
                  decoration: InputDecoration(
                    labelText: l10n.voiceLabLocale,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _loadVoices,
                child: Text(l10n.voiceLabListVoices),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (voices != null && voices.isEmpty)
            Text(l10n.voiceLabNoVoices,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
          if (voices != null && voices.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in voices)
                  ChoiceChip(
                    label: Text('${v.name} · ${v.status}'),
                    selected: v.name == _voice,
                    onSelected: (_) => setState(() => _voice = v.name),
                  ),
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                '${selected.details}\n${_nativeVisibility(selected, l10n)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (selected != null && selected.status == 'downloadable') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: Text(l10n.voiceLabDownload),
                onPressed: _busy ? null : _download,
              ),
            ],
            if (_downloadLog != null) ...[
              const SizedBox(height: 4),
              Text(_downloadLog!, style: theme.textTheme.labelSmall),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l10n.voiceLabText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.record_voice_over),
              label: Text(l10n.voiceLabSynthesize),
              onPressed: _busy || _voice == null ? null : _synthesize,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            SelectableText(_error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
          ],
          if (probe != null) ...[
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(probe.describe(), style: theme.textTheme.bodySmall),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.voiceLabCopyReport),
              onPressed: () => Clipboard.setData(ClipboardData(text: probe.describe())),
            ),
            if (probe.audioFile != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(l10n.voiceLabShareAudio),
                onPressed: () => SharePlus.instance.share(
                    ShareParams(text: probe.describe(), files: [XFile(probe.audioFile!)])),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
