import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/share_intent_service.dart';

/// #132 — ShareIntentService (T97) was the one service under lib/services/
/// with no dedicated test.
const _methodChannel = MethodChannel('audio_guide/share_intent');
const _eventChannel = EventChannel('audio_guide/share_intent_stream');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_eventChannel, null);
  });

  group('getInitialSharedImage', () {
    test('returns the path on a cold-start share', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_methodChannel, (call) async {
        expect(call.method, 'getInitialSharedImage');
        return '/tmp/shared_photo.jpg';
      });

      final path = await ShareIntentService.getInitialSharedImage();

      expect(path, '/tmp/shared_photo.jpg');
    });

    test('returns null when there was no cold-start share', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_methodChannel, (call) async => null);

      final path = await ShareIntentService.getInitialSharedImage();

      expect(path, isNull);
    });

    test('returns null gracefully on a platform error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_methodChannel, (call) async {
        throw PlatformException(code: 'ERROR', message: 'native failure');
      });

      final path = await ShareIntentService.getInitialSharedImage();

      expect(path, isNull);
    });

    test('returns null gracefully when no handler is registered at all', () async {
      final path = await ShareIntentService.getInitialSharedImage();

      expect(path, isNull);
    });
  });

  group('sharedImageStream', () {
    test('maps warm-start events to their image path', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        _eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('/tmp/warm_share.jpg');
            events.endOfStream();
          },
        ),
      );

      final paths = await ShareIntentService.sharedImageStream.toList();

      expect(paths, ['/tmp/warm_share.jpg']);
    });

    test('emits every share in order for multiple warm-start events', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        _eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('/tmp/first.jpg');
            events.success('/tmp/second.jpg');
            events.endOfStream();
          },
        ),
      );

      final paths = await ShareIntentService.sharedImageStream.toList();

      expect(paths, ['/tmp/first.jpg', '/tmp/second.jpg']);
    });
  });
}
