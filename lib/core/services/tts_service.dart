// TTS Service - Text-to-Speech for navigation voice guidance
// Author: Lộc Vũ Trung

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _enabled = true;

  bool get enabled => _enabled;
  set enabled(bool v) => _enabled = v;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('vi-VN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
      debugPrint('TtsService: Initialized vi-VN');
    } catch (e) {
      debugPrint('TtsService: Init failed: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!_enabled || !_initialized) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TtsService: Speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }
}
