import 'package:equatable/equatable.dart';

/// One Claude Code session on the Mac, as the hub describes it.
class Session extends Equatable {
  const Session({
    required this.id,
    required this.label,
    required this.state,
    this.cwd = '',
    this.branch,
    this.last = '',
    this.phoneMode = false,
    this.phoneWaitingUntil,
    this.queued = 0,
    this.claudeSessionId,
  });

  final String id;
  final String label;

  /// working | waiting | needs_terminal | idle | ended
  final String state;
  final String cwd;
  final String? branch;
  final String last;
  final bool phoneMode;

  /// Unix seconds; set while a finished session waits for a phone instruction.
  final double? phoneWaitingUntil;
  final int queued;
  final String? claudeSessionId;

  bool get ended => state == 'ended';

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? 'session',
        state: (j['state'] as String?) ?? 'working',
        cwd: (j['cwd'] as String?) ?? '',
        branch: j['branch'] as String?,
        last: (j['last'] as String?) ?? '',
        phoneMode: (j['phone_mode'] as bool?) ?? false,
        phoneWaitingUntil: (j['phone_waiting_until'] as num?)?.toDouble(),
        queued: (j['queued'] as num?)?.toInt() ?? 0,
        claudeSessionId: j['claude_session_id'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, label, state, cwd, branch, last, phoneMode, phoneWaitingUntil, queued, claudeSessionId];
}

/// A question from Claude that is waiting for your answer.
class Question extends Equatable {
  const Question({required this.qid, required this.sid, required this.text, required this.ts});

  final String qid;
  final String sid;
  final String text;
  final double ts;

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        qid: j['qid'] as String,
        sid: j['sid'] as String,
        text: (j['text'] as String?) ?? '',
        ts: (j['ts'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [qid, sid, text, ts];
}

/// One line of the conversation feed.
class HubMessage extends Equatable {
  const HubMessage({
    required this.id,
    required this.kind,
    required this.text,
    required this.ts,
    this.sid,
    this.label = '',
    this.speak = false,
    this.say,
    this.natural = false,
    this.replay = false,
  });

  final int id;
  final String? sid;
  final String label;

  /// report | question | status | system | answer | instruction
  final String kind;
  final String text;
  final bool speak;

  /// What to read aloud (the hub decides whether to name the session).
  final String? say;

  /// Whether the hub can make a natural-voice MP3 of [say].
  final bool natural;
  final double ts;

  /// Sent again after a reconnect: show it, don't read it aloud.
  final bool replay;

  bool get fromUser => kind == 'answer' || kind == 'instruction';

  factory HubMessage.fromJson(Map<String, dynamic> j) => HubMessage(
        id: (j['id'] as num).toInt(),
        sid: j['sid'] as String?,
        label: (j['label'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'system',
        text: (j['text'] as String?) ?? '',
        speak: (j['speak'] as bool?) ?? false,
        say: j['say'] as String?,
        natural: (j['natural'] as bool?) ?? false,
        ts: (j['ts'] as num?)?.toDouble() ?? 0,
        replay: (j['replay'] as bool?) ?? false,
      );

  @override
  List<Object?> get props => [id, sid, label, kind, text, speak, say, natural, ts, replay];
}

class VoiceOption extends Equatable {
  const VoiceOption(this.id, this.name);

  final String id;

  /// "Heart · US woman"
  final String name;

  static const phone = VoiceOption('phone', 'Phone voice · robotic');

  @override
  List<Object?> get props => [id, name];
}
