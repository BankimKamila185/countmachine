import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  bool isEnabled = true;
  int _lastSpokenCount = -1;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);

  TtsService._internal() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      // Ignored if platform TTS initialization is delayed
    }
  }

  Future<void> announceCount(int count, {bool force = false}) async {
    if (!isEnabled) return;

    final now = DateTime.now();
    // Prevent repetitive repeating spam: announce only when count changes or after cooldown
    if (!force && count == _lastSpokenCount && now.difference(_lastSpokenTime).inSeconds < 4) {
      return;
    }

    _lastSpokenCount = count;
    _lastSpokenTime = now;

    final text = count == 0
        ? 'No pieces detected'
        : count == 1
            ? '1 piece detected'
            : '$count pieces detected';

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      // TTS error fallback
    }
  }

  void toggleEnabled() {
    isEnabled = !isEnabled;
    if (!isEnabled) {
      _flutterTts.stop();
    }
  }
}
