import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/hub_api.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../services/alerts.dart';
import '../services/listener.dart';
import '../services/speaker.dart';
import 'bridge_state.dart';
import 'target.dart';

/// Everything the home screen does, in one place: the live connection to the
/// hub, reading messages aloud, question notifications and your replies.
class BridgeCubit extends Cubit<BridgeState> {
  BridgeCubit({
    required this.api,
    required this.store,
    required this.speaker,
    required this.listener,
    required this.alerts,
  }) : super(BridgeState(
          soundOn: store.soundOn,
          autoSend: store.autoSend,
          keepListening: store.keepListening,
          lang: store.lang,
          voice: store.voice ?? 'af_heart',
        ));

  final HubApi api;
  final SettingsStore store;
  final Speaker speaker;
  final VoiceListener listener;
  final Alerts alerts;

  StreamSubscription<HubEvent>? _sub;
  final _spoken = <int>{};
  bool _inForeground = true;

  static const maxFeed = 300;
  static const previewText = 'Hi, this is how I sound.';

  Future<void> start() async {
    _sub = api.events().listen(_onEvent);
    final v = await api.voices();
    if (isClosed) return;
    final voices = [...v.voices, VoiceOption.phone];
    final saved = store.voice;
    final voice = voices.any((o) => o.id == saved) ? saved! : (v.available ? v.defaultVoice : VoiceOption.phone.id);
    emit(state.copyWith(voices: voices, naturalAvailable: v.available, voice: voice));
    if (state.keepListening) unawaited(alerts.keepAlive(true, status: _status()));
  }

  void setForeground(bool value) => _inForeground = value;

  // ---------- incoming ----------
  void _onEvent(HubEvent e) {
    if (isClosed) return;
    switch (e) {
      case ConnectionChanged(:final connected):
        emit(state.copyWith(connected: connected));
      case StateSnapshot(:final sessions, :final questions):
        final open = {for (final q in questions) q.qid};
        for (final q in state.questions) {
          if (!open.contains(q.qid)) unawaited(alerts.clearQuestion(q.qid));
        }
        emit(state.copyWith(sessions: sessions, questions: questions));
        if (state.keepListening) unawaited(alerts.keepAlive(true, status: _status()));
      case MessageArrived(:final message):
        _onMessage(message);
    }
  }

  void _onMessage(HubMessage m) {
    if (state.feed.any((x) => x.id == m.id)) return;
    final feed = [...state.feed, m];
    emit(state.copyWith(feed: feed.length > maxFeed ? feed.sublist(feed.length - maxFeed) : feed));
    if (m.replay || !m.speak || !_spoken.add(m.id)) return;
    if (state.soundOn) speaker.say(_utterance(m.id, m.say ?? m.text, m.natural));
    if (m.kind == 'question' && !_inForeground) {
      final q = state.questions.where((q) => q.sid == m.sid && q.text == m.text);
      unawaited(alerts.question(
        qid: q.isEmpty ? 'msg-${m.id}' : q.first.qid,
        who: state.sessions.length > 1 ? m.label : '',
        text: m.text,
      ));
    }
  }

  Utterance _utterance(int id, String text, bool natural) => Utterance(
        text: text,
        audio: natural && state.naturalAvailable && state.voice != VoiceOption.phone.id
            ? api.audioUri(id, state.voice)
            : null,
      );

  String _status() {
    final live = state.sessions.where((s) => !s.ended).length;
    final waiting = state.questions.length;
    if (waiting > 0) return '$waiting question${waiting == 1 ? '' : 's'} waiting for you';
    return live == 0 ? 'No Claude sessions' : 'Listening to $live session${live == 1 ? '' : 's'}';
  }

  // ---------- replies ----------
  void pick(Target t) => emit(state.copyWith(picked: t));

  /// Sends [text] to the current target. Returns a line to show you.
  /// Throws [HubError] when the hub can't be reached.
  Future<String> send(String text) async {
    text = text.trim();
    if (text.isEmpty) return '';
    final t = state.target;
    if (t == null) throw const HubError('No session to send to');
    switch (t) {
      case AnswerTarget(:final qid):
        await api.post('/api/answer', {'qid': qid, 'text': text});
        unawaited(alerts.clearQuestion(qid));
        emit(state.copyWith(clearPicked: true));
        return 'Answer sent';
      case InstructTarget(:final sid):
        final res = await api.post('/api/instruct', {'id': sid, 'text': text});
        emit(state.copyWith(clearPicked: true));
        return switch (res['delivery']) {
          'now' => 'Sent: Claude is picking it up',
          'queued_idle' => 'Queued: Claude had already stopped, so it reads this at your next terminal prompt',
          _ => 'Sent: Claude gets it on its next step',
        };
    }
  }

  Future<String> status([String? sid]) async {
    await api.post('/api/status', {'id': sid ?? 'all'});
    return sid == null ? 'Status requested from all' : 'Status requested';
  }

  Future<String> setPhoneMode(String sid, bool on) async {
    await api.post('/api/phone_mode', {'id': sid, 'on': on});
    return on ? 'Phone mode on: Claude waits for you when it finishes' : 'Phone mode off';
  }

  Future<String> rename(String sid, String label) async {
    await api.post('/api/label', {'id': sid, 'label': label});
    return 'Renamed';
  }

  Future<String> forget(String sid) async {
    await api.post('/api/forget', {'id': sid});
    return 'Removed';
  }

  // ---------- voice in ----------
  Future<bool> startListening(void Function(String words, bool isFinal) onWords) async {
    speaker.hush();
    if (!await listener.ready()) return false;
    emit(state.copyWith(listening: true));
    await listener.start(lang: state.lang, onWords: onWords);
    return true;
  }

  Future<void> stopListening() async {
    await listener.stop();
    if (!isClosed) emit(state.copyWith(listening: false));
  }

  // ---------- settings ----------
  Future<void> setVoice(String voice) async {
    await store.setVoice(voice);
    emit(state.copyWith(voice: voice));
    speaker
      ..hush()
      ..say(_utterance(0, previewText, true));
  }

  Future<void> setLang(String lang) async {
    await store.setLang(lang);
    emit(state.copyWith(lang: lang));
  }

  Future<void> setAutoSend(bool on) async {
    await store.setAutoSend(on);
    emit(state.copyWith(autoSend: on));
  }

  Future<void> setSound(bool on) async {
    await store.setSoundOn(on);
    if (!on) speaker.hush();
    emit(state.copyWith(soundOn: on));
  }

  Future<void> setKeepListening(bool on) async {
    await store.setKeepListening(on);
    emit(state.copyWith(keepListening: on));
    await alerts.keepAlive(on, status: _status());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    speaker.hush();
    return super.close();
  }
}
