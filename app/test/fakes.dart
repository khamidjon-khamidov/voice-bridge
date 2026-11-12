import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_bridge/data/hub_api.dart';
import 'package:voice_bridge/data/models.dart';
import 'package:voice_bridge/data/settings_store.dart';
import 'package:voice_bridge/services/alerts.dart';
import 'package:voice_bridge/services/listener.dart';
import 'package:voice_bridge/services/speaker.dart';

class FakeApi implements HubApi {
  final controller = StreamController<HubEvent>.broadcast();
  final posts = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> Function(String path, Map<String, dynamic> body) reply = (_, __) => {'ok': true};
  VoiceList voiceList = const VoiceList(
    available: true,
    defaultVoice: 'af_heart',
    voices: [VoiceOption('af_heart', 'Heart · US woman'), VoiceOption('am_michael', 'Michael · US man')],
  );
  bool pingOk = true;

  @override
  Stream<HubEvent> events() => controller.stream;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    posts.add((path, body));
    return reply(path, body);
  }

  @override
  Future<VoiceList> voices() async => voiceList;

  @override
  Uri audioUri(int messageId, String voice) => Uri.parse('https://hub/audio/$messageId?voice=$voice');

  @override
  Future<bool> ping() async => pingOk;

  @override
  void close() {}
}

class FakeSpeaker implements Speaker {
  final said = <Utterance>[];
  int hushes = 0;

  @override
  void say(Utterance u) => said.add(u);

  @override
  void hush() => hushes++;

  @override
  Future<void> dispose() async {}
}

class FakeListener implements VoiceListener {
  bool available = true;
  void Function(String, bool)? onWords;
  bool listening = false;

  @override
  Future<bool> ready() async => available;

  @override
  Future<void> start({required String lang, required void Function(String, bool) onWords}) async {
    this.onWords = onWords;
    listening = true;
  }

  @override
  Future<void> stop() async => listening = false;
}

class FakeAlerts implements Alerts {
  final questions = <String>[];
  final cleared = <String>[];
  bool? keptAlive;

  @override
  Future<void> init() async {}

  @override
  Future<void> question({required String qid, required String who, required String text}) async =>
      questions.add(qid);

  @override
  Future<void> clearQuestion(String qid) async => cleared.add(qid);

  @override
  Future<void> keepAlive(bool on, {String status = ''}) async => keptAlive = on;
}

Future<SettingsStore> fakeStore([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsStore.open();
}

const sessionA = Session(id: 'a', label: 'rd_monorepo · main', state: 'working', last: 'Tests pass.');
const sessionB = Session(id: 'b', label: 'voice-bridge · main', state: 'idle');
const question1 = Question(qid: 'q1', sid: 'a', text: 'Delete the old folder?', ts: 100);

HubMessage message(int id, {String kind = 'report', String text = 'hello', bool speak = true, bool natural = true, bool replay = false, String sid = 'a'}) =>
    HubMessage(id: id, sid: sid, label: 'rd_monorepo · main', kind: kind, text: text, speak: speak, say: text, natural: natural, ts: 100, replay: replay);

void expectPost((String, Map<String, dynamic>) post, String path, Map<String, dynamic> body) {
  expect(post.$1, path);
  expect(post.$2, body);
}
