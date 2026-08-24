import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:audiolens/widgets/background_photo.dart';

/// #191 — pinch-to-zoom, gated by [BackgroundPhoto.zoomable] so it's only
/// active in "photo mode" (no script overlay competing for gestures).
void main() {
  late Directory tmpDir;
  late File imageFile;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('background_photo_test');
    final placeholder = img.Image(width: 4, height: 4);
    img.fill(placeholder, color: img.ColorRgb8(80, 40, 160));
    imageFile = File(join(tmpDir.path, 'photo.jpg'))
      ..writeAsBytesSync(img.encodeJpg(placeholder));
  });

  tearDown(() => tmpDir.deleteSync(recursive: true));

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: child)),
      );

  testWidgets('is not zoomable by default', (tester) async {
    await tester.pumpWidget(wrap(BackgroundPhoto(file: imageFile)));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('becomes zoomable when zoomable: true', (tester) async {
    await tester.pumpWidget(wrap(BackgroundPhoto(file: imageFile, zoomable: true)));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('drops the InteractiveViewer again when zoomable flips back to false',
      (tester) async {
    await tester.pumpWidget(wrap(BackgroundPhoto(file: imageFile, zoomable: true)));
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.pumpWidget(wrap(BackgroundPhoto(file: imageFile, zoomable: false)));
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
