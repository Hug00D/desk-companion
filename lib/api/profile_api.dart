import '../auth/auth_session.dart';
import 'api_client.dart';

class ProfileApi {
  const ProfileApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getProfile({
    required String userId,
    String? accessToken,
  }) {
    return _client.get('/users/$userId/profile', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String userId,
    required Map<String, dynamic> body,
    String? accessToken,
  }) {
    return _client.put(
      '/users/$userId/profile',
      body: body,
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> getMyProfile(AuthSession session) {
    return getProfile(
      userId: session.userId!,
      accessToken: session.accessToken,
    );
  }

  Future<Map<String, dynamic>> updateMyProfile({
    required AuthSession session,
    required Map<String, dynamic> body,
  }) {
    return updateProfile(
      userId: session.userId!,
      body: body,
      accessToken: session.accessToken,
    );
  }
}
