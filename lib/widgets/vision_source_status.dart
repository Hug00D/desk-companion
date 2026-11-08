import 'package:flutter/material.dart';

import 'expandable_hud_control.dart';

enum VisionSourceStatus { initializing, camera, video, unavailable }

/// A compact camera control with source details and actions on expansion.
class VisionSourceIndicator extends StatelessWidget {
  const VisionSourceIndicator({
    super.key,
    required this.status,
    required this.onRetryCamera,
    this.isCalibrating = false,
    this.onRecalibrate,
  });

  final VisionSourceStatus status;
  final bool isCalibrating;
  final VoidCallback onRetryCamera;
  final VoidCallback? onRecalibrate;

  @override
  Widget build(BuildContext context) {
    final (label, detail, color) = switch (status) {
      VisionSourceStatus.initializing => (
        '正在啟動…',
        '正在準備偵測來源，請稍候。',
        const Color(0xFF52657D),
      ),
      VisionSourceStatus.camera => (
        isCalibrating ? '即時相機・校正中' : '即時相機',
        isCalibrating ? '請自然坐好並看向前方，等待校正完成。' : '目前以裝置相機進行即時偵測。',
        const Color(0xFF247D65),
      ),
      VisionSourceStatus.video => (
        '測試影片',
        '目前偵測的是預錄影片，並非即時相機。可按右側按鈕重試相機。',
        const Color(0xFF93600B),
      ),
      VisionSourceStatus.unavailable => (
        '未就緒',
        '偵測來源無法啟動，請確認相機權限後重試。',
        const Color(0xFFB33A48),
      ),
    };
    final canRetry =
        status == VisionSourceStatus.video ||
        status == VisionSourceStatus.unavailable;
    final canRecalibrate =
        status == VisionSourceStatus.camera &&
        !isCalibrating &&
        onRecalibrate != null;

    return ExpandableHudControl(
      controlId: 'vision-source',
      semanticName: '相機來源',
      icon: Icons.videocam_rounded,
      label: label,
      detail: detail,
      color: color,
      expandedAction: canRetry
          ? TextButton.icon(
              onPressed: onRetryCamera,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重試相機'),
              style: TextButton.styleFrom(foregroundColor: color),
            )
          : canRecalibrate
          ? TextButton.icon(
              onPressed: onRecalibrate,
              icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
              label: const Text('重新校正'),
              style: TextButton.styleFrom(foregroundColor: color),
            )
          : null,
    );
  }
}
