import 'package:flutter_test/flutter_test.dart';
import 'package:voice_bridge/data/hub_api.dart';
import 'package:voice_bridge/logic/bridge_cubit.dart';
import 'package:voice_bridge/logic/target.dart';

import 'fakes.dart';

void main() {
  late FakeApi api;
  late FakeSpeaker speaker;
  late FakeListener listener;
  late FakeAlerts alerts;
  late BridgeCubit cubit;

  Future<BridgeCubit> make([Map<String, Object> prefs = const {}]) async {
    api = FakeApi();
    speaker = FakeSpeaker();
    listener = FakeListener();
    alerts = FakeAlerts();
    cubit = BridgeCubit(api: api, store: await fakeStore(prefs), speaker: speaker, listener: listener, alerts: alerts);
    await cubit.start();
    return cubit;
  }

  Future<void> push(HubEvent e) async {
    api.controller.add(e);
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() => cubit.close());

  test('start loads voices, keeps the saved one, starts the keep-alive service', () async {
    await make({'voice': 'am_michael'});
    expect(cubit.state.naturalAvailable, isTrue);
    expect(cubit.state.voices.map((v) => v.id), ['af_heart', 'am_michael', 'phone']);
    expect(cubit.state.voice, 'am_michael');
    expect(alerts.keptAlive, isTrue);
  });

  test('connection, sessions and questions come from the hub', () async {
    await make();
    await push(const ConnectionChanged(true));
    await push(const StateSnapshot([sessionA], [question1]));
    expect(cubit.state.connected, isTrue);
    expect(cubit.state.sessions, [sessionA]);
    expect(cubit.state.target, const AnswerTarget('q1'));
  });

  test('new spoken messages are read in the natural voice; replays and duplicates are not', () async {
    await make();
    await push(MessageArrived(message(1)));
    await push(MessageArrived(message(1)));
    await push(MessageArrived(message(2, replay: true)));
    await push(MessageArrived(message(3, speak: false)));
    expect(cubit.state.feed.map((m) => m.id), [1, 2, 3]);
    expect(speaker.said, hasLength(1));
    expect(speaker.said.single.audio.toString(), 'https://hub/audio/1?voice=af_heart');
  });

  test('non-English text and the phone voice use the phone engine', () async {
    await make();
    await push(MessageArrived(message(1, natural: false)));
    await cubit.setVoice('phone');
    await push(MessageArrived(message(2)));
    expect(speaker.said.first.audio, isNull);
    expect(speaker.said.last.audio, isNull);
  });

  test('muted means silent', () async {
    await make();
    await cubit.setSound(false);
    await push(MessageArrived(message(1)));
    expect(speaker.said, isEmpty);
    expect(speaker.hushes, greaterThan(0));
  });

  test('a question notifies only while the app is in the background', () async {
    await make();
    await push(const StateSnapshot([sessionA], [question1]));
    await push(MessageArrived(message(1, kind: 'question', text: 'Delete the old folder?')));
    expect(alerts.questions, isEmpty);
    cubit.setForeground(false);
    await push(MessageArrived(message(2, kind: 'question', text: 'Delete the old folder?')));
    expect(alerts.questions, ['q1']);
  });

  test('answered questions clear their notification', () async {
    await make();
    await push(const StateSnapshot([sessionA], [question1]));
    await push(const StateSnapshot([sessionA], []));
    expect(alerts.cleared, ['q1']);
  });

  test('send answers the open question', () async {
    await make();
    await push(const StateSnapshot([sessionA], [question1]));
    expect(await cubit.send(' yes '), 'Answer sent');
    expectPost(api.posts.single, '/api/answer', {'qid': 'q1', 'text': 'yes'});
  });

  test('send messages a session and reports how it will be delivered', () async {
    await make();
    await push(const StateSnapshot([sessionA, sessionB], []));
    cubit.pick(const InstructTarget('b'));
    api.reply = (_, __) => {'ok': true, 'delivery': 'queued_idle'};
    expect(await cubit.send('run tests'), startsWith('Queued'));
    expectPost(api.posts.single, '/api/instruct', {'id': 'b', 'text': 'run tests'});
    expect(cubit.state.picked, isNull);
  });

  test('send with nobody to talk to fails clearly', () async {
    await make();
    expect(() => cubit.send('hi'), throwsA(isA<HubError>()));
  });

  test('session actions call the hub', () async {
    await make();
    await cubit.status();
    await cubit.status('a');
    await cubit.setPhoneMode('a', true);
    await cubit.rename('a', 'Backend');
    await cubit.forget('a');
    expect(api.posts.map((p) => p.$1), ['/api/status', '/api/status', '/api/phone_mode', '/api/label', '/api/forget']);
    expect(api.posts.first.$2, {'id': 'all'});
  });

  test('picking a voice saves it and plays a sample', () async {
    await make();
    await cubit.setVoice('am_michael');
    expect(cubit.state.voice, 'am_michael');
    expect(speaker.said.single.audio.toString(), 'https://hub/audio/0?voice=am_michael');
    expect(speaker.said.single.text, BridgeCubit.previewText);
  });

  test('listening hushes the speaker and reports words', () async {
    await make();
    final words = <String>[];
    expect(await cubit.startListening((w, _) => words.add(w)), isTrue);
    expect(cubit.state.listening, isTrue);
    expect(speaker.hushes, 1);
    listener.onWords!('hello', true);
    await cubit.stopListening();
    expect(words, ['hello']);
    expect(cubit.state.listening, isFalse);
  });

  test('no microphone means no listening', () async {
    await make();
    listener.available = false;
    expect(await cubit.startListening((_, __) {}), isFalse);
    expect(cubit.state.listening, isFalse);
  });

  test('turning keep-listening off stops the service and is remembered', () async {
    await make();
    await cubit.setKeepListening(false);
    expect(alerts.keptAlive, isFalse);
    expect(cubit.store.keepListening, isFalse);
  });
}
