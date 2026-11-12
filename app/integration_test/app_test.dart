// End to end on an emulator against a real voice-bridge hub on the Mac.
//
//   VB_PORT=8766 VB_STATE_FILE=/tmp/vb-it.json ~/tools/voice-bridge/.venv/bin/vb-hub &
//   fvm flutter test integration_test --dart-define=HUB=http://10.0.2.2:8766
//
// The test plays Claude's side over HTTP (report, ask_user) and checks the app
// shows it, reads it aloud in the natural voice, and that an answer typed in
// the app reaches Claude. Speech, microphone and notifications are faked so no
// permission dialogs get in the way.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:voice_bridge/app.dart';
import 'package:voice_bridge/data/hub_api.dart';

import '../test/fakes.dart';

const hub = String.fromEnvironment('HUB', defaultValue: 'http://10.0.2.2:8766');

Future<Map<String, dynamic>> claude(String path, Map<String, dynamic> body) async {
  final res = await http.post(
    Uri.parse('$hub$path'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'key': 'it-session', 'cwd': '/work/demo-app', 'branch': 'main', ...body}),
  );
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('talks to a real hub: report, question, answer', (tester) async {
    final speaker = FakeSpeaker();
    final store = await fakeStore({'hubUrl': hub});
    await tester.pumpWidget(VoiceBridgeApp(
      deps: AppDeps(
        store: store,
        makeApi: HttpHubApi.new,
        makeSpeaker: () => speaker,
        listener: FakeListener(),
        alerts: FakeAlerts(),
      ),
    ));

    // Claude reports a milestone: the session appears, and it's read aloud as natural-voice audio.
    await tester.pump(const Duration(seconds: 2)); // let the live connection open
    await claude('/api/report', {'text': 'Integration test: step one done.'});
    await waitFor(tester, find.text('demo-app · main'));
    await waitFor(tester, find.text('Integration test: step one done.'));
    expect(speaker.said, isNotEmpty);
    expect(speaker.said.last.audio?.path, startsWith('/audio/'));

    // Claude asks; the app shows the question; we answer by typing.
    final answer = claude('/api/ask', {'text': 'Ship it from the emulator?'});
    await waitFor(tester, find.text('Ship it from the emulator?'));
    await tester.enterText(find.byKey(const Key('input')), 'yes from the emulator');
    await tester.tap(find.byKey(const Key('send')));
    final reply = await answer.timeout(const Duration(seconds: 15));
    expect(reply, {'status': 'answered', 'answer': 'yes from the emulator'});
    await waitFor(tester, find.text('Answer sent'));
  });
}
