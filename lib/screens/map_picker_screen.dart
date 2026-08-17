import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../l10n/app_localizations.dart';
import '../services/location_service.dart';

/// Lets the user tap a spot on a map to indicate where a photo was taken
/// (T87) — used when a gallery-picked photo has no GPS in its EXIF, where
/// falling back to the device's current position would be misleading (the
/// photo could be old, or from anywhere).
///
/// Returns the picked [LatLng], or null if the user backed out without
/// picking a spot.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _defaultCenter = LatLng(48.8566, 2.3522); // Paris fallback

  final _mapController = MapController();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    // Best-effort: center on the device's current position if available,
    // purely as a convenient starting point — never used as the actual
    // answer, unlike the realtime-GPS fallback this screen replaces.
    LocationService.getCurrentLocation().then((result) {
      final info = result.info;
      if (info != null && mounted) {
        _mapController.move(LatLng(info.latitude, info.longitude), 13);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapPickerTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.mapPickerSkip),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 5,
              onTap: (_, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'io.nohzoh.audiolens',
              ),
              if (_picked != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                  ),
                ]),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: FilledButton(
                onPressed: _picked == null
                    ? null
                    : () => Navigator.pop(context, _picked),
                child: Text(_picked == null
                    ? l10n.mapPickerHint
                    : l10n.mapPickerConfirm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
