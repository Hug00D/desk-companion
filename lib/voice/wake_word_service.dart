import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'pcm_audio.dart';

typedef WakeWordDetectedCallback = Future<void> Function(String keyword);
typedef WakeWordErrorCallback = void Function(String message);

enum WakeWordServiceState { idle, initializing, listening, error }

class WakeWordService {
  static const int _sampleRate = 16000;
  static const String _assetRoot = 'assets/models/wake_word';
  static const String _encoderName =
      'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String _decoderName =
      'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String _joinerName =
      'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String _tokensName = 'tokens.txt';

  final AudioRecorder _recorder = AudioRecorder();

  static bool _bindingsInitialized = false;

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _keywordStream;
  StreamSubscription<Uint8List>? _audioSubscription;
  WakeWordDetectedCallback? _onDetected;
  WakeWordErrorCallback? _onError;
  WakeWordServiceState _state = WakeWordServiceState.idle;
  bool _disposed = false;
  bool _handlingDetection = false;
  int? _pendingPcmByte;

  WakeWordServiceState get state => _state;
  bool get isListening => _state == WakeWordServiceState.listening;

  Future<void> start({
    required String keywordTokens,
    required WakeWordDetectedCallback onDetected,
    WakeWordErrorCallback? onError,
  }) async {
    if (_disposed) {
      throw StateError('WakeWordService has already been disposed.');
    }
    if (isListening || _state == WakeWordServiceState.initializing) return;

    _onDetected = onDetected;
    _onError = onError;
    _state = WakeWordServiceState.initializing;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw StateError('麥克風權限未開啟。');
      }

      await _ensureSpotter(keywordTokens);
      final spotter = _spotter;
      if (spotter == null) {
        throw StateError('喚醒模型初始化失敗。');
      }

      _keywordStream?.free();
      _keywordStream = spotter.createStream();
      _pendingPcmByte = null;

      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          streamBufferSize: 3200,
        ),
      );
      _audioSubscription = audioStream.listen(
        _consumeAudio,
        onError: (Object error, StackTrace stackTrace) {
          _reportError('麥克風串流失敗：$error');
          unawaited(stop());
        },
        cancelOnError: true,
      );
      _state = WakeWordServiceState.listening;
    } catch (error) {
      _state = WakeWordServiceState.error;
      _reportError(error.toString());
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final subscription = _audioSubscription;
    _audioSubscription = null;
    final keywordStream = _keywordStream;
    _keywordStream = null;
    _pendingPcmByte = null;
    if (!_disposed) {
      _state = WakeWordServiceState.idle;
    }

    await subscription?.cancel();

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    keywordStream?.free();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    _spotter?.free();
    _spotter = null;
    await _recorder.dispose();
  }

  Future<void> _ensureSpotter(String keywordTokens) async {
    if (_spotter != null) return;

    if (!_bindingsInitialized) {
      sherpa.initBindings();
      _bindingsInitialized = true;
    }

    final modelDirectory = await _copyModelsToFileSystem();
    final keywordBytes = utf8.encode(keywordTokens);
    _spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: _sampleRate,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '${modelDirectory.path}/$_encoderName',
            decoder: '${modelDirectory.path}/$_decoderName',
            joiner: '${modelDirectory.path}/$_joinerName',
          ),
          tokens: '${modelDirectory.path}/$_tokensName',
          numThreads: 1,
          provider: 'cpu',
          debug: false,
        ),
        maxActivePaths: 4,
        numTrailingBlanks: 1,
        keywordsScore: 2.0,
        keywordsThreshold: 0.2,
        keywordsBuf: keywordTokens,
        keywordsBufSize: keywordBytes.length,
      ),
    );
  }

  Future<Directory> _copyModelsToFileSystem() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final modelDirectory = Directory(
      '${supportDirectory.path}/wake_word/sherpa_zh_v1',
    );
    await modelDirectory.create(recursive: true);

    for (final filename in <String>[
      _encoderName,
      _decoderName,
      _joinerName,
      _tokensName,
    ]) {
      final assetData = await rootBundle.load('$_assetRoot/$filename');
      final target = File('${modelDirectory.path}/$filename');
      if (await target.exists() &&
          await target.length() == assetData.lengthInBytes) {
        continue;
      }
      await target.writeAsBytes(
        assetData.buffer.asUint8List(
          assetData.offsetInBytes,
          assetData.lengthInBytes,
        ),
        flush: true,
      );
    }
    return modelDirectory;
  }

  void _consumeAudio(Uint8List bytes) {
    final spotter = _spotter;
    final stream = _keywordStream;
    if (!isListening || spotter == null || stream == null || bytes.isEmpty) {
      return;
    }

    final leadingByte = _pendingPcmByte;
    final samples = pcm16LittleEndianToFloat32(bytes, leadingByte: leadingByte);
    final totalByteCount = bytes.length + (leadingByte == null ? 0 : 1);
    _pendingPcmByte = totalByteCount.isOdd ? bytes.last : null;
    if (samples.isEmpty) return;

    stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    while (spotter.isReady(stream)) {
      spotter.decode(stream);
    }

    final keyword = spotter.getResult(stream).keyword.trim();
    if (keyword.isEmpty || _handlingDetection) return;
    spotter.reset(stream);
    unawaited(_handleDetection(keyword));
  }

  Future<void> _handleDetection(String keyword) async {
    _handlingDetection = true;
    try {
      await stop();
      await _onDetected?.call(keyword);
    } finally {
      _handlingDetection = false;
    }
  }

  void _reportError(String message) {
    _onError?.call(message);
  }
}
