import 'package:desk_companion/focus/reminder_policy.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReminderPolicy', () {
    final start = DateTime(2026, 9, 5, 10);

    test('only prompts after the configured evidence threshold', () {
      final policy = ReminderPolicy();

      expect(
        _evaluate(
          policy,
          start,
          const Duration(seconds: 7),
          CompanionCause.postureDown,
        ),
        isNull,
      );
      expect(
        _evaluate(
          policy,
          start,
          const Duration(seconds: 8),
          CompanionCause.postureDown,
        ),
        isNotNull,
      );
    });

    test('never interrupts while the user is away', () {
      final policy = ReminderPolicy();

      final prompt = policy.evaluate(
        status: CompanionStatus.userMissing,
        cause: CompanionCause.userAway,
        evidenceDuration: const Duration(hours: 1),
        now: start,
      );

      expect(prompt, isNull);
    });

    test('only prompts once during an unchanged episode', () {
      final policy = ReminderPolicy();

      expect(
        _evaluate(
          policy,
          start,
          const Duration(seconds: 3),
          CompanionCause.drowsy,
        ),
        isNotNull,
      );
      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 30)),
          const Duration(minutes: 30),
          CompanionCause.drowsy,
        ),
        isNull,
      );
    });

    test('continue requires recovery and a ten minute cooldown', () {
      final policy = ReminderPolicy();
      _evaluate(
        policy,
        start,
        const Duration(seconds: 3),
        CompanionCause.eyeClosed,
        status: CompanionStatus.fatigue,
      );
      policy.recordResponse(
        status: CompanionStatus.fatigue,
        cause: CompanionCause.eyeClosed,
        response: ReminderPolicyResponse.continueFocus,
        now: start,
      );

      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 11)),
          const Duration(minutes: 11),
          CompanionCause.eyeClosed,
          status: CompanionStatus.fatigue,
        ),
        isNull,
        reason: 'elapsed time alone must not re-arm an unchanged episode',
      );

      policy.markEpisodeEnded(
        CompanionStatus.fatigue,
        CompanionCause.eyeClosed,
      );
      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 9)),
          const Duration(seconds: 3),
          CompanionCause.eyeClosed,
          status: CompanionStatus.fatigue,
        ),
        isNull,
      );
      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 10)),
          const Duration(seconds: 3),
          CompanionCause.eyeClosed,
          status: CompanionStatus.fatigue,
        ),
        isNotNull,
      );
    });

    test(
      'remind later can prompt again in the same episode after five minutes',
      () {
        final policy = ReminderPolicy();
        _evaluate(
          policy,
          start,
          const Duration(seconds: 15),
          CompanionCause.headTurned,
          status: CompanionStatus.distracted,
        );
        policy.recordResponse(
          status: CompanionStatus.distracted,
          cause: CompanionCause.headTurned,
          response: ReminderPolicyResponse.remindLater,
          now: start,
        );

        expect(
          _evaluate(
            policy,
            start.add(const Duration(minutes: 4, seconds: 59)),
            const Duration(minutes: 5),
            CompanionCause.headTurned,
            status: CompanionStatus.distracted,
          ),
          isNull,
        );
        expect(
          _evaluate(
            policy,
            start.add(const Duration(minutes: 5)),
            const Duration(minutes: 5),
            CompanionCause.headTurned,
            status: CompanionStatus.distracted,
          ),
          isNotNull,
        );
      },
    );

    test('dismissal uses the longer fifteen minute cooldown', () {
      final policy = ReminderPolicy();
      _evaluate(
        policy,
        start,
        const Duration(seconds: 8),
        CompanionCause.postureDown,
      );
      policy.recordResponse(
        status: CompanionStatus.sleeping,
        cause: CompanionCause.postureDown,
        response: ReminderPolicyResponse.dismissed,
        now: start,
      );
      policy.markEpisodeEnded(
        CompanionStatus.sleeping,
        CompanionCause.postureDown,
      );

      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 14, seconds: 59)),
          const Duration(seconds: 8),
          CompanionCause.postureDown,
        ),
        isNull,
      );
      expect(
        _evaluate(
          policy,
          start.add(const Duration(minutes: 15)),
          const Duration(seconds: 8),
          CompanionCause.postureDown,
        ),
        isNotNull,
      );
    });
  });
}

ReminderPolicyPrompt? _evaluate(
  ReminderPolicy policy,
  DateTime now,
  Duration evidence,
  CompanionCause cause, {
  CompanionStatus status = CompanionStatus.sleeping,
}) {
  return policy.evaluate(
    status: status,
    cause: cause,
    evidenceDuration: evidence,
    now: now,
  );
}
