import 'package:flutter/foundation.dart';

class AuthSession extends ChangeNotifier {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  String? _userId;
  String? _email;
  String? _accessToken;

  String? get userId => _userId;
  String? get email => _email;
  String? get accessToken => _accessToken;
  bool get isSignedIn => _userId != null;

  void setSession({
    required String userId,
    required String email,
    String? accessToken,
  }) {
    _userId = userId;
    _email = email;
    _accessToken = accessToken;
    notifyListeners();
  }

  void clear() {
    _userId = null;
    _email = null;
    _accessToken = null;
    notifyListeners();
  }
}
