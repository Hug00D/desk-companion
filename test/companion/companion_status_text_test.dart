import 'package:desk_companion/companion/companion_status_text.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the simplified sleeping state retains the cause in user-facing text',
    () {
      expect(
        companionStatusText(
          CompanionStatus.sleeping,
          CompanionCause.postureDown,
        ),
        '姿勢過低',
      );
      expect(
        companionStatusText(CompanionStatus.sleeping, CompanionCause.drowsy),
        '疑似瞌睡',
      );
    },
  );
}
