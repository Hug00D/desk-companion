import 'pose_calculator.dart';

class VisionResult {
  const VisionResult({
    required this.raw,
    required this.hasPose,
    required this.hasFace,
    this.leftShoulderX,
    this.leftShoulderY,
    this.rightShoulderX,
    this.rightShoulderY,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.shoulderWidth,
  });

  final Map<dynamic, dynamic> raw;
  final bool hasPose;
  final bool hasFace;
  final double? leftShoulderX;
  final double? leftShoulderY;
  final double? rightShoulderX;
  final double? rightShoulderY;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? shoulderWidth;

  bool get hasEyeData => leftEyeOpen != null && rightEyeOpen != null;

  factory VisionResult.fromNativeMap(Map<dynamic, dynamic> data) {
    final hasPose = data['hasPose'] == true;
    final hasFace = data['hasFace'] == true;

    final leftShoulderX = _toDouble(data['lsX']);
    final leftShoulderY = _toDouble(data['lsY']);
    final rightShoulderX = _toDouble(data['rsX']);
    final rightShoulderY = _toDouble(data['rsY']);

    double? shoulderWidth;
    if (hasPose &&
        leftShoulderX != null &&
        leftShoulderY != null &&
        rightShoulderX != null &&
        rightShoulderY != null) {
      shoulderWidth = PoseCalculator.getWidth(
        leftShoulderX,
        leftShoulderY,
        rightShoulderX,
        rightShoulderY,
      );
    }

    return VisionResult(
      raw: data,
      hasPose: hasPose,
      hasFace: hasFace,
      leftShoulderX: leftShoulderX,
      leftShoulderY: leftShoulderY,
      rightShoulderX: rightShoulderX,
      rightShoulderY: rightShoulderY,
      leftEyeOpen: hasFace ? _toDouble(data['leftEye']) : null,
      rightEyeOpen: hasFace ? _toDouble(data['rightEye']) : null,
      shoulderWidth: shoulderWidth,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }
}
