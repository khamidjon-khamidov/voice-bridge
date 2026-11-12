import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_bridge/app.dart';
import 'package:voice_bridge/data/hub_api.dart';

import 'fakes.dart';

void main() {
  late FakeApi api;
  late FakeSpeaker speaker;
  late FakeListener listener;

  Future<void> pumpApp(WidgetTester tester, {String? url = 'https://mac.ts.net'}) async {
    api = FakeApi();
    speaker = FakeSpeaker();
    listener = FakeListener();
    final store = await fakeStore({if (url != null) 'hubUrl': url});
    await tester.pumpWidget(VoiceBridgeApp(
      deps: AppDeps(
        store: store,
        makeApi: (_) => api,
        makeSpeaker: () => speaker,
        listener: listener,
        alerts: FakeAlerts(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> hub(WidgetTester tester, HubEvent e) async {
    api.controller.add(e);
    await tester.pumpAndSettle();
  }

  testWidgets('first run asks for the Mac address and connects', (tester) async {
    await pumpApp(tester, url: null);
    expect(find.text('Mac address'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hubUrl')), 'mac.ts.net/');
    await tester.tap(find.byKey(const Key('connect')));
    await tester.pumpAndSettle();
    expect(find.text('Sessions'.toUpperCase()), findsOneWidget);
  });

  testWidgets('an unreachable address shows a clear error', (tester) async {
    await pumpApp(tester, url: null);
    api.pingOk = false;
    await tester.tap(find.byKey(const Key('connect')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the hub"), findsOneWidget);
  });

  testWidgets('shows sessions, the open question and answers it', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('No Claude sessions yet'), findsOneWidget);
    await hub(tester, const ConnectionChanged(true));
    await hub(tester, const StateSnapshot([sessionA, sessionB], [question1]));

    expect(find.text('WAITING FOR YOU'), findsOneWidget);
    expect(find.text('Delete the old folder?'), findsOneWidget);
    expect(find.text('rd_monorepo · main'), findsOneWidget);
    expect(find.text('needs answer'), findsNothing); // sessionA is "working"
    expect(find.text('working'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('input')), 'yes');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expectPost(api.posts.last, '/api/answer', {'qid': 'q1', 'text': 'yes'});
    expect(find.text('Answer sent'), findsOneWidget);
  });

  testWidgets('Message button retargets the reply bar', (tester) async {
    await pumpApp(tester);
    await hub(tester, const StateSnapshot([sessionA, sessionB], []));
    await tester.tap(find.byKey(const Key('msg-b')));
    await tester.pumpAndSettle();
    final target = tester.widget<RichText>(find.descendant(of: find.byKey(const Key('target')), matching: find.byType(RichText)));
    expect(target.text.toPlainText(), 'Message to voice-bridge · main');
  });

  testWidgets('a failed action shows an error', (tester) async {
    await pumpApp(tester);
    await hub(tester, const StateSnapshot([sessionA], []));
    api.reply = (_, __) => throw const HubError("Couldn't reach the hub");
    await tester.tap(find.byKey(const Key('status-a')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach the hub"), findsOneWidget);
  });

  testWidgets('hold to talk fills the box and sends on release', (tester) async {
    await pumpApp(tester);
    await hub(tester, const StateSnapshot([sessionA], []));
    final talk = tester.getCenter(find.byKey(const Key('talk')));
    final gesture = await tester.startGesture(talk);
    await tester.pumpAndSettle();
    expect(find.textContaining('Listening'), findsOneWidget);
    listener.onWords!('run the tests', false);
    await gesture.up();
    await tester.pump();
    listener.onWords!('run the tests', true);
    await tester.pumpAndSettle();
    expectPost(api.posts.last, '/api/instruct', {'id': 'a', 'text': 'run the tests'});
  });

  testWidgets('settings: pick a voice and hear a sample', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    expect(find.text("CLAUDE'S VOICE"), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-am_michael')));
    await tester.pumpAndSettle();
    expect(speaker.said.last.audio.toString(), contains('voice=am_michael'));
  });
}
