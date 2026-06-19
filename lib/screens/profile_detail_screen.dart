import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/profile_api.dart';
import '../auth/auth_session.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/rive_asset_background.dart';
import 'profile_hub_screen.dart';
import 'statistics_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({super.key});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final AuthSession _session = AuthSession.instance;
  final ProfileApi _profileApi = ProfileApi(ApiClient());
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _avatarUrlController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadMessage;

  @override
  void initState() {
    super.initState();
    _displayNameController.text = _fallbackDisplayName;
    _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  String get _fallbackEmail => _session.email ?? 'reader@desk-companion.local';

  String get _fallbackDisplayName {
    final email = _session.email;
    if (email == null || email.isEmpty) return 'Reader';
    return email.split('@').first;
  }

  String get _avatarInitial {
    final name = _displayNameController.text.trim();
    if (name.isNotEmpty) return name.characters.first.toUpperCase();
    return _fallbackDisplayName.characters.first.toUpperCase();
  }

  Future<void> _loadProfile() async {
    if (!_session.isSignedIn) {
      setState(() => _loadMessage = '目前是 Demo 模式，登入後可同步個人資料。');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadMessage = null;
    });

    try {
      final profile = await _profileApi.getMyProfile(_session);
      if (!mounted) return;
      final displayName = profile['displayName']?.toString().trim();
      final avatarUrl = profile['avatarUrl']?.toString().trim();
      _displayNameController.text = displayName == null || displayName.isEmpty
          ? _fallbackDisplayName
          : displayName;
      _avatarUrlController.text = avatarUrl ?? '';
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadMessage = '讀取個人資料失敗：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadMessage = '讀取個人資料失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    final avatarUrl = _avatarUrlController.text.trim();

    if (displayName.isEmpty) {
      _showSnackBar('暱稱不能空白。');
      return;
    }

    if (!_session.isSignedIn) {
      _showSnackBar('目前是 Demo 模式，尚未連到後端帳號。');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _profileApi.updateMyProfile(
        session: _session,
        body: {
          'displayName': displayName,
          'avatarUrl': avatarUrl.isEmpty ? null : avatarUrl,
        },
      );
      if (!mounted) return;
      _showSnackBar('個人檔案已更新。');
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnackBar('儲存失敗：${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('儲存失敗：$e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showComingSoon(String title) {
    _showSnackBar('$title 之後會接上正式頁面。');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10283D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RiveAssetBackground(
            assetPath: 'assets/test2.riv',
            motionIntensity: 4,
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8810283D),
                  Color(0x4410283D),
                  Color(0xCC10283D),
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
                        _GlassPanel(child: _buildIdentityCard()),
                        const SizedBox(height: 14),
                        _GlassPanel(child: _buildEditForm()),
                        const SizedBox(height: 14),
                        _GlassPanel(child: _buildAccountInfo()),
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
          '個人檔案',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '管理你的暱稱、頭像與帳號資料。',
          style: TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _avatarInitial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ListenableBuilder(
            listenable: _displayNameController,
            builder: (context, child) {
              final displayName = _displayNameController.text.trim().isEmpty
                  ? _fallbackDisplayName
                  : _displayNameController.text.trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fallbackEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StatusPill(
                    label: _session.isSignedIn ? '已連接後端帳號' : 'Demo 模式',
                    color: _session.isSignedIn
                        ? const Color(0xFF9FF3D0)
                        : const Color(0xFFFFD36B),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('基本資料', style: _sectionTitleStyle),
        const SizedBox(height: 14),
        _GlassTextField(
          controller: _displayNameController,
          label: '暱稱',
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: 12),
        _GlassTextField(
          controller: _avatarUrlController,
          label: '頭像網址',
          icon: Icons.image_rounded,
          hintText: 'https://example.com/avatar.png',
        ),
        if (_loadMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _loadMessage!,
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _isLoading || _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? '儲存中' : '儲存個人檔案'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9FF3D0),
              foregroundColor: const Color(0xFF10283D),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('帳號狀態', style: _sectionTitleStyle),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.mail_rounded,
          label: 'Email',
          value: _fallbackEmail,
          color: const Color(0xFF79D2F5),
        ),
        const Divider(height: 24, color: Color(0x22FFFFFF)),
        _InfoRow(
          icon: Icons.verified_user_rounded,
          label: '狀態',
          value: _session.isSignedIn ? 'ACTIVE' : '尚未登入',
          color: const Color(0xFF9FF3D0),
        ),
        const Divider(height: 24, color: Color(0x22FFFFFF)),
        _InfoRow(
          icon: Icons.key_rounded,
          label: 'User ID',
          value: _session.userId ?? 'Demo user',
          color: const Color(0xFFFFD36B),
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
      onTasksTap: () => _showComingSoon('任務'),
      onSettingsTap: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }
}

const _sectionTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 17,
  fontWeight: FontWeight.w900,
);

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

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.8)),
        labelStyle: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF9FF3D0), width: 1.4),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
