import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Returns a path to save to the gallery that reflects a manual rotation
/// (#152/#183), without mutating the original file on disk.
///
/// [HistoryEntry.rotationQuarters] is deliberately display-only — the
/// same image file is what EXIF GPS extraction reads, so baking the
/// rotation into it would mean re-preserving EXIF on every rotation and
/// risking the user's original photo on a failed write. "Save to
/// gallery" is the one place that distinction actually matters to the
/// user: without this, the exported photo silently doesn't match what
/// they just saw and confirmed on screen.
///
/// Returns [imagePath] unchanged when [rotationQuarters] is 0 (the
/// overwhelmingly common case), so the normal save path stays exactly
/// as cheap as it already was. On any decode/encode failure, also falls
/// back to the original path — better to save an unrotated photo than
/// to fail the save entirely over a rotation hiccup.
Future<String> imagePathForGallerySave(
  String imagePath,
  int rotationQuarters,
) async {
  if (rotationQuarters == 0) return imagePath;

  try {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return imagePath;

    final rotated = img.copyRotate(decoded, angle: rotationQuarters * 90);
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/rotated_export_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(tempPath).writeAsBytes(img.encodeJpg(rotated));
    return tempPath;
  } catch (_) {
    return imagePath;
  }
}
