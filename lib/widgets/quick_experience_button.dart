import 'package:flutter/material.dart';

import '../focus/pomodoro_controller.dart';
import 'expandable_hud_control.dart';

class QuickExperienceButton extends StatelessWidget {
  const QuickExperienceButton({
    super.key,
    required this.controller,
    required this.onPressed,
    required this.onOpenPomodoro,
  });

  final PomodoroController controller;
  final VoidCallback onPressed;
  final VoidCallback onOpenPomodoro;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isActive = controller.isActive;
        return ExpandableHudControl(
          controlId: 'quick-experience',
          semanticName: '番茄鐘',
          icon: Icons.schedule_rounded,
          label: isActive ? '專注場次進行中' : '1 分鐘快速體驗',
          detail: isActive ? '點擊開啟番茄鐘頁面，管理目前場次。' : '完成相機校正後，點擊開始一分鐘專注體驗。',
          color: isActive ? const Color(0xFF247D65) : const Color(0xFF397D9B),
          onPressed: () {
            if (controller.isActive) {
              onOpenPomodoro();
            } else {
              onPressed();
            }
          },
        );
      },
    );
  }
}
