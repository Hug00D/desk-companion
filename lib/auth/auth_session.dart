import 'package:flutter/foundation.dart';

class AuthSession extends ChangeNotifier {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  String? _userId;
  String? _email;
  String? _accessToken;
  String? _displayName;

  String? get userId => _userId;
  String? get email => _email;
  String? get accessToken => _accessToken;
  bool get isSignedIn => _userId != null;
  String get displayName {
    final name = _displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final fallback = _email?.split('@').first.trim();
    return fallback == null || fallback.isEmpty ? 'Reader' : fallback;
  }

  void updateDisplayName(String? name, {required String userId}) {
    if (_userId != userId || name == null || name.trim().isEmpty) return;
    _displayName = name.trim();
    notifyListeners();
  }

  void setSession({
    required String userId,
    required String email,
    String? accessToken,
  }) {
    _userId = userId;
    _displayName = null;
    _email = email;
    _accessToken = accessToken;
    notifyListeners();
  }

  void clear() {
    _userId = null;
    _email = null;
    _accessToken = null;
    _displayName = null;
    notifyListeners();
  }
}
