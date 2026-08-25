import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// #126: a small, non-interactive map preview of where a photo was taken —
/// takes bare coordinates rather than an `AudioGuideResult`/`HistoryEntry`,
/// so both `PlayerScreen` and `HistoryDetailScreen` can use it identically.
///
/// Mirrors `map_picker_screen.dart`'s `FlutterMap` config (same tile
/// source, `userAgentPackageName`) for visual consistency, but locked down
/// to a fixed zoom/center with all interaction disabled — this is a
/// preview to glance at, not something to pan/zoom.
class MiniMap extends StatelessWidget {
  final double latitude;
  final double longitude;

  const MiniMap({super.key, required this.latitude, required this.longitude});

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 120,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'io.nohzoh.audiolens',
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 32,
                height: 32,
                child:
                    const Icon(Icons.location_pin, color: Colors.red, size: 32),
              ),
            ]),
            // OSM tile usage policy requires visible attribution — a
            // pre-existing gap in map_picker_screen.dart's own FlutterMap,
            // fixed there too alongside this new one rather than repeated.
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
