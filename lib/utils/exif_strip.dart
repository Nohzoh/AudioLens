import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Returns a path to a copy of [imagePath] with EXIF metadata cleared
/// (#328) — used when attaching a photo to an outgoing report sent to a
/// third party (Telegram feedback, #315), so GPS coordinates embedded in
/// the original capture can't leak alongside it. Never mutates the
/// original file, which is also what EXIF GPS extraction reads and what
/// gets saved to history — both need the untouched original.
///
/// On any decode/encode failure, falls back to [imagePath] unchanged —
/// better to send the original photo than to fail the report entirely
/// over a stripping hiccup.
Future<String> imagePathWithExifStripped(String imagePath) async {
  try {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return imagePath;

    decoded.exif = img.ExifData();
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/feedback_exif_stripped_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(tempPath).writeAsBytes(img.encodeJpg(decoded));
    return tempPath;
  } catch (_) {
    return imagePath;
  }
}
