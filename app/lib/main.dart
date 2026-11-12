import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'data/hub_api.dart';
import 'data/settings_store.dart';
import 'services/alerts.dart';
import 'services/listener.dart';
import 'services/speaker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  final alerts = DeviceAlerts();
  await alerts.init();
  runApp(VoiceBridgeApp(
    deps: AppDeps(
      store: await SettingsStore.open(),
      makeApi: HttpHubApi.new,
      makeSpeaker: DeviceSpeaker.new,
      listener: DeviceListener(),
      alerts: alerts,
    ),
  ));
}
