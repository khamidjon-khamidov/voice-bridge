import 'package:equatable/equatable.dart';

import '../data/models.dart';

/// Who the next thing you say goes to.
sealed class Target extends Equatable {
  const Target();
}

/// Answer an open question.
class AnswerTarget extends Target {
  const AnswerTarget(this.qid);
  final String qid;
  @override
  List<Object?> get props => [qid];
}

/// Send a new instruction to a session.
class InstructTarget extends Target {
  const InstructTarget(this.sid);
  final String sid;
  @override
  List<Object?> get props => [sid];
}

/// What you tapped wins while it still exists. An open question from the
/// session you picked beats a plain message to it. Otherwise the oldest open
/// question, otherwise the first live session.
Target? resolveTarget(Target? picked, List<Session> sessions, List<Question> questions) {
  if (picked is AnswerTarget && questions.any((q) => q.qid == picked.qid)) return picked;
  if (picked is InstructTarget && sessions.any((s) => s.id == picked.sid && !s.ended)) {
    for (final q in questions) {
      if (q.sid == picked.sid) return AnswerTarget(q.qid);
    }
    return picked;
  }
  if (questions.isNotEmpty) {
    final oldest = questions.reduce((a, b) => a.ts <= b.ts ? a : b);
    return AnswerTarget(oldest.qid);
  }
  for (final s in sessions) {
    if (!s.ended) return InstructTarget(s.id);
  }
  return null;
}
