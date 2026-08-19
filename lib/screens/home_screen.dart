import 'dart:async';
import 'dart:io';
import '../utils/analysis_runner.dart';
import '../services/exif_location_service.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/audio_guide_service.dart';
import '../services/history_service.dart';
import '../services/location_service.dart';
import '../services/remote_config_service.dart';
import '../services/settings_service.dart';
import '../services/share_intent_service.dart';
import '../widgets/kofi_button.dart';
import 'history_screen.dart';
import 'map_picker_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  LocationPermissionStatus _permissionStatus = LocationPermissionStatus.granted;
  StreamSubscription<String>? _shareIntentSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();
    _initShareIntentHandling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareIntentSubscription?.cancel();
    super.dispose();
  }

  /// T97: picks up a photo shared to AudioLens from another app, both for
  /// a cold start (app launched directly by the share) and a warm start
  /// (app was already running when the share arrived).
  Future<void> _initShareIntentHandling() async {
    final initialPath = await ShareIntentService.getInitialSharedImage();
    if (initialPath != null) await _handleSharedImage(initialPath);
    _shareIntentSubscription =
        ShareIntentService.sharedImageStream.listen(_handleSharedImage);
  }

  Future<void> _handleSharedImage(String path) async {
    if (!mounted) return;
    final imageFile = File(path);
    if (!imageFile.existsSync()) return;
    await _processImageForAnalysis(imageFile, analysisSource: 'share');
  }

  // Re-check permission when user comes back from settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationPermission();
    }
  }

  Future<void> _checkLocationPermission() async {
    final status = await LocationService.checkPermission();
    if (mounted) setState(() => _permissionStatus = status);
  }

  Future<void> _pickImage(ImageSource source, {bool analyzeNow = true}) async {
    final picker = ImagePicker();
    final cfg = RemoteConfigService.current;
    final xFile = await picker.pickImage(
      source: source,
      imageQuality: cfg.imageQuality,
      maxWidth: cfg.imageMaxWidth.toDouble(),
    );
    if (xFile == null || !mounted) return;

    final imageFile = File(xFile.path);

    if (!analyzeNow) {
      await _captureOnly(imageFile);
      return;
    }

    await _processImageForAnalysis(
      imageFile,
      analysisSource: source == ImageSource.camera ? 'camera' : 'gallery',
    );
  }

  /// Processes an image file as an analysis input — shared by the gallery/
  /// camera picker (_pickImage) and incoming shared photos (T97), both of
  /// which need the same "check EXIF, offer the map picker if there's
  /// none, save as a pending entry, launch analysis" flow.
  Future<void> _processImageForAnalysis(
    File imageFile, {
    required String analysisSource, // 'camera' | 'gallery' | 'share'
  }) async {
    final history = context.read<HistoryService>();

    // A gallery/shared photo could be old, or from anywhere — unlike a
    // fresh camera capture, falling back to the device's current position
    // when there's no EXIF GPS would be misleading. Offer picking the
    // real spot on a map instead (T87); if declined, behavior is
    // unchanged (LocationContextResolver falls back to real-time GPS).
    ({double lat, double lon, String source})? knownCoordinates;
    if (analysisSource != 'camera') {
      final exifCoords = await ExifLocationService.readGpsFromImage(imageFile);
      if (exifCoords == null && mounted) {
        final picked = await Navigator.push<LatLng>(
          context,
          MaterialPageRoute(builder: (_) => const MapPickerScreen()),
        );
        if (picked != null) {
          knownCoordinates = (lat: picked.latitude, lon: picked.longitude, source: 'map');
        }
      }
    }
    if (!mounted) return;

    final pendingEntry = await history.addPendingEntry(imagePath: imageFile.path);
    await _runAnalysis(
      imageFile: imageFile,
      entryId: pendingEntry.id!,
      source: analysisSource,
      knownCoordinates: knownCoordinates,
      // imageFile is a temp file (image_picker's own capture, or a copy
      // extracted from a share intent) — addPendingEntry already copied
      // it to permanent history storage, so once PlayerScreen is done
      // with it (display + "save to gallery"), it's just an orphaned
      // temp file (T45).
      isTempImage: true,
    );
  }

  /// Saves the photo + raw GPS only — no reverse geocoding, Wikipedia, AI,
  /// or TTS — so the whole capture stays offline (T78). The analysis can
  /// be launched later (e.g. once back on wifi) from the history entry.
  Future<void> _captureOnly(File imageFile) async {
    final history = context.read<HistoryService>();

    final exifCoords = await ExifLocationService.readGpsFromImage(imageFile);
    double? lat = exifCoords?.lat;
    double? lon = exifCoords?.lon;
    var gpsSource = exifCoords != null ? 'exif' : 'none';

    if (exifCoords == null) {
      final raw = await LocationService.getCurrentRawCoordinates();
      if (raw != null) {
        lat = raw.lat;
        lon = raw.lon;
        gpsSource = 'realtime';
      }
    }

    await history.addCapturedEntry(
      imagePath: imageFile.path,
      gpsLatitude: lat,
      gpsLongitude: lon,
      gpsSource: gpsSource,
    );

    // imageFile is image_picker's own temp capture — addCapturedEntry
    // already copied it to permanent history storage, and unlike the
    // analyze-now flow, nothing else needs it after this point (T45).
    try {
      if (imageFile.existsSync()) imageFile.deleteSync();
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.homeCapturedSnackbar),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showLocationDeniedForeverDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.homeLocationDisabledTitle),
        content: Text(l10n.homeLocationDisabledContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.homeLater),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              LocationService.openSettings();
            },
            child: Text(l10n.homeOpenSettings),
          ),
        ],
      ),
    );
  }

  /// Retries a failed analysis, reusing whatever location was resolved for
  /// the original attempt (live GPS, EXIF, or a manually picked map point)
  /// instead of re-resolving the device's current position from scratch —
  /// see HistoryService.failEntry's doc.
  Future<void> _retryAnalysis(HistoryEntry entry) async {
    final imageFile = File(entry.imagePath);
    if (!imageFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.homeImageNotFound)),
      );
      return;
    }

    await _runAnalysis(
      imageFile: imageFile,
      entryId: entry.id!,
      source: 'retry',
      knownCoordinates: knownCoordinatesFromEntry(entry),
    );
  }

  /// Launches the analysis for a captured entry (T78), using the raw GPS
  /// saved at capture time rather than the device's current location.
  Future<void> _launchAnalysisForCaptured(HistoryEntry entry) async {
    final imageFile = File(entry.imagePath);
    if (!imageFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.homeImageNotFound)),
      );
      return;
    }

    await _runAnalysis(
      imageFile: imageFile,
      entryId: entry.id!,
      source: 'captured',
      knownCoordinates: knownCoordinatesFromEntry(entry),
    );
  }

  Future<void> _runAnalysis({
    required File imageFile,
    required int entryId,
    required String source,
    ({double lat, double lon, String source})? knownCoordinates,
    bool isTempImage = false,
  }) async {
    await runAnalysisAndNavigate(
      context: context,
      imageFile: imageFile,
      entryId: entryId,
      source: source,
      knownCoordinates: knownCoordinates,
      deleteImageOnDispose: isTempImage,
    );
    if (mounted) {
      final guide = context.read<AudioGuideService>();
      setState(() => _permissionStatus = guide.lastLocationStatus);
    }
  }

  Future<void> _showImageSourceDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<({ImageSource source, bool analyzeNow})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.homeTakePhoto),
              onTap: () => Navigator.pop(context, (source: ImageSource.camera, analyzeNow: true)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.homeChooseFromGallery),
              onTap: () => Navigator.pop(context, (source: ImageSource.gallery, analyzeNow: true)),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(l10n.homeCaptureOnly),
              subtitle: Text(l10n.homeCaptureOnlySubtitle),
              onTap: () => Navigator.pop(context, (source: ImageSource.camera, analyzeNow: false)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (choice != null) _pickImage(choice.source, analyzeNow: choice.analyzeNow);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHigh,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('🎧 AudioLens',
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Consumer<SettingsService>(
                      // T86: the default grey (Colors.grey[600], chosen to
                      // read as subtly de-emphasized against the plain
                      // AppBars on the other screens) has too little
                      // contrast against this screen's surface gradient —
                      // reported as visibly more washed out than the
                      // history/settings icons right next to it. Matching
                      // their color keeps it readable here without
                      // affecting the other 5 screens.
                      builder: (context, settings, _) => KofiButton(
                        show: settings.showKofiButton,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history),
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const HistoryScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Provider + location status row
                Row(
                  children: [
                    Consumer<AudioGuideService>(
                      builder: (context, guide, _) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              guide.providerName.contains('Nano')
                                  ? Icons.phone_android
                                  : Icons.cloud_outlined,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              guide.providerName.isEmpty
                                  ? l10n.homeInitializing
                                  : guide.providerName,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Location status badge
                    if (_permissionStatus ==
                        LocationPermissionStatus.deniedForever)
                      GestureDetector(
                        onTap: _showLocationDeniedForeverDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(l10n.homeGpsDisabled,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.orange)),
                            ],
                          ),
                        ),
                      )
                    else if (_permissionStatus ==
                        LocationPermissionStatus.denied)
                      GestureDetector(
                        onTap: () async {
                          await _checkLocationPermission();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Text(l10n.homeGpsAllow,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.orange)),
                            ],
                          ),
                        ),
                      )
                    else if (_permissionStatus ==
                        LocationPermissionStatus.granted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(l10n.homeGpsActive,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.green)),
                          ],
                        ),
                      ),
                  ],
                ),

                // History preview
                Consumer<HistoryService>(
                  builder: (context, history, _) {
                    if (history.entries.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(l10n.homeRecentlyVisited,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white38,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => Navigator.push(context,
                                  MaterialPageRoute(
                                      builder: (_) => const HistoryScreen()),
                                ),
                                child: Text(l10n.homeSeeAll,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: history.entries.take(6).length,
                            itemBuilder: (context, i) {
                              final entry = history.entries[i];
                              final isPending = entry.isPending;
                              final isFailed = entry.status == AnalysisStatus.failed;
                              final isCaptured = entry.isCaptured;
                              final isDimmed = isPending || isFailed || isCaptured;
                              return GestureDetector(
                                key: ValueKey(entry.id),
                                onTap: () {
                                  if (isPending || isFailed) {
                                    // Retry analysis
                                    _retryAnalysis(entry);
                                  } else if (isCaptured) {
                                    _launchAnalysisForCaptured(entry);
                                  } else {
                                    Navigator.push(context,
                                      MaterialPageRoute(
                                        builder: (_) => HistoryDetailScreen(entry: entry),
                                      ),
                                    );
                                  }
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Image — greyed if pending/failed/captured
                                      ColorFiltered(
                                        colorFilter: isDimmed
                                            ? const ColorFilter.matrix([
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0,      0,      0,      1, 0,
                                              ])
                                            : const ColorFilter.mode(
                                                Colors.transparent,
                                                BlendMode.multiply),
                                        child: File(entry.imagePath).existsSync()
                                            ? Image.file(File(entry.imagePath), fit: BoxFit.cover)
                                            : Container(color: theme.colorScheme.surfaceContainerHigh),
                                      ),
                                      // Status overlay
                                      if (isPending)
                                        const Center(child: SizedBox(width: 24, height: 24,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)))
                                      else if (isFailed)
                                        const Center(child: Icon(Icons.refresh, color: Colors.white, size: 28))
                                      else if (isCaptured)
                                        const Center(child: Icon(Icons.cloud_off_outlined, color: Colors.white70, size: 28)),
                                      // Title at bottom
                                      Positioned(
                                        bottom: 0, left: 0, right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                                            ),
                                          ),
                                          child: Text(
                                            isFailed
                                                ? l10n.homeTapToRetry
                                                : isCaptured
                                                    ? l10n.homeTapToAnalyze
                                                    : entry.title,
                                            style: TextStyle(
                                              color: isFailed
                                                  ? Colors.orangeAccent
                                                  : isCaptured
                                                      ? Colors.white70
                                                      : Colors.white,
                                              fontSize: 9, height: 1.2,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt_outlined,
                            size: 80, color: Colors.white12),
                        const SizedBox(height: 16),
                        Text(
                          l10n.homeEmptyStateHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 15,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),

                FilledButton.icon(
                  onPressed: _showImageSourceDialog,
                  icon: const Icon(Icons.camera_alt, size: 24),
                  label: Text(l10n.homeTakePhoto,
                      style: const TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 64),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ).animate().scale(delay: 200.ms),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


