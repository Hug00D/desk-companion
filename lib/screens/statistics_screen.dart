import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/rive_asset_background.dart';
import 'profile_hub_screen.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10283D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RiveAssetBackground(
            assetPath: 'assets/test2.riv',
            motionIntensity: 5,
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x6610283D),
                  Color(0x2210283D),
                  Color(0xAA10283D),
                ],
              ),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
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
                        const SizedBox(height: 18),
                        _GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('今日摘要', style: _sectionTitleStyle),
                              const SizedBox(height: 14),
                              Row(
                                children: const [
                                  Expanded(
                                    child: _MetricTile(
                                      label: '專注時間',
                                      value: '2h 35m',
                                      icon: Icons.timer_rounded,
                                      color: Color(0xFF9FF3D0),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _MetricTile(
                                      label: '完成輪數',
                                      value: '5',
                                      icon: Icons.check_circle_rounded,
                                      color: Color(0xFF79D2F5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: const [
                                  Expanded(
                                    child: _MetricTile(
                                      label: '提醒次數',
                                      value: '7',
                                      icon: Icons.notifications_rounded,
                                      color: Color(0xFFFFD36B),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _MetricTile(
                                      label: '離席時間',
                                      value: '12m',
                                      icon: Icons.airline_seat_recline_normal,
                                      color: Color(0xFF9AC7FF),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _GlassPanel(child: _buildFocusTrend()),
                        const SizedBox(height: 14),
                        _GlassPanel(child: _buildStateDistribution()),
                        const SizedBox(height: 14),
                        _GlassPanel(child: _buildRecentEvents()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildBottomNavBar(context),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return const Column(
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
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return GlassBottomNavBar(
      activeTab: AppNavTab.statistics,
      onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      onStatisticsTap: () {},
      onTasksTap: () => _showComingSoon(context, '任務'),
      onSettingsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 之後會接上正式頁面。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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

  Widget _buildFocusTrend() {
    final values = <double>[0.32, 0.56, 0.42, 0.74, 0.68, 0.86, 0.61];
    final labels = <String>['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('本週專注趨勢', style: _sectionTitleStyle),
        const SizedBox(height: 18),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: values[i],
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
                          labels[i],
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStateDistribution() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('狀態分布', style: _sectionTitleStyle),
        SizedBox(height: 14),
        _ProgressRow(label: '穩定專注', value: 0.68, color: Color(0xFF9FF3D0)),
        _ProgressRow(label: '注意力波動', value: 0.18, color: Color(0xFFFFD36B)),
        _ProgressRow(label: '疲勞 / 打瞌睡', value: 0.09, color: Color(0xFFFF7A3D)),
        _ProgressRow(label: '離席', value: 0.05, color: Color(0xFF9AC7FF)),
      ],
    );
  }

  Widget _buildRecentEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('最近提醒', style: _sectionTitleStyle),
        SizedBox(height: 12),
        _EventRow(
          time: '14:20',
          title: '視線偏離',
          detail: '連續分心 3 次，已跳出提醒泡泡。',
          color: Color(0xFFFFD36B),
        ),
        _EventRow(
          time: '13:48',
          title: '眼睛疲勞',
          detail: '閉眼時間偏長，建議休息 2 分鐘。',
          color: Color(0xFFFF7A3D),
        ),
        _EventRow(
          time: '13:12',
          title: '完成一輪專注',
          detail: '25 分鐘專注完成，表現穩定。',
          color: Color(0xFF9FF3D0),
        ),
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
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
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
    required this.color,
  });

  final String label;
  final double value;
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
                '${(value * 100).round()}%',
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

const TextStyle _sectionTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w900,
);
