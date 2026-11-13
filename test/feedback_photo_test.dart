import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:audiolens/services/feedback_service.dart';

// #541
void main() {
  test('the feedback photo loses its metadata and is downscaled', () {
    final original = img.Image(width: 3200, height: 1800);
    original.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(48, 1);
    original.exif.imageIfd['Model'] = img.IfdValueAscii('Pixel 10');
    final withExif = img.encodeJpg(original);
    expect(img.decodeJpgExif(withExif)?.isEmpty, isFalse);

    final clean = stripImageMetadata(withExif)!;
    final decoded = img.decodeJpg(clean)!;
    expect(decoded.width, 1600);
    expect(decoded.height, 900);
    final exif = img.decodeJpgExif(clean);
    expect(exif == null || exif.isEmpty, isTrue);
  });

  test('bytes that are not an image are left alone', () {
    expect(stripImageMetadata(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
