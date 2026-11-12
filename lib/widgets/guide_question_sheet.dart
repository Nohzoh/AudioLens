import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/guide_question_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';

/// #424: whether a question can be asked about [entry] — a complete
/// analysis, and a model to answer.
bool canAskAboutEntry(BuildContext context, HistoryEntry? entry) {
  if (entry == null || entry.status != AnalysisStatus.complete) return false;
  if (entry.script.trim().isEmpty) return false;
  try {
    return questionServiceFor(context).isAvailable;
  } on ProviderNotFoundException {
    // A screen built without the AI services (some widget tests).
    return false;
  }
}

/// #424: the question service built from the app's AI configuration.
GuideQuestionService questionServiceFor(BuildContext context) {
  final guide = context.read<AudioGuideService>();
  return GuideQuestionService(
    api: guide.geminiApiServiceForQuiz,
    nano: guide.nanoService,
    nanoAvailable: guide.nanoAvailable,
  );
}

/// #424: opens the question sheet for [entry].
Future<void> showGuideQuestionSheet(
  BuildContext context,
  HistoryEntry entry, {
  GuideQuestionService? service,
}) {
  final language =
      entry.outputLanguage ?? context.read<SettingsService>().outputLanguage;
  final questions = service ?? questionServiceFor(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GuideQuestionSheet(
      entry: entry,
      language: language,
      service: questions,
    ),
  );
}

/// #424: a short conversation about one guide. Ephemeral: closing the
/// sheet forgets it.
class GuideQuestionSheet extends StatefulWidget {
  const GuideQuestionSheet({
    super.key,
    required this.entry,
    required this.language,
    required this.service,
  });

  final HistoryEntry entry;
  final String language;
  final GuideQuestionService service;

  @override
  State<GuideQuestionSheet> createState() => _GuideQuestionSheetState();
}

class _GuideQuestionSheetState extends State<GuideQuestionSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _exchanges = <GuideExchange>[];
  CancelToken? _pending;
  String? _pendingQuestion;
  bool _failed = false;

  @override
  void dispose() {
    _pending?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _limitReached => _exchanges.length >= maxGuideQuestions;

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _pending != null || _limitReached) return;
    final token = CancelToken();
    setState(() {
      _pending = token;
      _pendingQuestion = question;
      _failed = false;
    });
    _controller.clear();
    // log-hygiene-ok: only the question's length, never its text.
    AppLogger.ai('Guide question asked (${question.length} chars, '
        'context ${widget.entry.promptContext == null ? 'not recorded' : 'recorded'})');
    try {
      final answer = await widget.service.ask(
        title: widget.entry.title,
        script: widget.entry.script,
        context: widget.entry.promptContext ?? _fallbackContext(widget.entry),
        language: widget.language,
        previous: List.of(_exchanges),
        question: question,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _exchanges.add(GuideExchange(question, answer));
        _pending = null;
        _pendingQuestion = null;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted || token.isCancelled) return;
      AppLogger.error('Guide question failed: ${sanitizeError(e.toString())}');
      setState(() {
        _pending = null;
        _failed = true;
        // Give the question back so it can be sent again.
        _controller.text = question;
        _pendingQuestion = null;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  /// Entries analyzed before #424 kept no context: the address is the
  /// little there is.
  static String? _fallbackContext(HistoryEntry entry) {
    final address = entry.gpsAddress ?? entry.locationName;
    return address == null || address.isEmpty ? null : 'Adresse : $address';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.guideQuestionTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(widget.entry.title,
                  style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  children: [
                    if (_exchanges.isEmpty && _pendingQuestion == null)
                      Text(l10n.guideQuestionIntro, style: theme.textTheme.bodyMedium),
                    for (final e in _exchanges) ...[
                      _Bubble(text: e.question, mine: true),
                      _Bubble(text: e.answer, mine: false),
                    ],
                    if (_pendingQuestion != null) ...[
                      _Bubble(text: _pendingQuestion!, mine: true),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Next to the input, so they stay visible however long the
              // conversation is.
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.guideQuestionFailed,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
              if (_limitReached)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.guideQuestionLimit, style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_limitReached,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.guideQuestionHint,
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: l10n.guideQuestionSend,
                    icon: const Icon(Icons.send),
                    onPressed: _pending != null || _limitReached ? null : _send,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(text),
      ),
    );
  }
}
