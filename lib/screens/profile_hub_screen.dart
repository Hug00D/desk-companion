import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../preferences/companion_preferences.dart';
import '../preferences/companion_preferences_controller.dart';
import '../vision/vision_calibration_request_controller.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import 'profile_detail_screen.dart';
import 'statistics_screen.dart';
import 'tasks_screen.dart';

class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AuthSession.instance;
    final email = session.email ?? 'reader@desk-companion.local';
    final displayName = email.split('@').first;

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
                  Color(0xBB10283D),
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
                        _buildProfileEntryCard(
                          context: context,
                          displayName: displayName,
                          email: email,
                        ),
                        const SizedBox(height: 14),
                        ValueListenableBuilder<CompanionPreferences>(
                          valueListenable:
                              CompanionPreferencesController.instance,
                          builder: (context, preferences, _) {
                            final controller =
                                CompanionPreferencesController.instance;
                            return _SettingsSection(
                              title: '提醒與陪伴',
                              children: [
                                _SettingsTile(
                                  icon: Icons.smart_toy_rounded,
                                  title: 'AI 回覆語氣',
                                  subtitle:
                                      '目前：${preferences.aiResponseTone.label}，點擊切換語氣。',
                                  color: const Color(0xFF79D2F5),
                                  onTap: controller.cycleResponseTone,
                                ),
                                _SettingsTile(
                                  icon: Icons.bedtime_rounded,
                                  title: '安靜模式',
                                  subtitle: preferences.quietMode
                                      ? '已開啟：只記錄狀態，不主動打擾。'
                                      : '已關閉：偵測到狀態時會照常提醒。',
                                  color: const Color(0xFF9FF3D0),
                                  trailing: Switch.adaptive(
                                    value: preferences.quietMode,
                                    onChanged: controller.setQuietMode,
                                  ),
                                  onTap: () => controller.setQuietMode(
                                    !preferences.quietMode,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        _SettingsSection(
                          title: '偵測與資料',
                          children: [
                            _SettingsTile(
                              icon: Icons.center_focus_strong_rounded,
                              title: '重新校正基準',
                              subtitle: '回到主畫面，依提示坐好後重新建立視覺基準。',
                              color: const Color(0xFF9AC7FF),
                              onTap: () {
                                VisionCalibrationRequestController.instance
                                    .requestRecalibration();
                                Navigator.popUntil(
                                  context,
                                  (route) => route.isFirst,
                                );
                              },
                            ),
                            _SettingsTile(
                              icon: Icons.videocam_rounded,
                              title: '鏡頭與測試來源',
                              subtitle: '之後接相機、測試影片與權限設定。',
                              color: const Color(0xFF8A8EF2),
                              onTap: () => _showComingSoon(context, '鏡頭與測試來源'),
                            ),
                            _SettingsTile(
                              icon: Icons.privacy_tip_rounded,
                              title: '資料與隱私',
                              subtitle: '管理本機紀錄、同步與資料保存方式。',
                              color: const Color(0xFF4FB998),
                              onTap: () => _showComingSoon(context, '資料與隱私'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _SettingsSection(
                          title: '帳號',
                          children: [
                            _SettingsTile(
                              icon: Icons.logout_rounded,
                              title: '登出',
                              subtitle: '離開目前帳號，回到登入畫面。',
                              color: const Color(0xFFFF7A3D),
                              isDestructive: true,
                              onTap: () => _showComingSoon(context, '登出'),
                            ),
                          ],
                        ),
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
          '設定',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '調整提醒與陪伴方式。',
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
      activeTab: AppNavTab.settings,
      onHomeTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      onStatisticsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const StatisticsScreen()),
        );
      },
      onTasksTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const TasksScreen()),
        );
      },
      onSettingsTap: () {},
    );
  }

  Widget _buildProfileEntryCard({
    required BuildContext context,
    required String displayName,
    required String email,
  }) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileDetailScreen(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '查看與編輯個人檔案',
                        style: TextStyle(
                          color: Color(0xAAFFFFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xCCFFFFFF),
                ),
              ],
            ),
          ),
        ),
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
                '設定',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '先整理成 Demo 入口，後續再接實際功能。',
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

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 之後會接上正式功能。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.trailing,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDestructive
                            ? const Color(0xFFFFB19A)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 10),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xAAFFFFFF),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: padding,
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
