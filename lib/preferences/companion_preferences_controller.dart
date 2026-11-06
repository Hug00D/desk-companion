import 'package:flutter/foundation.dart';

import 'companion_preferences.dart';

/// Shared preferences for the current app session, across navigation routes.
class CompanionPreferencesController
    extends ValueNotifier<CompanionPreferences> {
  CompanionPreferencesController._() : super(const CompanionPreferences());

  static final instance = CompanionPreferencesController._();

  void setQuietMode(bool enabled) {
    if (value.quietMode == enabled) return;
    value = value.copyWith(quietMode: enabled);
  }

  void cycleResponseTone() {
    final next = switch (value.aiResponseTone) {
      AiResponseTone.supportive => AiResponseTone.encouraging,
      AiResponseTone.encouraging => AiResponseTone.strict,
      AiResponseTone.strict => AiResponseTone.supportive,
    };
    value = value.copyWith(aiResponseTone: next);
  }
}

extension AiResponseToneLabel on AiResponseTone {
  String get label => switch (this) {
    AiResponseTone.supportive => '溫和',
    AiResponseTone.encouraging => '鼓勵',
    AiResponseTone.strict => '嚴格',
  };
}
