import 'package:desk_companion/preferences/companion_preferences.dart';
import 'package:desk_companion/preferences/companion_preferences_controller.dart';
import 'package:desk_companion/preferences/companion_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads the three saved preferences before the UI starts', () async {
    final store = _MemoryPreferencesStore(
      const CompanionPreferences(
        quietMode: true,
        voiceReplyEnabled: false,
        aiResponseTone: AiResponseTone.strict,
      ),
    );
    final controller = CompanionPreferencesController.detached(store);

    await controller.initialize();

    expect(controller.value.quietMode, isTrue);
    expect(controller.value.voiceReplyEnabled, isFalse);
    expect(controller.value.aiResponseTone, AiResponseTone.strict);
  });

  test('saves every selected preference change in order', () async {
    final store = _MemoryPreferencesStore(null);
    final controller = CompanionPreferencesController.detached(store);
    await controller.initialize();

    controller.setQuietMode(true);
    controller.setVoiceReplyEnabled(false);
    controller.cycleResponseTone();
    await controller.flushPendingSave();

    expect(store.saved, hasLength(3));
    expect(store.saved.last.quietMode, isTrue);
    expect(store.saved.last.voiceReplyEnabled, isFalse);
    expect(store.saved.last.aiResponseTone, AiResponseTone.encouraging);
  });

  test('initialize is idempotent', () async {
    final store = _MemoryPreferencesStore(const CompanionPreferences());
    final controller = CompanionPreferencesController.detached(store);

    await controller.initialize();
    await controller.initialize();

    expect(store.loadCount, 1);
  });
}

class _MemoryPreferencesStore implements CompanionPreferencesStore {
  _MemoryPreferencesStore(this.loaded);

  final CompanionPreferences? loaded;
  final List<CompanionPreferences> saved = <CompanionPreferences>[];
  int loadCount = 0;

  @override
  Future<CompanionPreferences?> load() async {
    loadCount += 1;
    return loaded;
  }

  @override
  Future<void> save(CompanionPreferences preferences) async {
    saved.add(preferences);
  }
}
