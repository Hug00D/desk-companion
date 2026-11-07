import 'package:flutter/foundation.dart';

/// Carries a one-shot recalibration request back to the persistent home screen.
///
/// Settings can be reached through replacement routes, so a Navigator result is
/// not reliable enough to deliver this action.
class VisionCalibrationRequestController extends ChangeNotifier {
  VisionCalibrationRequestController._();

  static final instance = VisionCalibrationRequestController._();

  int _requestSerial = 0;

  int get requestSerial => _requestSerial;

  void requestRecalibration() {
    _requestSerial += 1;
    notifyListeners();
  }
}
