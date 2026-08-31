import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../focus/focus_session_report.dart';

Future<void> showFocusSessionReportDialog({
  required BuildContext context,
  required FocusSessionReport report,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x8A071725),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => FocusSessionReportDialog(report: report),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class FocusSessionReportDialog extends StatelessWidget {
  const FocusSessionReportDialog({super.key, required this.report});

  final FocusSessionReport report;

  @override
  Widget build(BuildContext context) {
    final score = report.score;
    final accentColor = _accentColorFor(score);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE6304558),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, accentColor),
                          const SizedBox(height: 22),
                          _buildScore(accentColor),
                          const SizedBox(height: 22),
                          _buildFocusDistribution(accentColor),
                          const SizedBox(height: 18),
                          _buildMetrics(),
                          const SizedBox(height: 18),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          const SizedBox(height: 16),
                          _buildEventSummary(),
                          const SizedBox(height: 18),
                          _buildFeedback(accentColor),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.check_rounded, size: 20),
                              label: const Text('收下這份報告'),
                              style: FilledButton.styleFrom(
                                foregroundColor: const Color(0xFF17334B),
                                backgroundColor: accentColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.auto_graph_rounded, color: accentColor, size: 23),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本輪專注報告',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '番茄鐘已完成',
                style: TextStyle(
                  color: Color(0xBFFFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '關閉',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Color(0xCCFFFFFF)),
        ),
      ],
    );
  }

  Widget _buildScore(Color accentColor) {
    final score = report.score;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: score == null ? 0 : score / 100,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score?.toString() ?? '--',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      score == null ? '資料不足' : '/ 100',
                      style: const TextStyle(
                        color: Color(0xBFFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                score == null ? '本輪不評分' : '${report.grade} 級表現',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                report.feedback,
                style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFocusDistribution(Color accentColor) {
    final focusPercent = (report.focusRatio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '有效專注比例',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              report.hasEnoughData ? '$focusPercent%' : '尚無足夠資料',
              style: TextStyle(
                color: accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: report.hasEnoughData ? report.focusRatio : 0,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        ),
      ],
    );
  }

  Widget _buildMetrics() {
    return Row(
      children: [
        _ReportMetric(
          label: '預定時間',
          value: _formatDuration(report.plannedDuration),
          color: const Color(0xFFFFD36B),
        ),
        _MetricDivider(),
        _ReportMetric(
          label: '有效專注',
          value: _formatDuration(report.effectiveFocusDuration),
          color: const Color(0xFF9FF3D0),
        ),
        _MetricDivider(),
        _ReportMetric(
          label: '分心時間',
          value: _formatDuration(report.distractedDuration),
          color: const Color(0xFFFFB474),
        ),
      ],
    );
  }

  Widget _buildEventSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '本輪事件',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _EventBadge(
              icon: Icons.visibility_off_outlined,
              label: '注意偏移 ${report.attentionEventCount}',
              color: const Color(0xFFFFD36B),
            ),
            _EventBadge(
              icon: Icons.bedtime_outlined,
              label: '疲勞睡眠 ${report.fatigueEventCount}',
              color: const Color(0xFFFFA071),
            ),
            _EventBadge(
              icon: Icons.person_off_outlined,
              label: '離席 ${report.awayEventCount}',
              color: const Color(0xFF79D2F5),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeedback(Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9FF3D0), size: 19),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '評分依有效專注比例與已記錄事件估算，作為調整節奏的參考，不代表能力高低。',
              style: TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _accentColorFor(int? score) {
    if (score == null) return const Color(0xFF79D2F5);
    if (score >= 80) return const Color(0xFF9FF3D0);
    if (score >= 60) return const Color(0xFFFFD36B);
    return const Color(0xFFFFA071);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xAFFFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
