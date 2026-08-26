import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/gemini_nano_service.dart';

/// One past call, kept in memory only (session-scoped) so recent attempts
/// can be reloaded into the form for quick side-by-side comparison without
/// retyping the prompt each time.
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

/// Debug tool (Settings > Tools, only shown when Nano is actually
/// available) for iterating on Gemini Nano prompt wording directly against
/// real on-device inference — one raw `generateContent` call per send, no
/// GPS/Wikipedia pipeline, no buildSeg1/2/3Prompt scaffolding
/// (GeminiNanoPlugin.kt's "rawPrompt" method, added alongside the existing
/// describeImage cascade for exactly this). Image is optional: attach one
/// to test segment-1-style prompts (image + text, where the actual visual
/// analysis happens), or leave it off to test segment-2/3-style text-only
/// continuations.
class NanoPromptLabScreen extends StatefulWidget {
  const NanoPromptLabScreen({super.key});

  @override
  State<NanoPromptLabScreen> createState() => _NanoPromptLabScreenState();
}

class _NanoPromptLabScreenState extends State<NanoPromptLabScreen> {
  final _nano = GeminiNanoService();
  final _promptController = TextEditingController();
  final _maxTokensController = TextEditingController(text: '256');
  final _temperatureController = TextEditingController();

  File? _image;
  bool _sending = false;
  String? _output;
  String? _error;
  Duration? _elapsed;
  final List<_LabAttempt> _history = [];

  @override
  void dispose() {
    _promptController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
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
          Row(
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
          ),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(_error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(_output!),
            ),
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
                          child: Image.file(attempt.image!,
                              width: 40, height: 40, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.text_fields),
                  title: Text(
                    attempt.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    attempt.error != null
                        ? l10n.nanoLabHistoryError
                        : '${attempt.elapsed.inMilliseconds} ms',
                  ),
                  onTap: () => _reuse(attempt),
                ),
              ),
        ],
      ),
    );
  }
}
