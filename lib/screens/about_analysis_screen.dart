import 'dart:io';
import 'dart:ui' as ui;
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('À propos de cette analyse'),
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
          // Image thumbnail
          if (File(entry.imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(entry.imagePath),
                  height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
          const SizedBox(height: 20),

          // Title
          Text(live.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          const _AiGeneratedBanner(),
          const SizedBox(height: 20),

          _Section(title: 'DATES', children: [
            _Row('Capture', DateFormat('dd/MM/yyyy à HH:mm').format(live.createdAt)),
            if (live.analyzedAt != null)
              _Row('Analyse', DateFormat('dd/MM/yyyy à HH:mm').format(live.analyzedAt!)),
            if (live.analysisDurationMs != null)
              _Row('Durée d\'analyse', '${(live.analysisDurationMs! / 1000).toStringAsFixed(1)}s'),
          ]),

          _Section(title: 'MODÈLES', children: [
            _Row('Modèle d\'analyse', live.aiModel ?? 'Inconnu'),
            _Row('Modèle TTS', live.ttsModel ?? 'Inconnu'),
            _Row('Source image', _sourceLabel(live.analysisSource)),
            if (live.aiFallback)
              _Row('Fallback IA',
                  'Utilisé : ${live.aiModel ?? "modèle de secours"}'),
            if (live.ttsFallback)
              const _Row('Fallback TTS', 'Voix native (Gemini TTS indisponible)'),
          ]),

          _Section(title: 'GÉOLOCALISATION', children: [
            _Row('Source GPS', _gpsSourceLabel(live.gpsSource)),
            if (live.gpsLatitude != null && live.gpsLongitude != null)
              _Row('Coordonnées',
                  '${live.gpsLatitude!.toStringAsFixed(5)}, '
                  '${live.gpsLongitude!.toStringAsFixed(5)}'),
            if (live.gpsAddress != null && live.gpsAddress!.isNotEmpty)
              _Row('Adresse', live.gpsAddress!
                  .replaceAll('Localisation GPS : ', '')
                  .split('(').last.replaceAll(')', '').trim()),
            _Row('Wikipedia utilisé', live.wikipediaUsed ? 'Oui' : 'Non'),
          ]),

          _Section(title: 'CONTENU', children: [
            _Row('Mots', live.wordCount?.toString() ?? 'Inconnu'),
            if (live.audioDurationEstimate.isNotEmpty)
              _Row('Durée audio estimée', live.audioDurationEstimate),
            _Row('Statut', _statusLabel(live.status)),
            if (live.audioPath != null)
              _Row('Audio en cache', 'Oui (${live.ttsModel ?? '?'})'),
          ]),

          const SizedBox(height: 12),

          // Copy debug info
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copier les infos de debug'),
            onPressed: () async {
              final debug = await _buildDebugInfo(live: live);
              Clipboard.setData(ClipboardData(text: debug));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Infos copiées')),
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

  String _sourceLabel(String? source) => switch (source) {
    'camera' => '📷 Caméra',
    'gallery' => '🖼️ Galerie',
    'retry' => '🔄 Relancée',
    'captured' => '📥 Capture différée',
    _ => 'Inconnu',
  };

  String _gpsSourceLabel(String? source) => switch (source) {
    'realtime' => '📡 Temps réel',
    'exif' => '📷 Métadonnées EXIF',
    'map' => '🗺️ Choisie sur la carte',
    'none' => '❌ Non disponible',
    _ => 'Inconnu',
  };

  String _statusLabel(AnalysisStatus status) => switch (status) {
    AnalysisStatus.complete => '✅ Complète',
    AnalysisStatus.pending => '⏳ En attente',
    AnalysisStatus.failed => '❌ Échouée',
    AnalysisStatus.captured => '📥 Capturée (analyse non lancée)',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white38, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

