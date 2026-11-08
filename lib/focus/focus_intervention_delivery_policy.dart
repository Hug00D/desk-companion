import 'focus_session_monitor.dart';

/// Decides which focus effects remain active while quiet mode is enabled.
///
/// Quiet mode suppresses proactive interruptions. It does not disable vision
/// recording or an auto-pause explicitly enabled by the focus policy.
class FocusInterventionDeliveryPolicy {
  const FocusInterventionDeliveryPolicy();

  bool shouldDeliver(FocusInterventionType type, {required bool quietMode}) {
    if (!quietMode) return true;

    return switch (type) {
      FocusInterventionType.eventRecorded ||
      FocusInterventionType.autoPause => true,
      FocusInterventionType.reminder ||
      FocusInterventionType.checkIn ||
      FocusInterventionType.offerPause ||
      FocusInterventionType.recovered => false,
    };
  }
}
