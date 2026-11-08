import 'dart:async';

import 'package:flutter/foundation.dart';

import 'companion_preferences.dart';
import 'companion_preferences_store.dart';

/// Shared user preferences across navigation routes and app restarts.
class CompanionPreferencesController
    extends ValueNotifier<CompanionPreferences> {
  CompanionPreferencesController._(this._store)
    : super(const CompanionPreferences());

  @visibleForTesting
  CompanionPreferencesController.detached(CompanionPreferencesStore store)
    : _store = store,
      super(const CompanionPreferences());

  static final instance = CompanionPreferencesController._(
    FileCompanionPreferencesStore(),
  );

  final CompanionPreferencesStore _store;
  Future<void>? _initialization;
  Future<void> _pendingSave = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final saved = await _store.load();
      if (saved == null) return;
      value = value.copyWith(
        quietMode: saved.quietMode,
        aiResponseTone: saved.aiResponseTone,
        voiceReplyEnabled: saved.voiceReplyEnabled,
      );
    } catch (error) {
      debugPrint('Local preferences initialization failed: $error');
    } finally {
      _initialized = true;
    }
  }

  void setQuietMode(bool enabled) {
    if (value.quietMode == enabled) return;
    _update(value.copyWith(quietMode: enabled));
  }

  void setVoiceReplyEnabled(bool enabled) {
    if (value.voiceReplyEnabled == enabled) return;
    _update(value.copyWith(voiceReplyEnabled: enabled));
  }

  void cycleResponseTone() {
    final next = switch (value.aiResponseTone) {
      AiResponseTone.supportive => AiResponseTone.encouraging,
      AiResponseTone.encouraging => AiResponseTone.strict,
      AiResponseTone.strict => AiResponseTone.supportive,
    };
    _update(value.copyWith(aiResponseTone: next));
  }

  void _update(CompanionPreferences next) {
    value = next;
    if (!_initialized) return;
    _pendingSave = _pendingSave.then((_) => _store.save(next)).catchError((
      Object error,
    ) {
      debugPrint('Local preferences save failed: $error');
    });
  }

  @visibleForTesting
  Future<void> flushPendingSave() => _pendingSave;
}

extension AiResponseToneLabel on AiResponseTone {
  String get label => switch (this) {
    AiResponseTone.supportive => '溫和',
    AiResponseTone.encouraging => '鼓勵',
    AiResponseTone.strict => '嚴格',
  };
}
