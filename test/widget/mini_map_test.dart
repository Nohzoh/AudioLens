import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/widgets/mini_map.dart';

/// #126 — mounts with a known lat/lon and confirms it renders without
/// throwing. Bounded pump() only, never pumpAndSettle(): tile network
/// calls aren't mocked in this suite (same reasoning as
/// map_picker_screen_test.dart, the only other FlutterMap usage here).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a non-interactive map centered on the given coordinates',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MiniMap(latitude: 48.8606, longitude: 2.3376),
    ));
    await tester.pump();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, 48.8606);
    expect(map.options.initialCenter.longitude, 2.3376);
    expect(map.options.interactionOptions.flags, InteractiveFlag.none);
    // Marker/RichAttributionWidget aren't necessarily preserved as their
    // own widget types in flutter_map's render tree (Marker in particular
    // is a plain config object passed to MarkerLayer, not rendered
    // directly) — asserting FlutterMap mounted with the right options and
    // took no exception is the meaningful, non-brittle check here.
    expect(tester.takeException(), isNull);
  });
}
