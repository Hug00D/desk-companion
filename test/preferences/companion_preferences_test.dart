import 'package:desk_companion/preferences/companion_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice replies default to enabled for existing preference data', () {
    const defaults = CompanionPreferences();
    final legacy = CompanionPreferences.fromJson(const <String, dynamic>{});

    expect(defaults.voiceReplyEnabled, isTrue);
    expect(legacy.voiceReplyEnabled, isTrue);
  });

  test('voice reply preference supports copy and JSON round trip', () {
    final disabled = const CompanionPreferences().copyWith(
      voiceReplyEnabled: false,
    );
    final restored = CompanionPreferences.fromJson(disabled.toJson());

    expect(disabled.voiceReplyEnabled, isFalse);
    expect(restored.voiceReplyEnabled, isFalse);
    expect(restored.quietMode, isFalse);
  });
}
