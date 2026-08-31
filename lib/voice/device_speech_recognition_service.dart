import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'voice_result.dart';

typedef SpeechStatusCallback = void Function(String status);
typedef SpeechErrorCallback = void Function(String message);
typedef SpeechResultCallback = void Function(VoiceRecognitionResult result);

class DeviceSpeechRecognitionService {
  static const String _traditionalChineseLocaleId = 'zh_TW';

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  int _sessionCounter = 0;
  String _preferredLocaleId = _traditionalChineseLocaleId;
  bool _preferredLocaleReportedByDevice = false;
  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String get preferredLocaleId => _preferredLocaleId;
  bool get preferredLocaleReportedByDevice => _preferredLocaleReportedByDevice;

  Future<bool> initialize({
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    if (_initialized) return _available;

    _available = await _speech.initialize(
      onStatus: (status) => _onStatus?.call(status),
      onError: (error) => _onError?.call(error.errorMsg),
      finalTimeout: const Duration(seconds: 1),
      options: <stt.SpeechConfigOption>[stt.SpeechToText.androidNoBluetooth],
    );
    _initialized = true;

    if (_available) {
      await _resolvePreferredLocale();
    }
    return _available;
  }

  Future<void> start({required SpeechResultCallback onResult}) async {
    if (!_available) {
      throw StateError('Speech recognition is not available on this device.');
    }

    final sessionId =
        'device-speech-${DateTime.now().millisecondsSinceEpoch}-${++_sessionCounter}';
    await _speech.listen(
      onResult: (result) => onResult(_toVoiceResult(sessionId, result)),
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        localeId: _preferredLocaleId,
      ),
    );
  }

  Future<void> stop() async {
    if (!_speech.isListening) return;
    await _speech.stop();
  }

  Future<void> cancel() async {
    if (!_speech.isListening) return;
    await _speech.cancel();
  }

  Future<void> _resolvePreferredLocale() async {
    final locales = await _speech.locales();
    for (final locale in locales) {
      final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
      if (normalized == 'zh_tw' || normalized.startsWith('zh_hant')) {
        _preferredLocaleId = locale.localeId;
        _preferredLocaleReportedByDevice = true;
        return;
      }
    }

    // The emulator often reports only en-US even though Google's recognizer can
    // accept an explicit Chinese locale. Never feed Chinese speech to that
    // English fallback; let the recognizer report a language error instead.
    _preferredLocaleId = _traditionalChineseLocaleId;
    _preferredLocaleReportedByDevice = false;
  }

  VoiceRecognitionResult _toVoiceResult(
    String sessionId,
    stt_result.SpeechRecognitionResult result,
  ) {
    final confidence = result.confidence;
    return VoiceRecognitionResult(
      sessionId: sessionId,
      eventType: result.finalResult
          ? VoiceEventType.finalResult
          : VoiceEventType.partial,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      transcript: result.recognizedWords,
      formattedTranscript: result.recognizedWords,
      isFinal: result.finalResult,
      candidates: <VoiceCandidate>[
        VoiceCandidate(
          text: result.recognizedWords,
          confidence: confidence < 0 ? null : confidence,
        ),
      ],
      language: VoiceLanguageInfo(tag: _preferredLocaleId),
    );
  }
}
