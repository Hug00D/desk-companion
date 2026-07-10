import 'api_client.dart';

class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  String get baseUrl => _client.baseUrl;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final data = await _client.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );

    return AuthResult.fromJson(data, fallbackEmail: email);
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = await _client.post(
      '/users/register',
      body: {'email': email, 'password': password, 'displayName': displayName},
    );

    return AuthResult.fromJson(data, fallbackEmail: email);
  }
}

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.email,
    this.accessToken,
    this.message,
  });

  final String userId;
  final String email;
  final String? accessToken;
  final String? message;

  factory AuthResult.fromJson(
    Map<String, dynamic> json, {
    required String fallbackEmail,
  }) {
    final userId = json['userId'] ?? json['id'];

    return AuthResult(
      userId: userId?.toString() ?? '',
      email: json['email']?.toString() ?? fallbackEmail,
      accessToken: json['accessToken']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
