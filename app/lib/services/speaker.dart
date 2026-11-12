import 'dart:async';
import 'dart:collection';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

/// Something to read aloud: a natural-voice MP3 from the hub, with the
/// phone's own voice as the fallback.
class Utterance {
  const Utterance({required this.text, this.audio});

  final String text;

  /// MP3 made on the Mac; null means use the phone's voice.
  final Uri? audio;
}

abstract class Speaker {
  void say(Utterance u);

  /// Stop now and drop everything queued.
  void hush();

  Future<void> dispose();
}

/// Plays one utterance at a time. Every step has a time limit and hush()
/// always ends the current one, so the queue can't get stuck (the web page
/// had that bug).
class DeviceSpeaker implements Speaker {
  DeviceSpeaker({AudioPlayer? player, FlutterTts? tts})
      : _player = player ?? AudioPlayer(),
        _tts = tts ?? FlutterTts() {
    _tts.awaitSpeakCompletion(true);
    _tts.setSpeechRate(0.5);
  }

  final AudioPlayer _player;
  final FlutterTts _tts;
  final _queue = Queue<Utterance>();
  bool _busy = false;
  int _generation = 0;

  @override
  void say(Utterance u) {
    _queue.add(u);
    _pump();
  }

  @override
  void hush() {
    _generation++;
    _queue.clear();
    _player.stop();
    _tts.stop();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty) {
        final gen = _generation;
        final u = _queue.removeFirst();
        var played = false;
        if (u.audio != null) played = await _playMp3(u.audio!);
        if (!played && gen == _generation) await _speakWithPhone(u.text);
      }
    } finally {
      _busy = false;
    }
  }

  Future<bool> _playMp3(Uri url) async {
    try {
      final duration = await _player.setUrl(url.toString()).timeout(const Duration(seconds: 20));
      final limit = (duration ?? const Duration(seconds: 30)) + const Duration(seconds: 5);
      await _player.play().timeout(limit);
      return true;
    } catch (_) {
      await _player.stop();
      return false;
    }
  }

  Future<void> _speakWithPhone(String text) async {
    try {
      await _tts.speak(text).timeout(const Duration(seconds: 30));
    } catch (_) {
      await _tts.stop();
    }
  }

  @override
  Future<void> dispose() async {
    hush();
    await _player.dispose();
  }
}
