import 'package:flutter/material.dart';

import '../auth/auth_session.dart';

class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AuthSession.instance;
    final email = session.email ?? 'reader@desk-companion.local';
    final displayName = email.split('@').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFD),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 250,
            elevation: 0,
            backgroundColor: const Color(0xFF12304A),
            foregroundColor: Colors.white,
            title: const Text(
              '我的',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHero(displayName: displayName, email: email),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatStrip(),
                  const SizedBox(height: 22),
                  _buildSection(
                    title: '讀書狀態',
                    children: [
                      _buildOptionTile(
                        icon: Icons.insights_rounded,
                        title: '專注報告',
                        subtitle: '查看分數、疲勞與離開紀錄',
                        color: const Color(0xFF2F7ED8),
                        onTap: () => _showComingSoon(context, '專注報告'),
                      ),
                      _buildOptionTile(
                        icon: Icons.history_rounded,
                        title: '歷史紀錄',
                        subtitle: '回顧番茄鐘、語音互動與視覺事件',
                        color: const Color(0xFF57BEEB),
                        onTap: () => _showComingSoon(context, '歷史紀錄'),
                      ),
                      _buildOptionTile(
                        icon: Icons.emoji_events_rounded,
                        title: '成就與習慣',
                        subtitle: '整理連續讀書天數與完成輪數',
                        color: const Color(0xFFFFB648),
                        onTap: () => _showComingSoon(context, '成就與習慣'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '個人與偏好',
                    children: [
                      _buildOptionTile(
                        icon: Icons.person_rounded,
                        title: '個人資料',
                        subtitle: '編輯暱稱、頭像與基本資料',
                        color: const Color(0xFF8A8EF2),
                        onTap: () => _showComingSoon(context, '個人資料'),
                      ),
                      _buildOptionTile(
                        icon: Icons.smart_toy_rounded,
                        title: 'AI 偏好',
                        subtitle: '設定陪伴語氣、安靜模式與提醒敏感度',
                        color: const Color(0xFF2F7ED8),
                        onTap: () => _showComingSoon(context, 'AI 偏好'),
                      ),
                      _buildOptionTile(
                        icon: Icons.notifications_active_rounded,
                        title: '提醒設定',
                        subtitle: '調整疲勞、休息與番茄鐘提醒',
                        color: const Color(0xFFE85D75),
                        onTap: () => _showComingSoon(context, '提醒設定'),
                      ),
                      _buildOptionTile(
                        icon: Icons.privacy_tip_rounded,
                        title: '隱私與權限',
                        subtitle: '管理鏡頭、語音與資料保存設定',
                        color: const Color(0xFF4FB998),
                        onTap: () => _showComingSoon(context, '隱私與權限'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '帳號',
                    children: [
                      _buildOptionTile(
                        icon: Icons.logout_rounded,
                        title: '登出',
                        subtitle: '離開目前帳號',
                        color: const Color(0xFFE85D75),
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
    );
  }

  Widget _buildHero({required String displayName, required String email}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10283D), Color(0xFF1D6B8F), Color(0xFF79D2F5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: 44,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -45,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFF57BEEB).withOpacity(0.22),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 74, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x26000000),
                              blurRadius: 22,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            displayName.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
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
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.76),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Text(
                      '今天先保持節奏，讓每一輪專注都有跡可循。',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatStrip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8EEF8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem('今日', '0m'),
          _buildStatDivider(),
          _buildStatItem('完成', '0 輪'),
          _buildStatDivider(),
          _buildStatItem('提醒', '0 次'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF20324D),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF63758C),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 30, color: const Color(0xFFE1F0F7));
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF63758C),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDDEEF6)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
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
                      style: TextStyle(
                        color: isDestructive
                            ? const Color(0xFFE85D75)
                            : const Color(0xFF20324D),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF63758C),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9EB2C5)),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 頁面之後會接上正式功能。'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
