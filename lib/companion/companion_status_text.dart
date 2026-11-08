import '../vision/companion_state_evaluator.dart';

String companionStatusText(CompanionStatus status, CompanionCause cause) {
  if (status == CompanionStatus.sleeping) {
    return cause == CompanionCause.postureDown ? '姿勢過低' : '疑似瞌睡';
  }
  return switch (status) {
    CompanionStatus.normal => '狀態穩定',
    CompanionStatus.attention => '注意力波動',
    CompanionStatus.fatigue => '疲勞／閉眼',
    CompanionStatus.distracted => '視線偏離',
    CompanionStatus.userMissing => '暫時離席',
    CompanionStatus.sleeping => '疑似瞌睡',
  };
}
