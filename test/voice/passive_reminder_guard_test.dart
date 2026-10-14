import 'dart:async';

import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/voice/passive_reminder_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 14, 10);
  late PassiveReminderGuard guard;

  void observe(
    int milliseconds, {
    CompanionStatus status = CompanionStatus.distracted,
    CompanionCause cause = CompanionCause.headTurned,
    bool face = true,
    bool pose = true,
    bool motion = false,
  }) {
    guard.observe(
      status: status,
      cause: cause,
      hasFace: face,
      hasPose: pose,
      motionSuspected: motion,
      now: start.add(Duration(milliseconds: milliseconds)),
    );
  }

  bool canPlay(int milliseconds, {int? revision}) => guard.canPlay(
    CompanionStatus.distracted,
    CompanionCause.headTurned,
    revision ?? guard.revision,
    now: start.add(Duration(milliseconds: milliseconds)),
  );

  setUp(() => guard = PassiveReminderGuard());

  test('800ms hold requires a confirming observation, not just a timer', () {
    observe(0);
    expect(canPlay(799), isFalse);
    expect(canPlay(800), isFalse);
    observe(800);
    expect(canPlay(800), isTrue);
  });

  test('hold overlaps existing three-second distraction evidence', () {
    observe(0, motion: true);
    observe(800, motion: true);
    observe(3000, motion: true);
    expect(canPlay(3000), isTrue);
  });

  test('new body movement restarts observation but not on every frame', () {
    observe(0);
    observe(800);
    expect(canPlay(800), isTrue);
    observe(900, motion: true);
    expect(canPlay(900), isFalse);
    observe(1600, motion: true);
    expect(canPlay(1600), isFalse);
    observe(1700, motion: true);
    expect(canPlay(1700), isTrue);
  });

  test('body-only face loss holds a prepared reminder for reconfirmation', () {
    observe(0);
    observe(800);
    final revision = guard.revision;
    observe(900, face: false);
    expect(canPlay(900, revision: revision), isFalse);
    expect(canPlay(1700, revision: revision), isFalse);
    observe(1700, face: false);
    expect(canPlay(1700, revision: revision), isTrue);
  });

  test('full tracking loss blocks audio even while sleep is latched', () {
    observe(
      0,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
    );
    observe(
      800,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
    );
    final revision = guard.revision;
    observe(
      900,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
      face: false,
      pose: false,
    );
    observe(
      1700,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
      face: false,
      pose: false,
    );
    expect(
      guard.canPlay(
        CompanionStatus.sleeping,
        CompanionCause.postureDown,
        revision,
        now: start.add(const Duration(milliseconds: 1700)),
      ),
      isFalse,
    );
    expect(
      guard.canPlay(
        CompanionStatus.sleeping,
        CompanionCause.postureDown,
        guard.revision,
        now: start.add(const Duration(milliseconds: 1700)),
      ),
      isFalse,
    );
  });

  test('body-only confirmed sleep is allowed after observation', () {
    observe(
      0,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
    );
    observe(
      100,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
      face: false,
    );
    observe(
      900,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
      face: false,
    );
    expect(
      guard.canPlay(
        CompanionStatus.sleeping,
        CompanionCause.postureDown,
        guard.revision,
        now: start.add(const Duration(milliseconds: 900)),
      ),
      isTrue,
    );
  });

  test('confirmed away invalidates old reminders even after quick return', () {
    observe(0);
    observe(800);
    final revision = guard.revision;
    observe(
      900,
      status: CompanionStatus.userMissing,
      cause: CompanionCause.userAway,
      face: false,
      pose: false,
    );
    observe(1000);
    observe(1800);
    expect(canPlay(1800, revision: revision), isFalse);
    expect(canPlay(1800), isTrue);
  });

  test('reason change cancels a reminder even with the same status', () {
    observe(0, status: CompanionStatus.sleeping, cause: CompanionCause.drowsy);
    final revision = guard.revision;
    observe(
      1000,
      status: CompanionStatus.sleeping,
      cause: CompanionCause.postureDown,
    );
    expect(
      guard.isCurrent(
        CompanionStatus.sleeping,
        CompanionCause.drowsy,
        revision,
      ),
      isFalse,
    );
  });

  test('normal cancels old reminders', () {
    observe(0);
    final revision = guard.revision;
    observe(800, status: CompanionStatus.normal, cause: CompanionCause.none);
    expect(canPlay(800, revision: revision), isFalse);
  });

  test('stale observations and resets cannot authorize playback', () {
    observe(0);
    observe(800);
    final revision = guard.revision;
    expect(canPlay(3801), isFalse);
    guard.reset();
    observe(4000);
    observe(4800);
    expect(canPlay(4800, revision: revision), isFalse);
  });

  test('a long observation gap starts fresh evidence', () {
    observe(0);
    observe(800);
    final revision = guard.revision;
    observe(4000);
    expect(canPlay(4000), isFalse);
    observe(4800);
    expect(canPlay(4800), isTrue);
    expect(canPlay(4800, revision: revision), isFalse);
  });

  test('steady eye fatigue is not given an unconditional extra hold', () {
    observe(
      0,
      status: CompanionStatus.fatigue,
      cause: CompanionCause.eyeClosed,
    );
    expect(
      guard.canPlay(
        CompanionStatus.fatigue,
        CompanionCause.eyeClosed,
        guard.revision,
        now: start,
      ),
      isTrue,
    );
  });

  test(
    'state change while audio initializes skips preparation and playback',
    () async {
      observe(0);
      observe(800);
      final revision = guard.revision;
      final ready = Completer<void>();
      var prepared = false;
      var played = false;
      final result = startVoicePlaybackIfEligible(
        ready: ready.future,
        canStart: () => canPlay(900, revision: revision),
        prepare: () async {
          prepared = true;
        },
        start: () async {
          played = true;
        },
      );
      observe(
        900,
        status: CompanionStatus.userMissing,
        cause: CompanionCause.userAway,
        face: false,
        pose: false,
      );
      ready.complete();
      expect(await result, isFalse);
      expect(prepared, isFalse);
      expect(played, isFalse);
    },
  );

  test(
    'departure while player stops cancels immediately before play',
    () async {
      observe(0);
      observe(800);
      final revision = guard.revision;
      final preparing = Completer<void>();
      final prepared = Completer<void>();
      var played = false;
      final result = startVoicePlaybackIfEligible(
        ready: Future<void>.value(),
        canStart: () => canPlay(900, revision: revision),
        prepare: () {
          preparing.complete();
          return prepared.future;
        },
        start: () async {
          played = true;
        },
      );
      await preparing.future;
      observe(
        900,
        status: CompanionStatus.userMissing,
        cause: CompanionCause.userAway,
        face: false,
        pose: false,
      );
      prepared.complete();
      expect(await result, isFalse);
      expect(played, isFalse);
    },
  );

  test('eligible passive audio plays once', () async {
    observe(0);
    observe(800);
    var plays = 0;
    expect(
      await startVoicePlaybackIfEligible(
        ready: Future<void>.value(),
        canStart: () => canPlay(800),
        prepare: () async {},
        start: () async {
          plays++;
        },
      ),
      isTrue,
    );
    expect(plays, 1);
  });

  test(
    'active conversation audio does not require vision eligibility',
    () async {
      var played = false;
      expect(
        await startVoicePlaybackIfEligible(
          ready: Future<void>.value(),
          prepare: () async {},
          start: () async {
            played = true;
          },
        ),
        isTrue,
      );
      expect(played, isTrue);
    },
  );
}
