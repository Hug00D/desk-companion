import 'package:flutter/material.dart';

import '../focus/pomodoro_controller.dart';

class PomodoroDockPanel extends StatelessWidget {
  const PomodoroDockPanel({
    super.key,
    required this.controller,
    required this.onTap,
  });

  final PomodoroController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final status = controller.status;
        final caption = switch (status) {
          PomodoroStatus.idle => '番茄鐘',
          PomodoroStatus.running => '番茄鐘・專注中',
          PomodoroStatus.paused => '番茄鐘・已暫停',
          PomodoroStatus.completed => '番茄鐘・已完成',
        };
        final time = status == PomodoroStatus.idle
            ? '開始專注'
            : controller.formattedRemaining;
        final canToggle =
            status == PomodoroStatus.running || status == PomodoroStatus.paused;
        final isRunning = status == PomodoroStatus.running;

        return Tooltip(
          message: '開啟番茄鐘設定與控制',
          child: Material(
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '開啟番茄鐘設定與控制',
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    size: 13,
                                    color: Color(0xE6FFFFFF),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    caption,
                                    style: const TextStyle(
                                      color: Color(0xE6FFFFFF),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                time,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                  shadows: [
                                    Shadow(
                                      color: Color(0x440E3954),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (canToggle) ...[
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  Tooltip(
                    message: isRunning ? '暫停番茄鐘' : '繼續番茄鐘',
                    child: IconButton(
                      key: const ValueKey('pomodoro-dock-toggle'),
                      onPressed: isRunning
                          ? controller.pause
                          : controller.resume,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
