import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:audiolens/utils/image_downscale.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('image_downscale_test');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Future<File> writeTestJpeg(String name, {required int width, required int height}) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 60, 200));
    final bytes = img.encodeJpg(image, quality: 90);
    final file = File('${tmpDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('downscales an image wider than maxWidth', () async {
    final file = await writeTestJpeg('big.jpg', width: 2000, height: 1000);

    final result = await downscaleForUpload(file, maxWidth: 500, quality: 80);

    final decoded = img.decodeImage(result)!;
    expect(decoded.width, 500);
    expect(decoded.height, 250); // aspect ratio preserved
    expect(result.length, lessThan(await file.length()));
  });

  test('leaves an image already within maxWidth unchanged', () async {
    final file = await writeTestJpeg('small.jpg', width: 300, height: 200);
    final originalBytes = await file.readAsBytes();

    final result = await downscaleForUpload(file, maxWidth: 1280, quality: 85);

    expect(result, orderedEquals(originalBytes));
  });

  test('falls back to the original bytes if decoding fails', () async {
    final file = File('${tmpDir.path}/not_an_image.jpg');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    final result = await downscaleForUpload(file, maxWidth: 500, quality: 80);

    expect(result, orderedEquals([1, 2, 3, 4, 5]));
  });
}
