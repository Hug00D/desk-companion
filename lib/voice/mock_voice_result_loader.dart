import 'dart:convert';

import 'package:flutter/services.dart';

import 'voice_result.dart';

class MockVoiceResultLoader {
  const MockVoiceResultLoader({
    this.assetPath = 'assets/mock/voice_intents.json',
  });

  final String assetPath;

  Future<List<VoiceRecognitionResult>> loadResults() async {
    final jsonText = await rootBundle.loadString(assetPath);
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    final results = data['results'];

    if (results is! List) return const [];

    return results
        .whereType<Map>()
        .map(
          (item) =>
              VoiceRecognitionResult.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
