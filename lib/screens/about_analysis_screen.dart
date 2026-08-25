import 'dart:io';
import 'dart:ui' as ui;
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../utils/date_format_utils.dart';
import '../widgets/kofi_button.dart';

class AboutAnalysisScreen extends StatelessWidget {
  final HistoryEntry entry;

  const AboutAnalysisScreen({super.key, required this.entry});

  /// Always get the latest version from HistoryService
  HistoryEntry _live(BuildContext context) {
    final history = context.watch<HistoryService>();
    return history.entries.firstWhere(
      (e) => e.id == entry.id,
      orElse: () => entry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = _live(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aboutAnalysisTitle),
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
        padding: const EdgeInsets.all(20),
        children: [
          // Image thumbnail — live.rotationQuarters, not entry's (this
          // screen already reads live for everything else below; entry
          // is only the value passed at navigation time and goes stale
          // the moment the photo is rotated from the detail screen).
          if (File(live.imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RotatedBox(
                quarterTurns: live.rotationQuarters,
                child: Image.file(File(live.imagePath),
                    height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 20),

          // Title
          Text(live.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          const _AiGeneratedBanner(),
          const SizedBox(height: 20),

          _Section(title: l10n.aboutAnalysisSectionDates, children: [
            _Row(l10n.aboutAnalysisCapture, formatLocalDateTime(live.createdAt, locale)),
            if (live.analyzedAt != null)
              _Row(l10n.aboutAnalysisAnalyzedAt,
                  formatLocalDateTime(live.analyzedAt!, locale)),
            if (live.analysisDurationMs != null)
              _Row(l10n.aboutAnalysisDuration,
                  '${(live.analysisDurationMs! / 1000).toStringAsFixed(1)}s'),
          ]),

          _Section(title: l10n.aboutAnalysisSectionModels, children: [
            _Row(l10n.aboutAnalysisModelAnalysis, live.aiModel ?? l10n.aboutAnalysisUnknown),
            _Row(l10n.aboutAnalysisModelTts, live.ttsModel ?? l10n.aboutAnalysisUnknown),
            _Row(l10n.aboutAnalysisImageSource, _sourceLabel(l10n, live.analysisSource)),
            if (live.aiFallback)
              _Row(
                l10n.aboutAnalysisAiFallback,
                l10n.aboutAnalysisAiFallbackValue(
                    live.aiModel ?? l10n.aboutAnalysisFallbackModelDefault),
              ),
            if (live.ttsFallback)
              _Row(l10n.aboutAnalysisTtsFallback, l10n.aboutAnalysisTtsFallbackValue),
            // #138
            if (live.scriptStyle != null)
              _Row(l10n.aboutAnalysisStyle, live.scriptStyle!),
            if (live.outputLanguage != null)
              _Row(l10n.aboutAnalysisLanguage, live.outputLanguage!),
            if (live.promptVersion != null)
              _Row(l10n.aboutAnalysisPromptVersion, live.promptVersion!),
          ]),

          _Section(title: l10n.aboutAnalysisSectionGeo, children: [
            _Row(l10n.aboutAnalysisGpsSource, _gpsSourceLabel(l10n, live.gpsSource)),
            if (live.gpsLatitude != null && live.gpsLongitude != null)
              _Row(l10n.aboutAnalysisCoordinates,
                  '${live.gpsLatitude!.toStringAsFixed(5)}, '
                  '${live.gpsLongitude!.toStringAsFixed(5)}'),
            if (live.gpsAddress != null && live.gpsAddress!.isNotEmpty)
              _Row(l10n.aboutAnalysisAddress, live.gpsAddress!
                  .replaceAll('Localisation GPS : ', '')
                  .split('(').last.replaceAll(')', '').trim()),
            _Row(l10n.aboutAnalysisWikipediaUsed,
                live.wikipediaUsed ? l10n.aboutAnalysisYes : l10n.aboutAnalysisNo),
          ]),

          _Section(title: l10n.aboutAnalysisSectionContent, children: [
            _Row(l10n.aboutAnalysisWordCount,
                live.wordCount?.toString() ?? l10n.aboutAnalysisUnknown),
            if (live.audioDurationEstimate.isNotEmpty)
              _Row(l10n.aboutAnalysisAudioDuration, live.audioDurationEstimate),
            _Row(l10n.aboutAnalysisStatus, _statusLabel(l10n, live.status)),
            if (live.audioPath != null)
              _Row(l10n.aboutAnalysisCachedAudio,
                  l10n.aboutAnalysisCachedAudioValue(live.ttsModel ?? '?')),
          ]),

          const SizedBox(height: 12),

          // Copy debug info
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.aboutAnalysisCopyDebugInfo),
            onPressed: () async {
              final debug = await _buildDebugInfo(live: live);
              Clipboard.setData(ClipboardData(text: debug));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.aboutAnalysisInfoCopied)),
                );
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Reads the raw EXIF orientation tag and the dimensions Flutter's
  /// decoder actually produced, to diagnose thumbnails that appear
  /// upside down/sideways in some screens (T88) — the tag alone doesn't
  /// say whether Skia already applied it (swapped width/height for a
  /// 90°/270° tag) or the file's orientation metadata is stale/wrong.
  /// Hex color at 5 fixed points (top/bottom/left/right-center, center)
  /// of the decoded [image] — a cheap way to eyeball its orientation from
  /// text alone (e.g. sky-colored top vs. ground-colored bottom) without
  /// needing to transfer the actual file (T88).
  Future<String> _samplePixels(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return 'unavailable';
    String colorAt(double xFrac, double yFrac) {
      final x = (image.width * xFrac).clamp(0, image.width - 1).toInt();
      final y = (image.height * yFrac).clamp(0, image.height - 1).toInt();
      final offset = (y * image.width + x) * 4;
      final r = byteData.getUint8(offset);
      final g = byteData.getUint8(offset + 1);
      final b = byteData.getUint8(offset + 2);
      return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }

    final top = colorAt(0.5, 0.05);
    final bottom = colorAt(0.5, 0.95);
    final left = colorAt(0.05, 0.5);
    final right = colorAt(0.95, 0.5);
    final center = colorAt(0.5, 0.5);
    return '$top / $bottom / $left / $right / $center';
  }

  Future<String> _imageDiagnostics(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) return 'file missing';
    try {
      final bytes = await file.readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      final orientationTag = exifData['Image Orientation']?.printable ?? 'no orientation tag';

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final decodedSize = '${image.width}x${image.height}';

      // Sample a few pixel colors from the frame Flutter actually decoded
      // (before any screen-specific rendering) — tells us whether the
      // *decoded* image is already upright or not, independent of
      // whatever the grid/player/about screens each do with it (T88).
      final pixelSamples = await _samplePixels(image);
      image.dispose();

      return 'EXIF orientation: $orientationTag\n'
          'Decoded size (Flutter): $decodedSize\n'
          'File size: ${bytes.length} bytes\n'
          'Pixel samples (top/bottom/left/right/center): $pixelSamples';
    } catch (e) {
      return 'error reading image: $e';
    }
  }

  Future<String> _buildDebugInfo({required HistoryEntry live}) async {
    final imageDiag = await _imageDiagnostics(live.imagePath);
    return '''AudioLens Debug Info
====================
Title: ${live.title}
Created: ${live.createdAt.toIso8601String()}
Analyzed: ${live.analyzedAt?.toIso8601String() ?? 'unknown'}
AI Model: ${live.aiModel ?? 'unknown'}
TTS Model: ${live.ttsModel ?? 'unknown'}
AI Fallback: ${live.aiFallback}
TTS Fallback: ${live.ttsFallback}
Script style: ${live.scriptStyle ?? 'unknown'}
Output language: ${live.outputLanguage ?? 'unknown'}
Prompt version: ${live.promptVersion ?? 'unknown'}
Analysis source: ${live.analysisSource ?? 'unknown'}
GPS source: ${live.gpsSource ?? 'unknown'}
GPS: ${live.gpsLatitude ?? 'null'}, ${live.gpsLongitude ?? 'null'}
Wikipedia: ${live.wikipediaUsed}
Word count: ${live.wordCount ?? 'unknown'}
Analysis duration: ${live.analysisDurationMs ?? 'unknown'}ms
Audio path: ${live.audioPath ?? 'none'}
Status: ${live.status.name}
Image path: ${live.imagePath}
$imageDiag
''';
  }

  String _sourceLabel(AppLocalizations l10n, String? source) => switch (source) {
    'camera' => l10n.aboutAnalysisSourceCamera,
    'gallery' => l10n.aboutAnalysisSourceGallery,
    'retry' => l10n.aboutAnalysisSourceRetry,
    'captured' => l10n.aboutAnalysisSourceCaptured,
    _ => l10n.aboutAnalysisUnknown,
  };

  String _gpsSourceLabel(AppLocalizations l10n, String? source) => switch (source) {
    'realtime' => l10n.aboutAnalysisGpsSourceRealtime,
    'exif' => l10n.aboutAnalysisGpsSourceExif,
    'map' => l10n.aboutAnalysisGpsSourceMap,
    'none' => l10n.aboutAnalysisGpsSourceNone,
    _ => l10n.aboutAnalysisUnknown,
  };

  String _statusLabel(AppLocalizations l10n, AnalysisStatus status) => switch (status) {
    AnalysisStatus.complete => l10n.aboutAnalysisStatusComplete,
    AnalysisStatus.pending => l10n.aboutAnalysisStatusPending,
    AnalysisStatus.failed => l10n.aboutAnalysisStatusFailed,
    AnalysisStatus.captured => l10n.aboutAnalysisStatusCaptured,
  };
}

class _AiGeneratedBanner extends StatelessWidget {
  const _AiGeneratedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.aboutAnalysisAiDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
                    fontSize: 13)),
          ),
          Expanded(
            // #154: tapping a single value copies just that value —
            // distinct from the bulk "Copier les infos de debug" button
            // below, which copies everything at once.
            child: InkWell(
              onTap: () => _copyValue(context),
              child: Text(value,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  void _copyValue(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.aboutAnalysisValueCopied(value)),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

