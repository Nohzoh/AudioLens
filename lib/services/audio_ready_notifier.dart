import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Posts a local notification when a background-eligible analysis
/// finishes (T85) — success ("audio ready") or failure — so a result
/// isn't silently dropped when the user isn't actively watching the app.
/// Best-effort by design, same rationale as [AnalysisForegroundService]:
/// a notification hiccup must never break the actual analysis.
class AudioReadyNotifier {
  static const _channelId = 'analysis_result';
  static const _channelName = 'Résultat de l\'analyse';
  static const _notificationId = 4202;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Called with the entry ID carried in a "ready" notification's payload
  /// when the user taps it — only set when that entry's playback was
  /// deferred because the app was backgrounded at completion time. The app
  /// process stays alive throughout thanks to the T85 foreground service,
  /// so this plain (foreground) callback is enough — no background isolate
  /// handling needed.
  void Function(int entryId)? onPlayRequested;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = int.tryParse(response.payload ?? '');
          if (id != null) onPlayRequested?.call(id);
        },
      );
      _initialized = true;
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS runtime permission. Safe
  /// to call repeatedly (no-ops once granted or permanently denied) —
  /// intended to be called once, lazily, on the first analysis attempt.
  Future<void> requestPermissionIfNeeded() async {
    await _ensureInitialized();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  /// [payload], when set, is the ID of a history entry whose playback was
  /// deferred because the app was backgrounded when it finished — tapping
  /// the notification then starts playback for it (see [onPlayRequested]).
  /// Left null for the deliberate "script only" case (T16) — that
  /// notification must not trigger auto-play.
  Future<void> notifyReady({String? payload}) => _show(
        title: 'AudioLens',
        body: payload != null
            ? 'Votre audioguide est prêt. Touchez pour l\'écouter.'
            : 'Votre audioguide est prêt.',
        payload: payload,
      );

  Future<void> notifyFailed() =>
      _show(title: 'AudioLens', body: 'L\'analyse a échoué.');

  /// Only shows while the user isn't actively looking at the app —
  /// avoids a redundant popup on top of a screen already displaying the
  /// same result.
  Future<void> _show({required String title, required String body, String? payload}) async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    await _ensureInitialized();
    try {
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Best-effort — see class doc.
    }
  }
}
