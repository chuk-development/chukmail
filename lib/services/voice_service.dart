import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _initialized = false;

  Future<bool> ensurePermissions() async {
    final mic = await Permission.microphone.request();
    return mic.isGranted;
  }

  Future<bool> init() async {
    if (_initialized) return true;
    final ok = await ensurePermissions();
    if (!ok) return false;
    _initialized = await _stt.initialize();
    return _initialized;
  }

  bool get isAvailable => _initialized;
  bool get isListening => _stt.isListening;

  Future<bool> start({
    required void Function(String text, bool finalResult) onResult,
    String? localeId,
  }) async {
    final ok = await init();
    if (!ok) return false;
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
    return true;
  }

  Future<void> stop() async {
    if (_stt.isListening) await _stt.stop();
  }

  Future<void> cancel() async {
    if (_stt.isListening) await _stt.cancel();
  }
}
