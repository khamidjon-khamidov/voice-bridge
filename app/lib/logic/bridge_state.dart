import 'package:equatable/equatable.dart';

import '../data/models.dart';
import 'target.dart';

class BridgeState extends Equatable {
  const BridgeState({
    this.connected = false,
    this.sessions = const [],
    this.questions = const [],
    this.feed = const [],
    this.picked,
    this.soundOn = true,
    this.autoSend = true,
    this.keepListening = true,
    this.lang = 'en-US',
    this.voice = 'af_heart',
    this.voices = const [VoiceOption.phone],
    this.naturalAvailable = false,
    this.listening = false,
  });

  final bool connected;
  final List<Session> sessions;
  final List<Question> questions;

  /// Oldest first.
  final List<HubMessage> feed;

  /// What you last tapped (a question or a session's Message button).
  final Target? picked;
  final bool soundOn;
  final bool autoSend;
  final bool keepListening;
  final String lang;
  final String voice;
  final List<VoiceOption> voices;
  final bool naturalAvailable;
  final bool listening;

  Target? get target => resolveTarget(picked, sessions, questions);

  Session? session(String? id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Question? question(String? qid) {
    for (final q in questions) {
      if (q.qid == qid) return q;
    }
    return null;
  }

  String labelOf(String? sid) => session(sid)?.label ?? 'session';

  BridgeState copyWith({
    bool? connected,
    List<Session>? sessions,
    List<Question>? questions,
    List<HubMessage>? feed,
    Target? picked,
    bool clearPicked = false,
    bool? soundOn,
    bool? autoSend,
    bool? keepListening,
    String? lang,
    String? voice,
    List<VoiceOption>? voices,
    bool? naturalAvailable,
    bool? listening,
  }) =>
      BridgeState(
        connected: connected ?? this.connected,
        sessions: sessions ?? this.sessions,
        questions: questions ?? this.questions,
        feed: feed ?? this.feed,
        picked: clearPicked ? null : (picked ?? this.picked),
        soundOn: soundOn ?? this.soundOn,
        autoSend: autoSend ?? this.autoSend,
        keepListening: keepListening ?? this.keepListening,
        lang: lang ?? this.lang,
        voice: voice ?? this.voice,
        voices: voices ?? this.voices,
        naturalAvailable: naturalAvailable ?? this.naturalAvailable,
        listening: listening ?? this.listening,
      );

  @override
  List<Object?> get props => [
        connected, sessions, questions, feed, picked, soundOn, autoSend, keepListening,
        lang, voice, voices, naturalAvailable, listening,
      ];
}
