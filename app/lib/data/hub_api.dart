import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'sse.dart';

/// Something the hub pushed, or a change in the connection itself.
sealed class HubEvent {
  const HubEvent();
}

class ConnectionChanged extends HubEvent {
  const ConnectionChanged(this.connected);
  final bool connected;
}

class StateSnapshot extends HubEvent {
  const StateSnapshot(this.sessions, this.questions);
  final List<Session> sessions;
  final List<Question> questions;
}

class MessageArrived extends HubEvent {
  const MessageArrived(this.message);
  final HubMessage message;
}

class HubError implements Exception {
  const HubError(this.message);
  final String message;
  @override
  String toString() => message;
}

class VoiceList {
  const VoiceList({required this.available, required this.defaultVoice, required this.voices});
  final bool available;
  final String defaultVoice;
  final List<VoiceOption> voices;
}

/// The voice-bridge hub on the Mac (see github.com/khamidjon-khamidov/voice-bridge).
abstract class HubApi {
  /// Live events; reconnects by itself and replays what was missed.
  Stream<HubEvent> events();

  /// POST to /api/...; returns the JSON body or throws [HubError].
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body);

  Future<VoiceList> voices();

  Uri audioUri(int messageId, String voice);

  Future<bool> ping();

  void close();
}

class HttpHubApi implements HubApi {
  HttpHubApi(String baseUrl, {http.Client? client})
      : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;
  bool _closed = false;
  http.Client? _streamClient;

  Uri _u(String path) => base.resolve(path.startsWith('/') ? path.substring(1) : path);

  @override
  Stream<HubEvent> events() {
    late StreamController<HubEvent> ctrl;
    var cancelled = false;
    String? lastId;

    Future<void> loop() async {
      var delay = const Duration(seconds: 1);
      while (!cancelled && !_closed) {
        final client = _streamClient = http.Client();
        try {
          final req = http.Request('GET', _u('events'))
            ..headers['Accept'] = 'text/event-stream'
            ..headers['Cache-Control'] = 'no-cache';
          if (lastId != null) req.headers['Last-Event-ID'] = lastId!;
          final res = await client.send(req).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) throw HubError('Hub answered ${res.statusCode}');
          ctrl.add(const ConnectionChanged(true));
          delay = const Duration(seconds: 1);
          final parser = SseParser();
          // The hub pings every 15 s; 40 s of silence means the link is dead.
          await for (final chunk in res.stream
              .transform(utf8.decoder)
              .timeout(const Duration(seconds: 40))) {
            if (cancelled) break;
            for (final e in parser.add(chunk)) {
              if (e.id != null) lastId = e.id;
              final event = _decode(e.data);
              if (event != null) ctrl.add(event);
            }
          }
        } catch (_) {
          // fall through to reconnect
        } finally {
          client.close();
        }
        if (cancelled || _closed) break;
        ctrl.add(const ConnectionChanged(false));
        await Future<void>.delayed(delay);
        if (delay < const Duration(seconds: 10)) delay *= 2;
      }
    }

    ctrl = StreamController<HubEvent>(
      onListen: loop,
      onCancel: () {
        cancelled = true;
        _streamClient?.close();
      },
    );
    return ctrl.stream;
  }

  static HubEvent? _decode(String data) {
    final Object? j;
    try {
      j = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (j is! Map<String, dynamic>) return null;
    switch (j['type']) {
      case 'state':
        return StateSnapshot(
          [for (final s in (j['sessions'] as List? ?? const [])) Session.fromJson(s as Map<String, dynamic>)],
          [for (final q in (j['questions'] as List? ?? const [])) Question.fromJson(q as Map<String, dynamic>)],
        );
      case 'message':
        return MessageArrived(HubMessage.fromJson(j));
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _client
          .post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const HubError("Couldn't reach the hub");
    }
    Map<String, dynamic> data = const {};
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode >= 400) throw HubError((data['error'] as String?) ?? 'Request failed');
    return data;
  }

  @override
  Future<VoiceList> voices() async {
    try {
      final res = await _client.get(_u('api/voices')).timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return VoiceList(
        available: (j['available'] as bool?) ?? false,
        defaultVoice: (j['default'] as String?) ?? 'af_heart',
        voices: [
          for (final v in (j['voices'] as List? ?? const []))
            VoiceOption((v as Map)['id'] as String, v['name'] as String),
        ],
      );
    } catch (_) {
      return const VoiceList(available: false, defaultVoice: 'phone', voices: []);
    }
  }

  @override
  Uri audioUri(int messageId, String voice) =>
      _u('audio/$messageId').replace(queryParameters: {'voice': voice});

  @override
  Future<bool> ping() async {
    try {
      final res = await _client.get(_u('health')).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 && (jsonDecode(res.body) as Map)['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    _closed = true;
    _streamClient?.close();
    _client.close();
  }
}
