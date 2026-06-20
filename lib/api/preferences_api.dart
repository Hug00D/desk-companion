import '../preferences/companion_preferences.dart';
import 'api_client.dart';

class PreferencesApi {
  const PreferencesApi(this._client);

  final ApiClient _client;

  Future<CompanionPreferences> getPreferences({
    required String userId,
    String? accessToken,
  }) async {
    final data = await _client.get(
      '/users/$userId/preferences',
      accessToken: accessToken,
    );
    return CompanionPreferences.fromJson(data);
  }

  Future<CompanionPreferences> updatePreferences({
    required String userId,
    required CompanionPreferences preferences,
    String? accessToken,
  }) async {
    final data = await _client.put(
      '/users/$userId/preferences',
      body: preferences.toJson(),
      accessToken: accessToken,
    );
    return CompanionPreferences.fromJson(data);
  }
}
