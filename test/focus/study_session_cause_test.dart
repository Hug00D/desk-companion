import 'package:desk_companion/focus/study_session_controller.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sleeping focus events are counted by their retained cause', () {
    final controller = StudySessionController();

    controller.recordFocusEvent(
      CompanionStatus.sleeping,
      CompanionCause.drowsy,
    );
    controller.recordFocusEvent(
      CompanionStatus.sleeping,
      CompanionCause.postureDown,
    );

    expect(controller.drowsyEventCount, 1);
    expect(controller.postureDownEventCount, 1);
  });
}
