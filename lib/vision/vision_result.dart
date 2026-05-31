import 'pose_calculator.dart';

class VisionResult {
  const VisionResult({
    required this.raw,
    required this.hasPose,
    required this.hasFace,
    this.imageWidth,
    this.imageHeight,
    this.poseSequence,
    this.leftShoulderX,
    this.leftShoulderY,
    this.rightShoulderX,
    this.rightShoulderY,
    this.leftShoulderVisibility,
    this.rightShoulderVisibility,
    this.poseNoseX,
    this.poseNoseY,
    this.poseNoseVisibility,
    this.poseLeftEyeY,
    this.poseLeftEyeVisibility,
    this.poseRightEyeY,
    this.poseRightEyeVisibility,
    this.poseLeftEarY,
    this.poseLeftEarVisibility,
    this.poseRightEarY,
    this.poseRightEarVisibility,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.headYaw,
    this.headPitch,
    this.headOffsetScore,
    this.isHeadOffsetCalibrating = false,
    this.shoulderWidth,
  });

  final Map<dynamic, dynamic> raw;
  final bool hasPose;
  final bool hasFace;
  final double? imageWidth;
  final double? imageHeight;
  final int? poseSequence;
  final double? leftShoulderX;
  final double? leftShoulderY;
  final double? rightShoulderX;
  final double? rightShoulderY;
  final double? leftShoulderVisibility;
  final double? rightShoulderVisibility;
  final double? poseNoseX;
  final double? poseNoseY;
  final double? poseNoseVisibility;
  final double? poseLeftEyeY;
  final double? poseLeftEyeVisibility;
  final double? poseRightEyeY;
  final double? poseRightEyeVisibility;
  final double? poseLeftEarY;
  final double? poseLeftEarVisibility;
  final double? poseRightEarY;
  final double? poseRightEarVisibility;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? headYaw;
  final double? headPitch;
  final double? headOffsetScore;
  final bool isHeadOffsetCalibrating;
  final double? shoulderWidth;

  bool get hasEyeData => leftEyeOpen != null && rightEyeOpen != null;

  double? get shoulderCenterY {
    if (leftShoulderY == null || rightShoulderY == null) return null;
    return (leftShoulderY! + rightShoulderY!) / 2;
  }

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
      imageWidth: _toDouble(data['imageWidth']),
      imageHeight: _toDouble(data['imageHeight']),
      poseSequence: _toInt(data['poseSequence']),
      leftShoulderX: leftShoulderX,
      leftShoulderY: leftShoulderY,
      rightShoulderX: rightShoulderX,
      rightShoulderY: rightShoulderY,
      leftShoulderVisibility: _toDouble(data['lsVisibility']),
      rightShoulderVisibility: _toDouble(data['rsVisibility']),
      poseNoseX: _toDouble(data['poseNoseX']),
      poseNoseY: _toDouble(data['poseNoseY']),
      poseNoseVisibility: _toDouble(data['poseNoseVisibility']),
      poseLeftEyeY: _toDouble(data['poseLeftEyeY']),
      poseLeftEyeVisibility: _toDouble(data['poseLeftEyeVisibility']),
      poseRightEyeY: _toDouble(data['poseRightEyeY']),
      poseRightEyeVisibility: _toDouble(data['poseRightEyeVisibility']),
      poseLeftEarY: _toDouble(data['poseLeftEarY']),
      poseLeftEarVisibility: _toDouble(data['poseLeftEarVisibility']),
      poseRightEarY: _toDouble(data['poseRightEarY']),
      poseRightEarVisibility: _toDouble(data['poseRightEarVisibility']),
      leftEyeOpen: hasFace ? _toDouble(data['leftEye']) : null,
      rightEyeOpen: hasFace ? _toDouble(data['rightEye']) : null,
      headYaw: hasFace ? _toDouble(data['headYaw']) : null,
      headPitch: hasFace ? _toDouble(data['headPitch']) : null,
      headOffsetScore: hasFace ? _toDouble(data['headOffsetScore']) : null,
      isHeadOffsetCalibrating: data['headOffsetCalibrating'] == true,
      shoulderWidth: shoulderWidth,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return null;
  }
}
