import 'package:flutter/material.dart';

import '../focus/pomodoro_controller.dart';

class QuickExperienceButton extends StatelessWidget {
  const QuickExperienceButton({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  final PomodoroController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isActive = controller.isActive;
        return Tooltip(
          message: isActive ? '目前已有專注場次，可從下方番茄鐘暫停或繼續。' : '完成相機校正後，直接開始一分鐘專注體驗。',
          child: FilledButton.icon(
            key: const ValueKey('quick-experience-button'),
            onPressed: onPressed,
            icon: Icon(
              isActive ? Icons.timer_rounded : Icons.bolt_rounded,
              size: 19,
            ),
            label: Text(isActive ? '專注場次進行中' : '1 分鐘快速體驗'),
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF397D9B),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
              shadowColor: const Color(0x66305F76),
            ),
          ),
        );
      },
    );
  }
}
