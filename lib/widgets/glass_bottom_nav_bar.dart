import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

enum AppNavTab { home, statistics, tasks, settings }

class GlassBottomNavBar extends StatelessWidget {
  const GlassBottomNavBar({
    super.key,
    required this.activeTab,
    required this.onHomeTap,
    required this.onStatisticsTap,
    required this.onTasksTap,
    required this.onSettingsTap,
    this.animation,
    this.glowColor,
    this.glowPulseBuilder,
  });

  static const double barHeight = 78;
  static const double bottomInset = 10;
  static const double horizontalInset = 14;
  static const double contentBottomPadding = 136;

  final AppNavTab activeTab;
  final VoidCallback onHomeTap;
  final VoidCallback onStatisticsTap;
  final VoidCallback onTasksTap;
  final VoidCallback onSettingsTap;
  final Listenable? animation;
  final Color? glowColor;
  final double Function()? glowPulseBuilder;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: bottomInset,
      child: SafeArea(
        top: false,
        child: animation == null
            ? _buildGlassBody(context)
            : AnimatedBuilder(
                animation: animation!,
                builder: (context, child) => _buildGlassBody(context),
              ),
      ),
    );
  }

  Widget _buildGlassBody(BuildContext context) {
    final statusColor = glowColor ?? const Color(0xFF79D2F5);
    final pulse = (glowPulseBuilder?.call() ?? 0.16).clamp(0.0, 1.0);
    final glowAlpha = 0.18 + pulse * 0.32;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: barHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: glowAlpha),
                blurRadius: 22 + pulse * 20,
                spreadRadius: 0.6 + pulse * 1.8,
              ),
              const BoxShadow(
                color: Color(0x24000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 18,
                right: 18,
                top: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        statusColor.withValues(alpha: glowAlpha),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    label: '首頁',
                    isActive: activeTab == AppNavTab.home,
                    activeColor: statusColor,
                    onTap: onHomeTap,
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_rounded,
                    label: '統計',
                    isActive: activeTab == AppNavTab.statistics,
                    activeColor: statusColor,
                    onTap: onStatisticsTap,
                  ),
                  _NavItem(
                    icon: Icons.track_changes_rounded,
                    label: '任務',
                    isActive: activeTab == AppNavTab.tasks,
                    activeColor: statusColor,
                    onTap: onTasksTap,
                  ),
                  _NavItem(
                    icon: Icons.settings_rounded,
                    label: '設定',
                    isActive: activeTab == AppNavTab.settings,
                    activeColor: statusColor,
                    onTap: onSettingsTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? activeColor.withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.82);

    return Expanded(
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.96)
                      : Colors.white.withValues(alpha: 0.68),
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
