import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/statistics_api.dart';
import '../auth/auth_session.dart';
import '../statistics/statistics_summary.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/live2d_character_background.dart';
import 'profile_hub_screen.dart';
import 'tasks_screen.dart';

enum _StatisticsRange {
  today(label: '今日', days: 1),
  sevenDays(label: '7 天', days: 7),
  thirtyDays(label: '30 天', days: 30);

  const _StatisticsRange({required this.label, required this.days});

  final String label;
  final int days;
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatisticsApi _statisticsApi = StatisticsApi(ApiClient());
  final AuthSession _authSession = AuthSession.instance;

  _StatisticsRange _selectedRange = _StatisticsRange.today;
  Future<StatisticsSummary>? _summaryFuture;
  DateTime? _lastLoadedAt;

  @override
  void initState() {
    super.initState();
    _reloadSummary();
  }

  void _reloadSummary() {
    setState(() {
      _summaryFuture = _fetchSummary();
    });
  }

  Future<StatisticsSummary> _fetchSummary() async {
    if (!_authSession.isSignedIn) {
      throw StateError('請先登入後再查看統計資料。');
    }

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final from = _selectedRange == _StatisticsRange.today
        ? startOfToday
        : startOfToday.subtract(Duration(days: _selectedRange.days - 1));

    final summary = await _statisticsApi.getMySummary(
      authSession: _authSession,
      from: from,
      to: now,
      timezone: 'Asia/Taipei',
    );

    if (mounted) {
      setState(() => _lastLoadedAt = DateTime.now());
    }
    return summary;
  }

  Future<void> _refreshSummary() async {
    _reloadSummary();
    await _summaryFuture;
  }

  void _selectRange(_StatisticsRange range) {
    if (_selectedRange == range) return;
    setState(() => _selectedRange = range);
    _reloadSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10283D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Live2DCharacterBackground(),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x7710283D),
                  Color(0x3310283D),
                  Color(0xBB10283D),
                ],
              ),
            ),
          ),
          SafeArea(
            child: FutureBuilder<StatisticsSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                final summary = snapshot.data;
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting &&
                    summary == null;

                return RefreshIndicator(
                  onRefresh: _refreshSummary,
                  color: const Color(0xFF2F7ED8),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            18,
                            14,
                            18,
                            GlassBottomNavBar.contentBottomPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPageHeader(),
                              const SizedBox(height: 14),
                              _buildRangeSelector(),
                              const SizedBox(height: 14),
                              if (isLoading)
                                const _GlassPanel(child: _LoadingState())
                              else if (snapshot.hasError)
                                _GlassPanel(
                                  child: _ErrorState(
                                    message: snapshot.error.toString(),
                                    onRetry: _reloadSummary,
                                  ),
                                )
                              else if (summary != null) ...[
                                _buildOverview(summary),
                                const SizedBox(height: 14),
                                _GlassPanel(child: _buildFocusTrend(summary)),
                                const SizedBox(height: 14),
                                _GlassPanel(
                                  child: _buildStateDistribution(summary),
                                ),
                                const SizedBox(height: 14),
                                _GlassPanel(child: _buildEventCounts(summary)),
                                const SizedBox(height: 14),
                                _GlassPanel(child: _buildRecentEvents(summary)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _buildBottomNavBar(context),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    final loadedText = _lastLoadedAt == null
        ? '尚未同步'
        : '更新於 ${_formatClock(_lastLoadedAt!)}';

    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '專注統計',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '依照後端紀錄即時整理你的學習狀態。',
                style: TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _GlassIconButton(
          icon: Icons.refresh_rounded,
          tooltip: loadedText,
          onTap: _reloadSummary,
        ),
      ],
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [
        for (final range in _StatisticsRange.values) ...[
          Expanded(
            child: _RangeButton(
              label: range.label,
              selected: _selectedRange == range,
              onTap: () => _selectRange(range),
            ),
          ),
          if (range != _StatisticsRange.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildOverview(StatisticsSummary summary) {
    final today = summary.today;

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('範圍總覽', style: _sectionTitleStyle),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: '穩定專注',
                  value: _formatDuration(today.focusSeconds),
                  icon: Icons.timer_rounded,
                  color: const Color(0xFF9FF3D0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: '完成輪數',
                  value: today.completedRoundCount.toString(),
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF79D2F5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: '提醒次數',
                  value: today.reminderShownCount.toString(),
                  icon: Icons.notifications_rounded,
                  color: const Color(0xFFFFD36B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: '離席時間',
                  value: _formatDuration(today.awaySeconds),
                  icon: Icons.airline_seat_recline_normal,
                  color: const Color(0xFF9AC7FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFocusTrend(StatisticsSummary summary) {
    final points = summary.weeklyTrend;
    final maxSeconds = points.fold<int>(
      0,
      (max, point) => point.focusSeconds > max ? point.focusSeconds : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('每日專注趨勢', style: _sectionTitleStyle),
        const SizedBox(height: 6),
        const Text(
          '柱狀高度代表當天穩定專注時間。',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        if (points.isEmpty)
          const _EmptyState(text: '這段時間還沒有專注紀錄。')
        else
          SizedBox(
            height: 170,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    SizedBox(
                      width: _selectedRange == _StatisticsRange.thirtyDays
                          ? 34
                          : 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxSeconds == 0
                                      ? 0.04
                                      : (point.focusSeconds / maxSeconds).clamp(
                                          0.04,
                                          1.0,
                                        ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0xFF9FF3D0),
                                          Color(0xFF79D2F5),
                                        ],
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x5579D2F5),
                                          blurRadius: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDayLabel(point.date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _formatShortDuration(point.focusSeconds),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStateDistribution(StatisticsSummary summary) {
    final distribution = summary.stateDistribution;
    final total = distribution.totalSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('時間分布', style: _sectionTitleStyle),
        const SizedBox(height: 6),
        const Text(
          '由 focus_sessions 彙整穩定專注、分心、疲勞與離席秒數。',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        if (total == 0)
          const _EmptyState(text: '目前還沒有可顯示的時間分布。')
        else ...[
          _ProgressRow(
            label: '穩定專注',
            value: distribution.ratioFor(distribution.focusSeconds),
            detail: _formatDuration(distribution.focusSeconds),
            color: const Color(0xFF9FF3D0),
          ),
          _ProgressRow(
            label: '分心 / 注意力下降',
            value: distribution.ratioFor(distribution.attentionSeconds),
            detail: _formatDuration(distribution.attentionSeconds),
            color: const Color(0xFFFFD36B),
          ),
          _ProgressRow(
            label: '分心',
            value: distribution.ratioFor(distribution.distractedSeconds),
            detail: _formatDuration(distribution.distractedSeconds),
            color: const Color(0xFFFFB648),
          ),
          _ProgressRow(
            label: '疲勞 / 打瞌睡',
            value: distribution.ratioFor(distribution.fatigueSeconds),
            detail: _formatDuration(distribution.fatigueSeconds),
            color: const Color(0xFFFF7A3D),
          ),
          _ProgressRow(
            label: '打瞌睡',
            value: distribution.ratioFor(distribution.drowsySeconds),
            detail: _formatDuration(distribution.drowsySeconds),
            color: const Color(0xFFE85D75),
          ),
          _ProgressRow(
            label: '趴下',
            value: distribution.ratioFor(distribution.postureDownSeconds),
            detail: _formatDuration(distribution.postureDownSeconds),
            color: const Color(0xFFC06CFF),
          ),
          _ProgressRow(
            label: '離席',
            value: distribution.ratioFor(distribution.awaySeconds),
            detail: _formatDuration(distribution.awaySeconds),
            color: const Color(0xFF9AC7FF),
          ),
        ],
      ],
    );
  }

  Widget _buildEventCounts(StatisticsSummary summary) {
    final entries = summary.eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('動作次數', style: _sectionTitleStyle),
        const SizedBox(height: 6),
        const Text(
          '依照 behavior_events.event_type 統計目前範圍內發生次數。',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          const _EmptyState(text: '這段時間還沒有事件紀錄。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries.take(12))
                _EventCountChip(
                  label: _eventTypeLabel(entry.key),
                  count: entry.value,
                  color: _eventColor(entry.key),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildRecentEvents(StatisticsSummary summary) {
    final events = summary.recentEvents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('近期事件', style: _sectionTitleStyle),
        const SizedBox(height: 12),
        if (events.isEmpty)
          const _EmptyState(text: '目前沒有近期事件。')
        else
          for (final event in events.take(8))
            _EventRow(
              time: _formatClock(event.occurredAt.toLocal()),
              title: _eventTypeLabel(event.eventType),
              detail: _eventDetail(event),
              color: _eventColor(event.eventType),
            ),
      ],
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return GlassBottomNavBar(
      activeTab: AppNavTab.statistics,
      onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      onStatisticsTap: _reloadSummary,
      onTasksTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const TasksScreen()),
        );
      },
      onSettingsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '統計',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '先用 Demo 數據排版，之後接真實紀錄。',
                style: TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 目前還在規劃中。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _eventDetail(RecentStatisticsEvent event) {
    final parts = <String>[
      if (event.detail != null && event.detail!.isNotEmpty) event.detail!,
      if (event.severity != null && event.severity!.isNotEmpty)
        '程度：${event.severity}',
      if (event.outcome != null && event.outcome!.isNotEmpty)
        '結果：${event.outcome}',
    ];
    return parts.isEmpty ? '已記錄到後端。' : parts.join(' · ');
  }

  String _eventTypeLabel(String type) {
    switch (type) {
      case 'vision.normal':
        return '狀態正常';
      case 'vision.partial_user_detected':
        return '姿態不完整';
      case 'vision.user_away':
        return '離席';
      case 'vision.user_returned':
        return '返回座位';
      case 'vision.attention_warning':
        return '注意力下降';
      case 'vision.distracted':
        return '分心';
      case 'vision.fatigue_detected':
        return '疲勞 / 閉眼';
      case 'vision.drowsy_detected':
        return '打瞌睡';
      case 'vision.posture_down':
        return '趴下';
      case 'voice.startPomodoro':
        return '語音開始番茄鐘';
      case 'voice.pausePomodoro':
        return '語音暫停';
      case 'voice.resumePomodoro':
        return '語音繼續';
      case 'voice.stopPomodoro':
        return '語音停止';
      case 'voice.requestFocusSummary':
        return '詢問狀態摘要';
      case 'voice.reportTired':
        return '自回報疲勞';
      case 'voice.reportDistracted':
        return '自回報分心';
      case 'voice.requestBreak':
        return '要求休息';
      case 'voice.command_unknown':
        return '未知語音';
      case 'timer.start_pomodoro':
        return '番茄鐘開始';
      case 'timer.pause_pomodoro':
        return '番茄鐘暫停';
      case 'timer.resume_pomodoro':
        return '番茄鐘繼續';
      case 'timer.stop_pomodoro':
        return '番茄鐘停止';
      case 'timer.pomodoro_completed':
        return '番茄鐘完成';
      case 'system.demo_event_upload':
        return '事件上傳 Demo';
      default:
        return type;
    }
  }

  Color _eventColor(String type) {
    if (type.contains('fatigue') ||
        type.contains('drowsy') ||
        type.contains('posture_down') ||
        type.contains('Tired')) {
      return const Color(0xFFFF7A3D);
    }
    if (type.contains('attention') ||
        type.contains('Distracted') ||
        type.contains('unknown')) {
      return const Color(0xFFFFD36B);
    }
    if (type.contains('away')) {
      return const Color(0xFF9AC7FF);
    }
    if (type.contains('voice')) {
      return const Color(0xFF79D2F5);
    }
    return const Color(0xFF9FF3D0);
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0 分';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return '$hours 小時 $minutes 分';
    if (hours > 0) return '$hours 小時';
    if (minutes > 0) return '$minutes 分';
    return '$totalSeconds 秒';
  }

  String _formatShortDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h';
    if (minutes > 0) return '${minutes}m';
    return '${totalSeconds}s';
  }

  String _formatClock(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDayLabel(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Colors.white.withValues(alpha: 0.16),
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeButton extends StatelessWidget {
  const _RangeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF20324D) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final double value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$detail · ${(value * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCountChip extends StatelessWidget {
  const _EventCountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.time,
    required this.title,
    required this.detail,
    required this.color,
  });

  final String time;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              time,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 120,
      child: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('統計載入失敗', style: _sectionTitleStyle),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新整理'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

const TextStyle _sectionTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w900,
);
