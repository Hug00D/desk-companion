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
    this.raisedPanel,
  });

  static const double barHeight = 78;
  static const double bottomInset = 10;
  static const double horizontalInset = 14;
  static const double contentBottomPadding = 136;
  static const double raisedPanelHeight = 60;
  static const double raisedContentBottomPadding =
      contentBottomPadding + raisedPanelHeight;

  final AppNavTab activeTab;
  final VoidCallback onHomeTap;
  final VoidCallback onStatisticsTap;
  final VoidCallback onTasksTap;
  final VoidCallback onSettingsTap;
  final Listenable? animation;
  final Color? glowColor;
  final double Function()? glowPulseBuilder;
  final Widget? raisedPanel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: bottomInset,
      child: SafeArea(top: false, child: _buildGlassBody(context)),
    );
  }

  Widget _buildGlassBody(BuildContext context) {
    final statusColor = glowColor ?? const Color(0xFF79D2F5);
    final rise = raisedPanel == null ? 0.0 : raisedPanelHeight;
    final clipper = _NavGlassClipper(raised: raisedPanel != null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = _raisedPanelWidth(constraints.maxWidth);
        return PhysicalShape(
          clipper: clipper,
          color: Colors.transparent,
          elevation: 6,
          shadowColor: statusColor.withValues(alpha: 0.20),
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: CustomPaint(
              foregroundPainter: _NavGlassBorder(clipper),
              child: Container(
                height: barHeight + rise,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.11),
                ),
                child: Stack(
                  children: [
                    if (raisedPanel != null) ...[
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: rise,
                        child: ColoredBox(
                          color: const Color(
                            0xFF9EDFFF,
                          ).withValues(alpha: 0.22),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: (constraints.maxWidth - panelWidth) / 2,
                        width: panelWidth,
                        height: rise - 8,
                        child: raisedPanel!,
                      ),
                    ],
                    if (animation == null)
                      _buildGlowLine(statusColor, 0.16, top: rise)
                    else
                      AnimatedBuilder(
                        animation: animation!,
                        builder: (context, child) => _buildGlowLine(
                          statusColor,
                          (glowPulseBuilder?.call() ?? 0.16).clamp(0.0, 1.0),
                          top: rise,
                        ),
                      ),
                    Positioned(
                      top: rise,
                      left: 0,
                      right: 0,
                      height: barHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlowLine(Color statusColor, double pulse, {double top = 0}) {
    final glowAlpha = 0.18 + pulse * 0.32;
    return Positioned(
      left: 18,
      right: 18,
      top: top,
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: glowAlpha * 0.7),
              blurRadius: 4 + pulse * 6,
            ),
          ],
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              statusColor.withValues(alpha: glowAlpha),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

double _raisedPanelWidth(double width) => (width * 0.52).clamp(136.0, 184.0);

class _NavGlassClipper extends CustomClipper<Path> {
  const _NavGlassClipper({required this.raised});

  final bool raised;

  @override
  Path getClip(Size size) {
    if (!raised) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28)),
      );
    }
    final panelWidth = _raisedPanelWidth(size.width);
    final left = (size.width - panelWidth) / 2;
    final right = left + panelWidth;
    const top = GlassBottomNavBar.raisedPanelHeight;

    return Path()
      ..moveTo(28, top)
      ..lineTo(left - 22, top)
      ..cubicTo(left - 4, top, left - 14, 0, left + 18, 0)
      ..lineTo(right - 18, 0)
      ..cubicTo(right + 14, 0, right + 4, top, right + 22, top)
      ..lineTo(size.width - 28, top)
      ..quadraticBezierTo(size.width, top, size.width, top + 28)
      ..lineTo(size.width, size.height - 28)
      ..quadraticBezierTo(size.width, size.height, size.width - 28, size.height)
      ..lineTo(28, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 28)
      ..lineTo(0, top + 28)
      ..quadraticBezierTo(0, top, 28, top)
      ..close();
  }

  @override
  bool shouldReclip(_NavGlassClipper oldClipper) => raised != oldClipper.raised;
}

class _NavGlassBorder extends CustomPainter {
  const _NavGlassBorder(this.clipper);

  final _NavGlassClipper clipper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      clipper.getClip(size),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_NavGlassBorder oldDelegate) =>
      clipper.raised != oldDelegate.clipper.raised;
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
