import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/hub_api.dart';
import 'data/settings_store.dart';
import 'logic/bridge_cubit.dart';
import 'services/alerts.dart';
import 'services/listener.dart';
import 'services/speaker.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';

/// Everything that touches the device or the network, so tests can swap it.
class AppDeps {
  const AppDeps({
    required this.store,
    required this.makeApi,
    required this.makeSpeaker,
    required this.listener,
    required this.alerts,
  });

  final SettingsStore store;
  final HubApi Function(String url) makeApi;
  final Speaker Function() makeSpeaker;
  final VoiceListener listener;
  final Alerts alerts;
}

class VoiceBridgeApp extends StatefulWidget {
  const VoiceBridgeApp({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<VoiceBridgeApp> createState() => _VoiceBridgeAppState();
}

class _VoiceBridgeAppState extends State<VoiceBridgeApp> {
  late String? _url = widget.deps.store.hubUrl;
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.deps;
    final url = _url;
    return MaterialApp(
      title: 'Voice bridge',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: url == null || _changing
          ? SetupScreen(
              initialUrl: url,
              makeApi: d.makeApi,
              onConnected: (u) async {
                await d.store.setHubUrl(u);
                setState(() {
                  _url = u;
                  _changing = false;
                });
              },
            )
          : BlocProvider(
              // A new cubit (and connection) whenever the address changes.
              key: ValueKey(url),
              create: (_) => BridgeCubit(
                api: d.makeApi(url),
                store: d.store,
                speaker: d.makeSpeaker(),
                listener: d.listener,
                alerts: d.alerts,
              )..start(),
              child: HomeScreen(onChangeMac: () => setState(() => _changing = true)),
            ),
    );
  }
}
