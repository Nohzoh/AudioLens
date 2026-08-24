import 'dart:io';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../utils/rotated_image_export.dart';
import '../widgets/background_photo.dart';
import '../widgets/kofi_button.dart';
import '../widgets/scrim_action_chip.dart';
import '../widgets/scrim_icon_button.dart';
import '../widgets/report_content_button.dart';

class PlayerScreen extends StatefulWidget {
  final File imageFile;
  /// Whether [imageFile] is a throwaway temp file (a fresh camera/gallery
  /// pick, already copied to permanent history storage before this screen
  /// was pushed) that this screen should delete once it's done with it
  /// (T45) — vs. an existing history entry's own permanent image, which
  /// must never be deleted here (retry/captured-launch flows pass that in
  /// as [imageFile] too, but leave this false).
  final bool deleteImageOnDispose;

  /// #152/#183: a prior manual rotation of this entry's photo, carried
  /// over so a retry (relaunching analysis on an existing entry) shows
  /// it the same way the history detail screen does — without this,
  /// the photo would flip back to its unrotated orientation during the
  /// retry/playback flow and then rotate again once analysis finishes
  /// and the detail screen takes over. Irrelevant for a fresh capture
  /// (default 0 — there's nothing to have rotated yet).
  final int rotationQuarters;

  const PlayerScreen({
    super.key,
    required this.imageFile,
    this.deleteImageOnDispose = false,
    this.rotationQuarters = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _scrollController = ScrollController();
  double _readingProgress = 0.0; // 0.0 to 1.0
  bool _photoMode = false; // T14: show the plain photo instead of the overlaid text

  @override
  void initState() {
    super.initState();
    // Listen to TTS progress from service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final guide = context.read<AudioGuideService>();
      guide.nativeTtsService.onProgress = (progress) {
        if (!mounted) return;
        setState(() => _readingProgress = progress);
        _scrollToProgress(progress);
      };
    });
  }

  void _scrollToProgress(double progress) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final target = maxScroll * progress;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (widget.deleteImageOnDispose) {
      try {
        if (widget.imageFile.existsSync()) widget.imageFile.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Consumer<AudioGuideService>(
        builder: (context, guide, _) {
          // Reset progress when new analysis starts
          if (guide.state == GuideState.locating ||
              guide.state == GuideState.analyzing) {
            _readingProgress = 0.0;
            _photoMode = false;
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // Background image
              BackgroundPhoto(file: widget.imageFile, rotationQuarters: widget.rotationQuarters),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _photoMode
                        ? [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ]
                        : [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.95),
                          ],
                    stops: _photoMode
                        ? const [0.0, 0.15, 0.85, 1.0]
                        : const [0.25, 0.75],
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          ScrimIconButton(
                            icon: Icons.arrow_back,
                            color: Colors.white,
                            onPressed: () {
                              guide.stop();
                              Navigator.pop(context);
                            },
                          ),
                          const Spacer(),
                          // Each trailing icon owns its own leading gap
                          // (rather than a shared SizedBox between them)
                          // so a hidden one — e.g. Ko-fi off in settings
                          // — contributes zero space instead of leaving
                          // an orphan gap or collapsing the gap next to
                          // whatever ends up adjacent to it.
                          if (guide.lastResult != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ScrimIconButton(
                                icon: _photoMode
                                    ? Icons.article_outlined
                                    : Icons.image_outlined,
                                color: Colors.white70,
                                tooltip: _photoMode
                                    ? l10n.playerShowText
                                    : l10n.playerPhotoMode,
                                onPressed: () =>
                                    setState(() => _photoMode = !_photoMode),
                              ),
                            ),
                          Consumer<SettingsService>(
                            builder: (context, settings, _) =>
                                settings.showKofiButton
                                    ? const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: KofiButton(
                                          show: true,
                                          iconColor: Colors.white70,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                          ),
                          if (guide.state == GuideState.cancelling)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                          else if (guide.state == GuideState.speaking || guide.state == GuideState.paused || guide.state == GuideState.synthesizing)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ScrimIconButton(
                                icon: Icons.cancel_outlined,
                                color: Colors.white70,
                                tooltip: l10n.playerCancel,
                                onPressed: () async {
                                  await guide.cancelCurrentAction();
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Content area
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pipeline progress
                            if (guide.state == GuideState.locating ||
                                guide.state == GuideState.analyzing ||
                                guide.state == GuideState.synthesizing) ...[
                              _PipelineProgressWidget(guide: guide),
                              const SizedBox(height: 16),
                            ],

                            // State label
                            if (!_photoMode) ...[
                              _StateLabel(state: guide.state),
                              const SizedBox(height: 8),
                            ],

                            // Title
                            if (guide.lastResult != null && !_photoMode) ...[
                              Text(
                                guide.lastResult!.title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ).animate().fadeIn().slideY(begin: 0.2),

                              if (guide.lastResult!.locationName != null) ...[
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.white54, size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    guide.lastResult!.locationName!,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                                ]),
                              ],

                              const SizedBox(height: 4),

                              // AI-generated content disclosure — shown
                              // wherever the AI-generated script/audio is
                              // actually delivered, not just buried in the
                              // detail sheet (_AiGeneratedBanner in
                              // about_analysis_screen.dart, which stays too).
                              Row(children: [
                                const Icon(Icons.auto_awesome,
                                    color: Colors.white54, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.playerAiGeneratedDisclosure,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ]),

                              const SizedBox(height: 4),

                              // Action buttons row. Wrap, not Row: see
                              // the matching comment in history_screen.dart
                              // — three pills plus spacing can exceed a
                              // narrow screen's width, especially in the
                              // longer French labels.
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  // Save to gallery
                                  ScrimActionChip(
                                    icon: Icons.save_alt,
                                    label: l10n.playerSave,
                                    onTap: () async {
                                      try {
                                        final galleryPath = await imagePathForGallerySave(
                                            widget.imageFile.path, widget.rotationQuarters);
                                        await Gal.putImage(galleryPath);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(l10n.playerPhotoSaved),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      } catch (_) {}
                                    },
                                  ),
                                  // Copy text
                                  ScrimActionChip(
                                    icon: Icons.copy,
                                    label: l10n.playerCopy,
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: guide.lastResult!.script));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(l10n.playerTextCopied), duration: const Duration(seconds: 2)),
                                      );
                                    },
                                  ),
                                  // Report content (T91)
                                  ReportContentButton(
                                    title: guide.lastResult!.title,
                                    script: guide.lastResult!.script,
                                    aiModel: guide.actualAiModel ?? guide.lastAiModel,
                                    date: DateTime.now(),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Fallback banners
                              if (guide.state == GuideState.speaking ||
                                  guide.state == GuideState.paused) ...[
                                if (guide.aiModelWasFallback)
                                  _FallbackBanner(
                                    icon: Icons.swap_horiz,
                                    message: l10n.playerAiFallbackMessage(guide.actualAiModel ?? '?'),
                                    color: Colors.orange,
                                  ),
                                if (guide.ttsWasFallback)
                                  _FallbackBanner(
                                    icon: Icons.volume_down,
                                    message: guide.ttsFallbackWasRateLimit
                                        ? l10n.playerTtsRateLimitFallback
                                        : l10n.playerTtsFallback,
                                    color: Colors.orange,
                                  ),
                                const SizedBox(height: 8),
                              ],

                              // Scrollable script with reading progress bar
                              Expanded(
                                child: Stack(
                                  children: [
                                    // Script text — scrollable by user + auto-scroll
                                    SingleChildScrollView(
                                      controller: _scrollController,
                                      physics: const BouncingScrollPhysics(),
                                      child: _HighlightedScript(
                                        text: guide.lastResult!.script,
                                        progress: _readingProgress,
                                      ),
                                    ),

                                    // Reading progress bar on the left edge
                                    if (guide.state == GuideState.speaking ||
                                        guide.state == GuideState.paused)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 3,
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          child: FractionallySizedBox(
                                            alignment: Alignment.topCenter,
                                            heightFactor: _readingProgress,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],

                            // Error
                            if (guide.state == GuideState.error)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xDD1a0000),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.error_outline,
                                            color: Colors.redAccent, size: 18),
                                        const SizedBox(width: 8),
                                        Text(l10n.playerError,
                                            style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        const Spacer(),
                                        // Same pattern as the Save/Copy/
                                        // Report row above — this used
                                        // to hand-roll its own InkWell,
                                        // drifting slightly out of sync
                                        // (11px/no pill vs the shared
                                        // chip's 12px pill) from every
                                        // other copy-style action.
                                        ScrimActionChip(
                                          icon: Icons.copy,
                                          label: l10n.playerCopy,
                                          color: Colors.white54,
                                          onTap: () {
                                            Clipboard.setData(ClipboardData(
                                                text: guide.errorMessage ?? ''));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                  content: Text(l10n.playerErrorCopied),
                                                  duration: const Duration(seconds: 2)));
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      guide.errorMessage ?? l10n.playerUnknownError,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Controls
                    if (guide.state == GuideState.speaking ||
                        guide.state == GuideState.paused)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // T118/T21: skip ±10s — only meaningful for the
                            // Gemini/cached-WAV engine (see
                            // AudioGuideService.canSkip's doc), hidden
                            // entirely rather than shown-but-broken for
                            // native TTS playback.
                            if (guide.canSkip) ...[
                              IconButton(
                                icon: const Icon(Icons.replay_10,
                                    color: Colors.white70, size: 32),
                                onPressed: guide.skipBack,
                              ),
                              const SizedBox(width: 8),
                            ],
                            IconButton.filled(
                              iconSize: 36,
                              icon: Icon(guide.state == GuideState.speaking
                                  ? Icons.pause : Icons.play_arrow),
                              onPressed: guide.togglePause,
                            ),
                            if (guide.canSkip) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.forward_10,
                                    color: Colors.white70, size: 32),
                                onPressed: guide.skipForward,
                              ),
                            ],
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.stop_circle_outlined,
                                  color: Colors.white70, size: 36),
                              onPressed: () async {
                                await guide.cancelCurrentAction();
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Displays script text with progressive highlighting
class _HighlightedScript extends StatelessWidget {
  final String text;
  final double progress; // 0.0 to 1.0

  const _HighlightedScript({required this.text, required this.progress});

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.0) {
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white70, fontSize: 15, height: 1.7),
        ),
      );
    }

    final splitIndex = (text.length * progress).round().clamp(0, text.length);
    final read = text.substring(0, splitIndex);
    final unread = text.substring(splitIndex);

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: read,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.7,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: unread,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 15,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineProgressWidget extends StatelessWidget {
  final AudioGuideService guide;
  const _PipelineProgressWidget({required this.guide});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = guide.progress;
    final steps = [
      (icon: Icons.location_on, label: l10n.playerStepGps),
      (icon: Icons.psychology, label: l10n.playerStepAnalysis),
      (icon: Icons.record_voice_over, label: l10n.playerStepVoice),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(steps.length, (i) {
            final isDone = i < progress.currentStep;
            final isActive = i == progress.currentStep;
            // GPS step: yellow if done but not granted
            final isGpsWarning = i == 0 && isDone &&
                guide.lastLocationStatus != LocationPermissionStatus.granted;
            return Expanded(
              child: Row(
                children: [
                  _StepDot(
                    icon: steps[i].icon,
                    label: steps[i].label,
                    isDone: isDone,
                    isActive: isActive,
                    isWarning: isGpsWarning,
                    progress: isActive
                        ? progress.stepProgress
                        : (isDone ? 1.0 : 0.0),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: isDone ? Colors.white : Colors.white24,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        if (progress.estimatedSecondsRemaining != null) ...[
          const SizedBox(height: 6),
          Text(
            l10n.playerSecondsRemaining(progress.estimatedSecondsRemaining!.round()),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDone;
  final bool isActive;
  final bool isWarning;
  final double progress;

  const _StepDot({
    required this.icon,
    required this.label,
    required this.isDone,
    required this.isActive,
    required this.progress,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: progress < 0 ? 0.0 : progress),
                duration: const Duration(milliseconds: 400),
                builder: (_, value, __) => CircularProgressIndicator(
                  value: progress < 0 ? null : value,
                  strokeWidth: 2,
                  backgroundColor: Colors.white12,
                  color: isWarning ? Colors.orange : (isDone ? Colors.greenAccent : Colors.white),
                ),
              ),
            ),
            Icon(
              isDone ? Icons.check : icon,
              size: 16,
              color: isWarning
                  ? Colors.orange
                  : isDone
                      ? Colors.greenAccent
                      : isActive
                          ? Colors.white
                          : Colors.white38,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isWarning
                ? Colors.orange
                : isDone
                    ? Colors.greenAccent
                    : isActive
                        ? Colors.white
                        : Colors.white38,
          ),
        ),
      ],
    );
  }
}

class _StateLabel extends StatelessWidget {
  final GuideState state;
  const _StateLabel({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (state) {
      GuideState.locating => Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 8),
          Text(l10n.playerStateLocating, style: const TextStyle(color: Colors.white70)),
        ]).animate().fadeIn(),
      GuideState.analyzing => Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 8),
          Text(l10n.playerStateAnalyzing,
              style: const TextStyle(color: Colors.white70)),
        ]).animate().fadeIn(),
      GuideState.synthesizing => Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 8),
          Text(l10n.playerStateSynthesizing,
              style: const TextStyle(color: Colors.white70)),
        ]).animate().fadeIn(),
      GuideState.speaking => Row(children: [
          const Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(l10n.playerStateSpeaking, style: const TextStyle(color: Colors.white70)),
        ]).animate().fadeIn(),
      GuideState.paused => Row(children: [
          const Icon(Icons.pause_circle, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Text(l10n.playerStatePaused, style: const TextStyle(color: Colors.white54)),
        ]),
      GuideState.scriptReady => Row(children: [
          const Icon(Icons.text_snippet_outlined, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Text(l10n.playerStateScriptReady, style: const TextStyle(color: Colors.white54)),
        ]),
      _ => const SizedBox.shrink(),
    };
  }
}

class _FallbackBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _FallbackBanner({
      required this.icon, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
