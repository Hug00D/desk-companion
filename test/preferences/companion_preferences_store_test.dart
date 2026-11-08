import 'dart:io';

import 'package:desk_companion/preferences/companion_preferences.dart';
import 'package:desk_companion/preferences/companion_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FileCompanionPreferencesStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'desk_companion_preferences_',
    );
    store = FileCompanionPreferencesStore(
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('missing local file uses app defaults', () async {
    expect(await store.load(), isNull);
  });

  test('stores only the three selected restart preferences', () async {
    const preferences = CompanionPreferences(
      quietMode: true,
      voiceReplyEnabled: false,
      aiResponseTone: AiResponseTone.strict,
      syncEnabled: false,
      storeTranscript: true,
      storeDebugSnapshot: true,
    );

    await store.save(preferences);
    final restored = await store.load();
    final raw = await File(
      '${directory.path}${Platform.pathSeparator}'
      '${FileCompanionPreferencesStore.fileName}',
    ).readAsString();

    expect(restored?.quietMode, isTrue);
    expect(restored?.voiceReplyEnabled, isFalse);
    expect(restored?.aiResponseTone, AiResponseTone.strict);
    expect(raw, contains('quietMode'));
    expect(raw, contains('voiceReplyEnabled'));
    expect(raw, contains('aiResponseTone'));
    expect(raw, isNot(contains('storeTranscript')));
    expect(raw, isNot(contains('storeDebugSnapshot')));
    expect(raw, isNot(contains('syncEnabled')));
  });

  test('invalid local JSON falls back without crashing startup', () async {
    await File(
      '${directory.path}${Platform.pathSeparator}'
      '${FileCompanionPreferencesStore.fileName}',
    ).writeAsString('{not-json');

    expect(await store.load(), isNull);
  });
}
