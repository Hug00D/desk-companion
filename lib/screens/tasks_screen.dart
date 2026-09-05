import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/focus_session_monitor.dart';
import '../focus/pomodoro_controller.dart';
import '../vision/companion_state_evaluator.dart';
import '../widgets/focus_session_report_dialog.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import 'profile_hub_screen.dart';
import 'statistics_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final PomodoroController _pomodoroController = PomodoroController();
  final FocusSessionMonitor _focusSessionMonitor = FocusSessionMonitor();
  late final Listenable _pageListenable;
  int _selectedMinutes = 25;

  @override
  void initState() {
    super.initState();
    _pageListenable = Listenable.merge([
      _pomodoroController,
      _focusSessionMonitor,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10283D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x7710283D),
                  Color(0x3310283D),
                  Color(0xC210283D),
                ],
              ),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _pageListenable,
              builder: (context, _) {
                return CustomScrollView(
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
                            _buildHeader(),
                            const SizedBox(height: 18),
                            _buildPomodoroPanel(),
                            const SizedBox(height: 14),
                            _buildFocusPolicyPanel(),
                            const SizedBox(height: 20),
                            const Text(
                              '專注模式',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildModeGrid(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildBottomNavBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '任務',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '選一個節奏，開始今天的專注。',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPomodoroPanel() {
    final status = _pomodoroController.status;
    final isActive = _pomodoroController.isActive;
    final displayTime = status == PomodoroStatus.idle
        ? _formatMinutes(_selectedMinutes)
        : _pomodoroController.formattedRemaining;
    final progress = isActive || status == PomodoroStatus.completed
        ? _pomodoroController.progress
        : 0.0;

    return _GlassPanel(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD36B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: Color(0xFFFFD36B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '番茄鐘',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusBadge(label: _statusLabel(status)),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 196,
            height: 196,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF9FF3D0)),
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayTime,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 45,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timerCaption(status),
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _buildDurationSelector(enabled: !isActive),
          const SizedBox(height: 18),
          _buildTimerControls(status),
          if (status == PomodoroStatus.completed &&
              _focusSessionMonitor.lastCompletedReport != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => showFocusSessionReportDialog(
                  context: context,
                  report: _focusSessionMonitor.lastCompletedReport!,
                ),
                icon: const Icon(Icons.auto_graph_rounded, size: 20),
                label: const Text('查看本輪專注報告'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9FF3D0),
                  side: BorderSide(
                    color: const Color(0xFF9FF3D0).withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusPolicyPanel() {
    final episodeStatus = _focusSessionMonitor.activeEpisodeStatus;
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF9FF3D0), size: 22),
              SizedBox(width: 10),
              Text(
                '專注保護',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SessionMetric(
                label: '有效專注',
                value: _compactDuration(
                  _focusSessionMonitor.effectiveFocusDuration,
                ),
                color: const Color(0xFF9FF3D0),
              ),
              const SizedBox(width: 8),
              _SessionMetric(
                label: '分心時間',
                value: _compactDuration(
                  _focusSessionMonitor.distractedDuration,
                ),
                color: const Color(0xFFFFC36B),
              ),
              const SizedBox(width: 8),
              _SessionMetric(
                label: '事件',
                value: '${_focusSessionMonitor.totalEventCount}',
                color: const Color(0xFF79D2F5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            episodeStatus == null
                ? '只在番茄鐘進行時記錄，不會因短暫動作立刻暫停。'
                : '正在觀察：${_focusStatusLabel(episodeStatus)}',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
          _buildPolicyToggle(
            title: '保守提醒試用',
            subtitle: '只詢問是否休息，不判定睡著、不在離席時提醒，也不自動暫停。',
            value: _focusSessionMonitor.experimentalReminderPolicyEnabled,
            onChanged:
                _focusSessionMonitor.setExperimentalReminderPolicyEnabled,
          ),
          if (!_focusSessionMonitor.experimentalReminderPolicyEnabled) ...[
            Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
            _buildPolicyToggle(
              title: '嚴重狀況自動暫停',
              subtitle: '趴下或打瞌睡 8 秒；離席 10 秒。',
              value: _focusSessionMonitor.severeAutoPauseEnabled,
              onChanged: _focusSessionMonitor.setSevereAutoPauseEnabled,
            ),
            Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
            _buildPolicyToggle(
              title: '長時間分心自動暫停',
              subtitle: '關閉時，分心 15 秒只會詢問是否暫停。',
              value: _focusSessionMonitor.longDistractionAutoPauseEnabled,
              onChanged:
                  _focusSessionMonitor.setLongDistractionAutoPauseEnabled,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPolicyToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xBFFFFFFF),
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildDurationSelector({required bool enabled}) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          _DurationOption(
            label: '25 分',
            selected: _selectedMinutes == 25,
            enabled: enabled,
            onTap: () => setState(() => _selectedMinutes = 25),
          ),
          _DurationOption(
            label: '50 分',
            selected: _selectedMinutes == 50,
            enabled: enabled,
            onTap: () => setState(() => _selectedMinutes = 50),
          ),
          _DurationOption(
            label: _selectedMinutes == 25 || _selectedMinutes == 50
                ? '自訂'
                : '$_selectedMinutes 分',
            selected: _selectedMinutes != 25 && _selectedMinutes != 50,
            enabled: enabled,
            onTap: _selectCustomDuration,
          ),
        ],
      ),
    );
  }

  Widget _buildTimerControls(PomodoroStatus status) {
    final isRunning = status == PomodoroStatus.running;
    final isPaused = status == PomodoroStatus.paused;
    final canStop = isRunning || isPaused;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canStop) ...[
          _RoundControlButton(
            icon: Icons.stop_rounded,
            tooltip: '結束',
            foregroundColor: const Color(0xFFFFA071),
            onTap: _pomodoroController.stop,
          ),
          const SizedBox(width: 18),
        ],
        _RoundControlButton(
          icon: isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: isRunning ? '暫停' : (isPaused ? '回首頁繼續' : '開始'),
          isPrimary: true,
          foregroundColor: const Color(0xFF17334B),
          onTap: () {
            if (isRunning) {
              _pomodoroController.pause();
            } else if (isPaused) {
              _pomodoroController.resume();
              Navigator.popUntil(context, (route) => route.isFirst);
            } else {
              _pomodoroController.start(durationMinutes: _selectedMinutes);
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          },
        ),
      ],
    );
  }

  Widget _buildModeGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.34,
      children: [
        _ModeTile(
          icon: Icons.timer_rounded,
          title: '番茄鐘',
          subtitle: '固定節奏',
          color: const Color(0xFFFFD36B),
          isAvailable: true,
          onTap: () {},
        ),
        _ModeTile(
          icon: Icons.all_inclusive_rounded,
          title: '自由專注',
          subtitle: '開放計時',
          color: const Color(0xFF79D2F5),
          onTap: () => _showComingSoon('自由專注'),
        ),
        _ModeTile(
          icon: Icons.menu_book_rounded,
          title: '閱讀模式',
          subtitle: '閱讀姿勢',
          color: const Color(0xFF9FF3D0),
          onTap: () => _showComingSoon('閱讀模式'),
        ),
        _ModeTile(
          icon: Icons.visibility_rounded,
          title: '護眼休息',
          subtitle: '短暫放鬆',
          color: const Color(0xFFB8A7FF),
          onTap: () => _showComingSoon('護眼休息'),
        ),
      ],
    );
  }

  Future<void> _selectCustomDuration() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => _CustomDurationDialog(initialMinutes: _selectedMinutes),
    );
    if (selected != null && mounted) {
      setState(() => _selectedMinutes = selected);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature正在準備中。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return GlassBottomNavBar(
      activeTab: AppNavTab.tasks,
      glowColor: const Color(0xFF9FF3D0),
      onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      onStatisticsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StatisticsScreen()),
        );
      },
      onTasksTap: () {},
      onSettingsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$remainingMinutes:00' : '$remainingMinutes:00';
  }

  String _compactDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _focusStatusLabel(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.normal:
        return '正常';
      case CompanionStatus.attention:
        return '注意力波動';
      case CompanionStatus.fatigue:
        return '長時間閉眼';
      case CompanionStatus.distracted:
        return '分心';
      case CompanionStatus.sleeping:
        return '疑似睡著';
      case CompanionStatus.userMissing:
        return '離席';
    }
  }

  String _statusLabel(PomodoroStatus status) {
    switch (status) {
      case PomodoroStatus.idle:
        return '準備';
      case PomodoroStatus.running:
        return '進行中';
      case PomodoroStatus.paused:
        return '已暫停';
      case PomodoroStatus.completed:
        return '已完成';
    }
  }

  String _timerCaption(PomodoroStatus status) {
    switch (status) {
      case PomodoroStatus.idle:
        return '專注時間';
      case PomodoroStatus.running:
        return '保持現在的節奏';
      case PomodoroStatus.paused:
        return _pauseCaption();
      case PomodoroStatus.completed:
        return '這輪做得很好';
    }
  }

  String _pauseCaption() {
    switch (_pomodoroController.pauseReason) {
      case PomodoroPauseReason.navigation:
        return '切換頁面，回首頁後自動繼續';
      case PomodoroPauseReason.appBackground:
        return '離開 App，回首頁後可繼續';
      case PomodoroPauseReason.distracted:
        return '分心過久，已自動暫停';
      case PomodoroPauseReason.fatigue:
        return '閉眼過久，已自動暫停';
      case PomodoroPauseReason.drowsy:
        return '疑似打瞌睡，已自動暫停';
      case PomodoroPauseReason.postureDown:
        return '偵測到趴下，已自動暫停';
      case PomodoroPauseReason.userMissing:
        return '離席過久，已自動暫停';
      case PomodoroPauseReason.manual:
      case null:
        return '休息一下再繼續';
    }
  }
}

class _SessionMetric extends StatelessWidget {
  const _SessionMetric({
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
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xBFFFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomDurationDialog extends StatefulWidget {
  const _CustomDurationDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_CustomDurationDialog> createState() => _CustomDurationDialogState();
}

class _CustomDurationDialogState extends State<_CustomDurationDialog> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.initialMinutes.toString(),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _apply() {
    final minutes = int.tryParse(_textController.text)?.clamp(1, 180);
    if (minutes != null) Navigator.pop(context, minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自訂專注時間'),
      content: TextField(
        controller: _textController,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: '分鐘', hintText: '1 - 180'),
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _apply, child: const Text('套用')),
      ],
    );
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 24,
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF9FF3D0).withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF9FF3D0).withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFCAFFE9),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DurationOption extends StatelessWidget {
  const _DurationOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: enabled ? 0.22 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.45),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.icon,
    required this.tooltip,
    required this.foregroundColor,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String tooltip;
  final Color foregroundColor;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final size = isPrimary ? 64.0 : 50.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isPrimary
            ? const Color(0xFF9FF3D0)
            : Colors.white.withValues(alpha: 0.13),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: foregroundColor,
              size: isPrimary ? 34 : 27,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isAvailable = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: isAvailable ? 0.18 : 0.11),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isAvailable
                      ? color.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 24),
                      const Spacer(),
                      Icon(
                        isAvailable
                            ? Icons.check_circle_rounded
                            : Icons.lock_clock_rounded,
                        color: isAvailable
                            ? color
                            : Colors.white.withValues(alpha: 0.46),
                        size: 17,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xBFFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
