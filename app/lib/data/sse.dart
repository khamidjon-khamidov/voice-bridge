/// Minimal Server-Sent Events parser: feed it text chunks as they arrive,
/// get back complete events. Handles events split across chunks.
class SseEvent {
  const SseEvent({this.id, required this.data});

  final String? id;
  final String data;
}

class SseParser {
  final _buffer = StringBuffer();
  String? _id;
  final _data = <String>[];

  List<SseEvent> add(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final lastNewline = text.lastIndexOf('\n');
    if (lastNewline < 0) return const [];
    _buffer
      ..clear()
      ..write(text.substring(lastNewline + 1));

    final events = <SseEvent>[];
    for (var line in text.substring(0, lastNewline).split('\n')) {
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) {
        if (_data.isNotEmpty) events.add(SseEvent(id: _id, data: _data.join('\n')));
        _data.clear();
        _id = null;
        continue;
      }
      if (line.startsWith(':')) continue; // comment / keep-alive ping
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'data') _data.add(value);
      if (field == 'id') _id = value;
    }
    return events;
  }
}
