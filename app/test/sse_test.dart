import 'package:flutter_test/flutter_test.dart';
import 'package:voice_bridge/data/sse.dart';

void main() {
  test('parses id and data, ignores pings and retry', () {
    final p = SseParser();
    final events = p.add('retry: 2000\n\n: ping\n\nid: 7\ndata: {"a":1}\n\n');
    expect(events, hasLength(1));
    expect(events.single.id, '7');
    expect(events.single.data, '{"a":1}');
  });

  test('joins an event split across chunks', () {
    final p = SseParser();
    expect(p.add('id: 1\nda'), isEmpty);
    expect(p.add('ta: hel'), isEmpty);
    final events = p.add('lo\n\n');
    expect(events.single.data, 'hello');
    expect(events.single.id, '1');
  });

  test('handles CRLF and multi-line data', () {
    final events = SseParser().add('data: one\r\ndata: two\r\n\r\n');
    expect(events.single.data, 'one\ntwo');
    expect(events.single.id, isNull);
  });

  test('several events in one chunk', () {
    final events = SseParser().add('data: a\n\ndata: b\n\n');
    expect(events.map((e) => e.data), ['a', 'b']);
  });
}
