import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications for questions, and the foreground service that keeps the
/// connection and the voice alive while the screen is off.
abstract class Alerts {
  Future<void> init();

  /// Show a heads-up notification for a question.
  Future<void> question({required String qid, required String who, required String text});

  Future<void> clearQuestion(String qid);

  /// Start or stop the keep-alive service. [status] is its notification text.
  Future<void> keepAlive(bool on, {String status});
}

class DeviceAlerts implements Alerts {
  final _notes = FlutterLocalNotificationsPlugin();

  static const _questions = AndroidNotificationDetails(
    'questions',
    'Questions from Claude',
    channelDescription: 'Claude is waiting for your answer',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  @override
  Future<void> init() async {
    await _notes.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _notes
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'connection',
        channelName: 'Connection to your Mac',
        channelDescription: 'Keeps listening for Claude while the screen is off',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: true,
      ),
    );
  }

  int _id(String qid) => qid.hashCode & 0x7fffffff;

  @override
  Future<void> question({required String qid, required String who, required String text}) => _notes.show(
        id: _id(qid),
        title: who.isEmpty ? 'Claude asks' : '$who asks',
        body: text,
        notificationDetails: const NotificationDetails(android: _questions),
      );

  @override
  Future<void> clearQuestion(String qid) => _notes.cancel(id: _id(qid));

  bool _starting = false;

  @override
  Future<void> keepAlive(bool on, {String status = 'Listening for Claude'}) async {
    final running = await FlutterForegroundTask.isRunningService;
    if (!on) {
      if (running) await FlutterForegroundTask.stopService();
      return;
    }
    if (running) {
      await FlutterForegroundTask.updateService(notificationTitle: 'Voice bridge', notificationText: status);
      return;
    }
    // Hub updates arrive every few seconds; start (and ask about battery) only once.
    if (_starting) return;
    _starting = true;
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      await FlutterForegroundTask.startService(
        serviceId: 300,
        serviceTypes: [ForegroundServiceTypes.mediaPlayback],
        notificationTitle: 'Voice bridge',
        notificationText: status,
        callback: startKeepAlive,
      );
    } finally {
      _starting = false;
    }
  }
}

/// The service only keeps the process (and its network and audio) alive;
/// all the work stays in the app itself, so the handler does nothing.
@pragma('vm:entry-point')
void startKeepAlive() => FlutterForegroundTask.setTaskHandler(_KeepAlive());

class _KeepAlive extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
