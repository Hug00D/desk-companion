import 'package:flutter/material.dart';

enum VisionSourceStatus { initializing, camera, video, unavailable }

/// A visible source label even when the preview and developer tools are closed.
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
    final (icon, label, detail, color) = switch (status) {
      VisionSourceStatus.initializing => (
        Icons.hourglass_top_rounded,
        '正在啟動…',
        '正在準備偵測來源，請稍候。',
        const Color(0xFF52657D),
      ),
      VisionSourceStatus.camera => (
        Icons.videocam_rounded,
        isCalibrating ? '即時相機・校正中' : '即時相機',
        isCalibrating ? '請自然坐好並看向前方，等待校正完成。' : '目前以裝置相機進行即時偵測。',
        const Color(0xFF247D65),
      ),
      VisionSourceStatus.video => (
        Icons.movie_rounded,
        '測試影片',
        '目前偵測的是預錄影片，並非即時相機。可按右側按鈕重試相機。',
        const Color(0xFF93600B),
      ),
      VisionSourceStatus.unavailable => (
        Icons.videocam_off_rounded,
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

    return Tooltip(
      message: detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            if (canRetry) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onRetryCamera,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重試相機'),
                style: TextButton.styleFrom(foregroundColor: color),
              ),
            ] else if (canRecalibrate) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onRecalibrate,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                label: const Text('重新校正'),
                style: TextButton.styleFrom(foregroundColor: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
