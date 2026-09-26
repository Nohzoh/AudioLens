import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/history_service.dart';
import '../utils/app_logger.dart';
import 'history_screen.dart';

/// #423: analyses sharing (almost) the same spot — one marker on the map.
/// Several photos taken in the same room of a museum would otherwise
/// stack exactly on top of each other, leaving all but one untappable.
class AnalysisMapGroup {
  final LatLng point;
  final List<HistoryEntry> entries;
  const AnalysisMapGroup(this.point, this.entries);
}

/// #423: the complete analyses among [entries] that have coordinates,
/// grouped by position rounded to 4 decimals (~11 m). Captured, pending
/// and failed entries are left out: they have no analysis to open yet.
/// Order within a group follows [entries] (history order, newest first).
List<AnalysisMapGroup> groupAnalysesForMap(List<HistoryEntry> entries) {
  final groups = <String, List<HistoryEntry>>{};
  for (final e in entries) {
    if (e.status != AnalysisStatus.complete ||
        e.gpsLatitude == null ||
        e.gpsLongitude == null) {
      continue;
    }
    final key = '${e.gpsLatitude!.toStringAsFixed(4)},'
        '${e.gpsLongitude!.toStringAsFixed(4)}';
    (groups[key] ??= []).add(e);
  }
  return [
    for (final list in groups.values)
      AnalysisMapGroup(
          LatLng(list.first.gpsLatitude!, list.first.gpsLongitude!), list),
  ];
}

/// #423: every geolocated analysis on one map, opened from the history
/// screen with its active favorites/collection filter.
///
/// Same tile source, `userAgentPackageName` and OSM attribution as
/// `MiniMap` / `MapPickerScreen`. Reads [HistoryService] live rather than
/// taking a snapshot of entries, so an analysis deleted from the detail
/// screen is gone from the map on the way back.
class AnalysesMapScreen extends StatefulWidget {
  final bool favoritesOnly;
  final int? collectionId;

  const AnalysesMapScreen(
      {super.key, this.favoritesOnly = false, this.collectionId});

  @override
  State<AnalysesMapScreen> createState() => _AnalysesMapScreenState();
}

class _AnalysesMapScreenState extends State<AnalysesMapScreen> {
  static const double _singlePointZoom = 15;
  static const double _maxFitZoom = 16;

  @override
  void initState() {
    super.initState();
    AppLogger.nav('AnalysesMapScreen opened (favoritesOnly: '
        '${widget.favoritesOnly}, collection: ${widget.collectionId})');
  }

  @override
  void dispose() {
    AppLogger.nav('AnalysesMapScreen closed');
    super.dispose();
  }

  String _title(AppLocalizations l10n, HistoryService history) {
    if (widget.favoritesOnly) return l10n.historyFavoritesFilter;
    final id = widget.collectionId;
    if (id != null) {
      for (final c in history.collections) {
        if (c.id == id) return c.name;
      }
    }
    return l10n.analysesMapTitle;
  }

  MapOptions _options(List<AnalysisMapGroup> groups) {
    if (groups.length == 1) {
      return MapOptions(
          initialCenter: groups.single.point, initialZoom: _singlePointZoom);
    }
    return MapOptions(
      initialCameraFit: CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([for (final g in groups) g.point]),
        padding: const EdgeInsets.all(56),
        maxZoom: _maxFitZoom,
      ),
    );
  }

  Future<void> _showGroup(BuildContext context, AnalysisMapGroup group) async {
    final entry = await showModalBottomSheet<HistoryEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupSheet(group: group),
    );
    if (entry == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoryDetailScreen(entry: entry)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer<HistoryService>(
      builder: (context, history, _) {
        final groups = groupAnalysesForMap(filterHistoryEntries(history,
            favoritesOnly: widget.favoritesOnly,
            collectionId: widget.collectionId));
        return Scaffold(
          appBar: AppBar(title: Text(_title(l10n, history))),
          body: groups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.12)),
                        const SizedBox(height: 16),
                        Text(
                          l10n.analysesMapEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.38),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : FlutterMap(
                  // Keyed on the set of points: the initial camera fit only
                  // applies on first build, so a change in what's shown
                  // (an entry deleted from the detail screen) re-fits.
                  key: ValueKey(groups.map((g) => g.point).join(';')),
                  options: _options(groups),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'io.nohzoh.audiolens',
                    ),
                    MarkerLayer(markers: [
                      for (final g in groups)
                        Marker(
                          point: g.point,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: _GroupMarker(
                            count: g.entries.length,
                            onTap: () => _showGroup(context, g),
                          ),
                        ),
                    ]),
                    // OSM tile usage policy requires visible attribution.
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _GroupMarker extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _GroupMarker({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Icon(Icons.location_pin, color: Colors.red, size: 40),
          if (count > 1)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red, width: 1.5),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Preview of a marker's analyses (thumbnail, title, date); tapping one
/// pops it back to [AnalysesMapScreen], which opens its detail.
class _GroupSheet extends StatelessWidget {
  final AnalysisMapGroup group;
  const _GroupSheet({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat('d MMM yyyy · HH:mm', locale);
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final e in group.entries)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: File(e.imagePath).existsSync()
                        ? RotatedBox(
                            quarterTurns: e.rotationQuarters,
                            child: Image.file(File(e.imagePath),
                                fit: BoxFit.cover),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_not_supported),
                          ),
                  ),
                ),
                title:
                    Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(format.format(e.createdAt)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, e),
              ),
          ],
        ),
      ),
    );
  }
}
