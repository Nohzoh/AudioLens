import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A full-screen background photo that never crops away the subject.
///
/// `BoxFit.cover` alone (what both screens used before) fills the screen
/// by scaling until the shorter side fits and cropping the rest. For a
/// camera capture that's harmless — its aspect ratio nearly matches the
/// screen's. For a landscape photo picked from the gallery, the crop is
/// severe: filling a tall screen from a wide photo can discard most of
/// its width, cutting out the very thing the guide is describing (#151).
///
/// So the photo is drawn with [BoxFit.contain] — whole, uncropped — over
/// a blurred, zoomed copy of itself that fills the leftover bands. The
/// bands read as an intentional backdrop rather than empty black bars,
/// and stay visually tied to the photo since they're made from it.
///
/// The blurred layer is only built when it would actually be visible:
/// for a photo whose aspect ratio is close to the screen's, `contain` and
/// `cover` produce nearly the same result, and rendering a second
/// full-screen image plus a blur behind it would cost real frame time for
/// bands a couple of pixels wide.
class BackgroundPhoto extends StatefulWidget {
  final File file;

  /// Quarter turns clockwise to apply, 0-3 (#152).
  ///
  /// Applied here rather than to the file on disk, so the photo's EXIF
  /// (which GPS extraction reads) is never rewritten — see
  /// HistoryEntry.rotationQuarters.
  final int rotationQuarters;

  /// How far the photo's aspect ratio may differ from the screen's before
  /// the letterbox treatment kicks in, as a ratio of the two.
  ///
  /// 1.15 ≈ bands worth about 13% of the screen. Below that, cropping is
  /// mild enough that filling the screen looks better than banding it.
  static const double _letterboxThreshold = 1.15;

  const BackgroundPhoto({
    super.key,
    required this.file,
    this.rotationQuarters = 0,
  });

  @override
  State<BackgroundPhoto> createState() => _BackgroundPhotoState();
}

class _BackgroundPhotoState extends State<BackgroundPhoto> {
  late Future<Size> _sizeFuture;

  @override
  void initState() {
    super.initState();
    _sizeFuture = _decodeSize(widget.file);
  }

  @override
  void didUpdateWidget(BackgroundPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only redecode when the photo itself changes — resolving this once
    // per file (not once per build, as a bare FutureBuilder would) keeps
    // this cheap even while the parent rebuilds continuously, e.g. once
    // per spoken word during narration (PlayerScreen's word-progress
    // callback drives a setState on every TTS boundary).
    if (oldWidget.file.path != widget.file.path) {
      _sizeFuture = _decodeSize(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<Size>(
          future: _sizeFuture,
          builder: (context, snapshot) {
            final size = snapshot.data;
            // Until the size is known, cover — matching the previous
            // behavior — so there's no visible layout shift for the
            // common (camera capture) case where nothing changes anyway.
            if (size == null) {
              return _rotated(Image.file(widget.file, fit: BoxFit.cover));
            }

            // An odd number of quarter turns swaps the photo's effective
            // width and height, which flips whether it letterboxes at all
            // — so rotation has to be folded in before the divergence
            // check, not applied to the finished result.
            final rotated = widget.rotationQuarters.isOdd;
            final photoRatio =
                rotated ? size.height / size.width : size.width / size.height;
            final screenRatio = constraints.maxWidth / constraints.maxHeight;
            final divergence = photoRatio > screenRatio
                ? photoRatio / screenRatio
                : screenRatio / photoRatio;

            if (divergence < BackgroundPhoto._letterboxThreshold) {
              return _rotated(Image.file(widget.file, fit: BoxFit.cover));
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                // Blurred backdrop: the same photo, cropped to fill, then
                // blurred so the bands never compete with the real image.
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: _rotated(Image.file(widget.file, fit: BoxFit.cover)),
                ),
                // Darkened so the sharp photo above stays the focal point
                // even when the blurred copy is bright.
                Container(color: Colors.black.withValues(alpha: 0.35)),
                _rotated(Image.file(widget.file, fit: BoxFit.contain)),
              ],
            );
          },
        );
      },
    );
  }

  /// Applies [BackgroundPhoto.rotationQuarters], or returns [child]
  /// untouched at 0 so the common case adds no widget to the tree at all.
  Widget _rotated(Widget child) => widget.rotationQuarters % 4 == 0
      ? child
      : RotatedBox(quarterTurns: widget.rotationQuarters, child: child);

  /// Resolves just the intrinsic size of [file].
  ///
  /// Goes through Flutter's own image cache (rather than decoding the
  /// bytes separately) so this doesn't decode the photo a second time —
  /// the [Image.file] widgets above resolve to the same cache entry. The
  /// decoded [ui.Image] handle is disposed immediately after its
  /// dimensions are read: this method only ever needs the size, and an
  /// undisposed handle leaks native/GPU memory (the listener receives a
  /// cloned image it owns and must release, per ImageStreamListener's own
  /// contract — see about_analysis_screen.dart for the same pattern).
  static Future<Size> _decodeSize(File file) {
    final completer = Completer<Size>();
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ));
        }
        info.image.dispose();
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
