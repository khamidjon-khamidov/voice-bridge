import 'package:flutter_test/flutter_test.dart';
import 'package:voice_bridge/data/models.dart';
import 'package:voice_bridge/logic/target.dart';

import 'fakes.dart';

void main() {
  const ended = Session(id: 'x', label: 'old', state: 'ended');
  const q2 = Question(qid: 'q2', sid: 'b', text: 'Use pnpm?', ts: 50);

  test('nothing to talk to', () {
    expect(resolveTarget(null, const [], const []), isNull);
    expect(resolveTarget(null, const [ended], const []), isNull);
  });

  test('defaults to the first live session', () {
    expect(resolveTarget(null, const [ended, sessionA], const []), const InstructTarget('a'));
  });

  test('defaults to the oldest open question', () {
    expect(resolveTarget(null, const [sessionA, sessionB], const [question1, q2]), const AnswerTarget('q2'));
  });

  test('a tapped question wins while it is open', () {
    expect(resolveTarget(const AnswerTarget('q1'), const [sessionA, sessionB], const [question1, q2]),
        const AnswerTarget('q1'));
    expect(resolveTarget(const AnswerTarget('gone'), const [sessionA], const [question1]), const AnswerTarget('q1'));
  });

  test("a picked session's own open question beats a plain message", () {
    expect(resolveTarget(const InstructTarget('a'), const [sessionA, sessionB], const [question1, q2]),
        const AnswerTarget('q1'));
    expect(resolveTarget(const InstructTarget('b'), const [sessionA, sessionB], const [question1]),
        const InstructTarget('b'));
  });

  test('a picked session that ended falls back', () {
    expect(resolveTarget(const InstructTarget('x'), const [ended, sessionB], const []), const InstructTarget('b'));
  });
}
