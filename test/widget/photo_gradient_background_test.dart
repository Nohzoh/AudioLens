import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart';
import 'package:audiolens/widgets/background_photo.dart';
import 'package:audiolens/widgets/photo_gradient_background.dart';

/// #147 — shared between player_screen.dart and history_screen.dart. The
/// photo-mode gradient is fixed (verified byte-identical between both
/// screens before this extraction); the "reading" gradient stays
/// caller-supplied since it deliberately differs per screen (T96).
void main() {
  late Directory tmpDir;
  late File imageFile;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('photo_gradient_background_test');
    final placeholder = img.Image(width: 4, height: 4);
    img.fill(placeholder, color: img.ColorRgb8(80, 40, 160));
    imageFile = File(join(tmpDir.path, 'photo.jpg'))
      ..writeAsBytesSync(img.encodeJpg(placeholder));
  });

  tearDown(() => tmpDir.deleteSync(recursive: true));

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: child)),
      );

  testWidgets('renders the background photo and reading gradient by default',
      (tester) async {
    await tester.pumpWidget(wrap(PhotoGradientBackground(
      file: imageFile,
      photoMode: false,
      readingGradientColors: const [Colors.transparent, Colors.black],
      readingGradientStops: const [0.25, 0.75],
    )));
    await tester.pump();

    expect(find.byType(BackgroundPhoto), findsOneWidget);
    final container =
        tester.widget<Container>(find.byType(Container).first);
    final gradient = (container.decoration as BoxDecoration).gradient
        as LinearGradient;
    expect(gradient.stops, const [0.25, 0.75]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches to the shared photo-mode gradient when photoMode is true',
      (tester) async {
    await tester.pumpWidget(wrap(PhotoGradientBackground(
      file: imageFile,
      photoMode: true,
      readingGradientColors: const [Colors.transparent, Colors.black],
      readingGradientStops: const [0.25, 0.75],
    )));
    await tester.pump();

    final container =
        tester.widget<Container>(find.byType(Container).first);
    final gradient = (container.decoration as BoxDecoration).gradient
        as LinearGradient;
    expect(gradient.stops, const [0.0, 0.15, 0.85, 1.0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skips BackgroundPhoto entirely when the file does not exist',
      (tester) async {
    await tester.pumpWidget(wrap(PhotoGradientBackground(
      file: File('/nonexistent/photo.jpg'),
      photoMode: false,
      readingGradientColors: const [Colors.transparent, Colors.black],
      readingGradientStops: const [0.25, 0.75],
    )));
    await tester.pump();

    expect(find.byType(BackgroundPhoto), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
