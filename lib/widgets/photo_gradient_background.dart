import 'dart:io';
import 'package:flutter/material.dart';
import 'background_photo.dart';

/// Shared full-bleed photo + gradient vignette used by `PlayerScreen` and
/// `HistoryDetailScreen` (#147) — both stack [BackgroundPhoto] under an
/// [IgnorePointer]-wrapped gradient scrim so on-photo text/icons stay
/// legible regardless of what's in the photo.
///
/// The photo-mode gradient (shown when the photo is displayed
/// unobstructed, #145/#204) was already byte-identical between both
/// screens and stays fixed here. The "reading" gradient (shown behind
/// the title/script text) differs deliberately per screen — History's is
/// stronger at the very top too (T96, to protect its top-bar icons,
/// especially the red delete icon, over a bright photo) — so it stays
/// caller-supplied rather than forced to match.
class PhotoGradientBackground extends StatelessWidget {
  final File file;
  final int rotationQuarters;
  final bool photoMode;
  final List<Color> readingGradientColors;
  final List<double> readingGradientStops;

  const PhotoGradientBackground({
    super.key,
    required this.file,
    required this.photoMode,
    required this.readingGradientColors,
    required this.readingGradientStops,
    this.rotationQuarters = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (file.existsSync())
          BackgroundPhoto(
            file: file,
            rotationQuarters: rotationQuarters,
            zoomable: photoMode,
          ),
        // #204: IgnorePointer — a plain decorated Container reports a hit
        // test for its ENTIRE bounds regardless of visual (semi-)
        // transparency, so this purely-decorative overlay would otherwise
        // silently swallow gestures meant for BackgroundPhoto's own
        // InteractiveViewer, breaking pinch-to-zoom (#191).
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: photoMode
                    ? [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ]
                    : readingGradientColors,
                stops: photoMode
                    ? const [0.0, 0.15, 0.85, 1.0]
                    : readingGradientStops,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
