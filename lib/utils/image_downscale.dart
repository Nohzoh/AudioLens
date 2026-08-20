import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Downscales/recompresses [file] for network upload (T113) — a modern
/// phone photo can be 10-20MB, which is real memory/GC pressure and, once
/// base64-encoded, ~33% larger again over the wire. Only used for the
/// Gemini API upload path: the original file is left untouched, since
/// it's also what EXIF GPS extraction reads and what gets saved to
/// history — both need full fidelity, and most decode/resize libraries
/// don't preserve EXIF tags through a re-encode.
///
/// Returns the original bytes unchanged if the image is already within
/// [maxWidth], or if decoding fails for any reason (better to upload the
/// original than to fail the whole analysis over a downscale hiccup).
Future<Uint8List> downscaleForUpload(
  File file, {
  required int maxWidth,
  required int quality,
}) async {
  final bytes = await file.readAsBytes();
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    if (decoded.width <= maxWidth) return bytes;

    final resized = img.copyResize(decoded, width: maxWidth);
    return img.encodeJpg(resized, quality: quality);
  } catch (_) {
    return bytes;
  }
}
