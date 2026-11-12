import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Turns your voice into text while the talk button is held.
abstract class VoiceListener {
  /// Asks for the microphone the first time. False if speech isn't available.
  Future<bool> ready();

  /// [onWords] gets the running transcript; [isFinal] once recognition is done.
  Future<void> start({required String lang, required void Function(String words, bool isFinal) onWords});

  Future<void> stop();
}

class DeviceListener implements VoiceListener {
  final _stt = SpeechToText();
  bool? _ok;

  @override
  Future<bool> ready() async => _ok ??= await _stt.initialize();

  @override
  Future<void> start({
    required String lang,
    required void Function(String words, bool isFinal) onWords,
  }) async {
    if (!await ready()) return;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onWords(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: lang.replaceAll('-', '_'),
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 30),
        listenFor: const Duration(minutes: 2),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}
