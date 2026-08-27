import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/gemini_nano_service.dart';
import '../services/location_context_resolver.dart';

/// One past call, kept in memory only (session-scoped) so recent attempts
/// can be reloaded into the form for quick side-by-side comparison without
/// retyping the prompt each time. Only used by the free-form ("raw") mode
/// — the full-pipeline mode's result shape (per-segment breakdown) doesn't
/// fit this single-output model, so it isn't added to this history.
class _LabAttempt {
  final String prompt;
  final File? image;
  final int maxOutputTokens;
  final double? temperature;
  final String? output;
  final String? error;
  final Duration elapsed;

  const _LabAttempt({
    required this.prompt,
    required this.image,
    required this.maxOutputTokens,
    required this.temperature,
    required this.output,
    required this.error,
    required this.elapsed,
  });
}

enum _LabMode { raw, pipeline }

/// Debug tool (Settings > Tools, only shown when Nano is actually
/// available) for iterating on Gemini Nano prompt wording directly against
/// real on-device inference.
///
/// Two modes:
/// - **Free-form prompt** (`GeminiNanoPlugin.kt`'s "rawPrompt"): one raw
///   `generateContent` call, no `buildSeg1/2/3Prompt` scaffolding — for
///   testing prompt wording in isolation.
/// - **Full pipeline** (#276, "describeImageDebug"): takes a GPS
///   location, resolves it through the real production
///   `LocationContextResolver` (reverse geocoding, POI/OSM metadata,
///   Wikidata, Wikipedia), then runs the exact same 3-segment cascade
///   production uses — surfacing each segment's own prompt and output,
///   not just the final assembled script.
class NanoPromptLabScreen extends StatefulWidget {
  const NanoPromptLabScreen({super.key});

  @override
  State<NanoPromptLabScreen> createState() => _NanoPromptLabScreenState();
}

class _NanoPromptLabScreenState extends State<NanoPromptLabScreen> {
  final _nano = GeminiNanoService();
  final _locationResolver = LocationContextResolver();

  _LabMode _mode = _LabMode.raw;

  // Shared knobs (both modes).
  final _maxTokensController = TextEditingController(text: '256');
  final _temperatureController = TextEditingController();
  File? _image;

  // Raw mode.
  final _promptController = TextEditingController();
  bool _sending = false;
  String? _output;
  String? _error;
  Duration? _elapsed;
  final List<_LabAttempt> _history = [];

  // Pipeline mode.
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  bool _resolvingLocation = false;
  LocationContext? _locationContext;
  String? _locationError;
  bool _runningPipeline = false;
  NanoDebugCascadeResult? _debugResult;
  String? _pipelineError;
  Duration? _pipelineElapsed;

  @override
  void dispose() {
    _promptController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _nano.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (xFile == null || !mounted) return;
    setState(() => _image = File(xFile.path));
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending) return;

    final maxTokens = int.tryParse(_maxTokensController.text) ?? 256;
    final temperature = double.tryParse(_temperatureController.text);
    final image = _image;

    setState(() {
      _sending = true;
      _output = null;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    String? output;
    String? error;
    try {
      output = await _nano.rawPrompt(
        prompt: prompt,
        imageFile: image,
        maxOutputTokens: maxTokens,
        temperature: temperature,
      );
    } catch (e) {
      error = e.toString();
    }
    stopwatch.stop();

    if (!mounted) return;
    setState(() {
      _sending = false;
      _output = output;
      _error = error;
      _elapsed = stopwatch.elapsed;
      _history.insert(
        0,
        _LabAttempt(
          prompt: prompt,
          image: image,
          maxOutputTokens: maxTokens,
          temperature: temperature,
          output: output,
          error: error,
          elapsed: stopwatch.elapsed,
        ),
      );
    });
  }

  void _reuse(_LabAttempt attempt) {
    setState(() {
      _promptController.text = attempt.prompt;
      _maxTokensController.text = attempt.maxOutputTokens.toString();
      _temperatureController.text = attempt.temperature?.toString() ?? '';
      _image = attempt.image;
      _output = attempt.output;
      _error = attempt.error;
      _elapsed = attempt.elapsed;
    });
  }

  Future<void> _resolveLocation() async {
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null || _resolvingLocation) return;

    setState(() {
      _resolvingLocation = true;
      _locationContext = null;
      _locationError = null;
    });

    LocationContext? ctx;
    String? error;
    try {
      ctx = await _locationResolver.resolveFromCoordinates(lat: lat, lon: lon, source: 'manual');
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _resolvingLocation = false;
      _locationContext = ctx;
      _locationError = error;
    });
  }

  Future<void> _runPipeline() async {
    final image = _image;
    if (image == null || _runningPipeline) return;

    final maxTokens = int.tryParse(_maxTokensController.text) ?? 256;
    final temperature = double.tryParse(_temperatureController.text);

    setState(() {
      _runningPipeline = true;
      _debugResult = null;
      _pipelineError = null;
    });

    final stopwatch = Stopwatch()..start();
    NanoDebugCascadeResult? result;
    String? error;
    try {
      result = await _nano.describeImageDebug(
        imageFile: image,
        locationContext: _locationContext?.promptContext,
        maxOutputTokens: maxTokens,
        temperature: temperature,
      );
    } catch (e) {
      error = e.toString();
    }
    stopwatch.stop();

    if (!mounted) return;
    setState(() {
      _runningPipeline = false;
      _debugResult = result;
      _pipelineError = error;
      _pipelineElapsed = stopwatch.elapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nanoLabTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_LabMode>(
            segments: [
              ButtonSegment(value: _LabMode.raw, label: Text(l10n.nanoLabModeRaw)),
              ButtonSegment(value: _LabMode.pipeline, label: Text(l10n.nanoLabModePipeline)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_image!, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_image == null ? l10n.nanoLabPickImage : l10n.nanoLabChangeImage),
                  onPressed: _pickImage,
                ),
              ),
              if (_image != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.nanoLabClearImage,
                  onPressed: () => setState(() => _image = null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mode == _LabMode.raw) ..._buildRawMode(l10n, theme) else ..._buildPipelineMode(l10n, theme),
        ],
      ),
    );
  }

  List<Widget> _buildRawMode(AppLocalizations l10n, ThemeData theme) {
    return [
      TextField(
        controller: _promptController,
        maxLines: 6,
        minLines: 3,
        decoration: InputDecoration(
          labelText: l10n.nanoLabPromptHint,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      _buildKnobsRow(l10n),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send),
        label: Text(_sending ? l10n.nanoLabSending : l10n.nanoLabSend),
        onPressed: _sending ? null : _send,
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
      ),
      const SizedBox(height: 20),
      if (_error != null) ...[
        _errorBox(theme, _error!),
        const SizedBox(height: 16),
      ],
      if (_output != null) ...[
        Row(
          children: [
            Text(l10n.nanoLabOutput, style: theme.textTheme.labelLarge),
            const Spacer(),
            if (_elapsed != null)
              Text('${_elapsed!.inMilliseconds} ms',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.54))),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: l10n.nanoLabCopyOutput,
              onPressed: () => Clipboard.setData(ClipboardData(text: _output!)),
            ),
          ],
        ),
        _outputBox(theme, _output!),
        const SizedBox(height: 20),
      ],
      Text(l10n.nanoLabHistory, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      if (_history.isEmpty)
        Text(l10n.nanoLabEmptyHistory,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.54)))
      else
        for (final attempt in _history)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: attempt.image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(attempt.image!, width: 40, height: 40, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.text_fields),
              title: Text(attempt.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                attempt.error != null ? l10n.nanoLabHistoryError : '${attempt.elapsed.inMilliseconds} ms',
              ),
              onTap: () => _reuse(attempt),
            ),
          ),
    ];
  }

  List<Widget> _buildPipelineMode(AppLocalizations l10n, ThemeData theme) {
    final ctx = _locationContext;
    return [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _latController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: l10n.nanoLabLatitude,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _lonController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: l10n.nanoLabLongitude,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: _resolvingLocation
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.place_outlined, size: 18),
        label: Text(_resolvingLocation ? l10n.nanoLabResolving : l10n.nanoLabResolveLocation),
        onPressed: _resolvingLocation ? null : _resolveLocation,
      ),
      const SizedBox(height: 12),
      if (_locationError != null) ...[
        _errorBox(theme, '${l10n.nanoLabLocationError}: $_locationError'),
        const SizedBox(height: 12),
      ],
      Text(l10n.nanoLabLocationContext, style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      if (ctx == null)
        Text(l10n.nanoLabNoLocation,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.54)))
      else
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ctx.poi != null
                      ? '${ctx.poi!.name}'
                          '${ctx.poi!.category != null ? ' (${ctx.poi!.category})' : ''}'
                          '${ctx.poi!.subtype != null ? ' — ${ctx.poi!.subtype}' : ''}'
                      : l10n.nanoLabPoiNone,
                  style: theme.textTheme.bodyMedium,
                ),
                if (ctx.poi?.inscription != null) ...[
                  const SizedBox(height: 4),
                  Text('« ${ctx.poi!.inscription} »', style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Text(
                  ctx.wikidataInfo != null ? ctx.wikidataInfo!.summary : l10n.nanoLabWikidataNone,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(l10n.nanoLabWikipediaResults, style: theme.textTheme.labelMedium),
                if (ctx.wikipediaResults.isEmpty)
                  Text(l10n.nanoLabWikipediaNone, style: theme.textTheme.bodySmall)
                else
                  for (final w in ctx.wikipediaResults)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• ${w.title}', style: theme.textTheme.bodySmall),
                    ),
                if (ctx.promptContext != null) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  SelectableText(ctx.promptContext!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      _buildKnobsRow(l10n),
      const SizedBox(height: 12),
      if (_image == null) ...[
        Text(l10n.nanoLabImageRequired,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
      ],
      FilledButton.icon(
        icon: _runningPipeline
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_runningPipeline ? l10n.nanoLabRunningPipeline : l10n.nanoLabRunPipeline),
        onPressed: (_runningPipeline || _image == null) ? null : _runPipeline,
        style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
      ),
      const SizedBox(height: 20),
      if (_pipelineError != null) ...[
        _errorBox(theme, _pipelineError!),
        const SizedBox(height: 16),
      ],
      if (_debugResult != null) ..._buildDebugResult(l10n, theme, _debugResult!),
    ];
  }

  List<Widget> _buildDebugResult(AppLocalizations l10n, ThemeData theme, NanoDebugCascadeResult r) {
    return [
      Row(
        children: [
          Text(l10n.nanoLabFullText, style: theme.textTheme.labelLarge),
          const Spacer(),
          if (_pipelineElapsed != null)
            Text('${_pipelineElapsed!.inMilliseconds} ms',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.54))),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: l10n.nanoLabCopyOutput,
            onPressed: () => Clipboard.setData(ClipboardData(text: r.fullText)),
          ),
        ],
      ),
      _outputBox(theme, r.fullText),
      const SizedBox(height: 16),
      _segmentCard(l10n, theme, l10n.nanoLabSegment1, r.seg1Prompt, r.seg1Output),
      _segmentCard(l10n, theme, l10n.nanoLabSegment2, r.seg2Prompt, r.seg2Output),
      _segmentCard(l10n, theme, l10n.nanoLabSegment3, r.seg3Prompt, r.seg3Output),
    ];
  }

  Widget _segmentCard(AppLocalizations l10n, ThemeData theme, String title, String prompt, String output) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(title, style: theme.textTheme.labelLarge),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.nanoLabSegmentPrompt, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(height: 4),
          SelectableText(prompt, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.nanoLabOutput, style: theme.textTheme.labelSmall),
          ),
          const SizedBox(height: 4),
          SelectableText(output, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildKnobsRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _maxTokensController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.nanoLabMaxTokens,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _temperatureController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.nanoLabTemperature,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBox(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(message, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
    );
  }

  Widget _outputBox(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(text),
    );
  }
}
