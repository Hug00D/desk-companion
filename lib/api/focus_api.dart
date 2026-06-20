import '../events/companion_event.dart';
import '../focus/focus_round.dart';
import '../focus/study_session.dart';
import 'api_client.dart';

class FocusApi {
  const FocusApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> createSession({
    required String userId,
    required StudySessionSnapshot session,
    String? accessToken,
  }) {
    return _client.post(
      '/users/$userId/focus-sessions',
      body: session.toCreatePayload(),
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> updateSession({
    required String userId,
    required String sessionId,
    required StudySessionSnapshot session,
    String? accessToken,
  }) {
    return _client.patch(
      '/users/$userId/focus-sessions/$sessionId',
      body: session.toUpdatePayload(),
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> createRound({
    required String userId,
    required String sessionId,
    required FocusRoundSnapshot round,
    String? accessToken,
  }) {
    return _client.post(
      '/users/$userId/focus-sessions/$sessionId/rounds',
      body: round.toJson(),
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> updateRound({
    required String userId,
    required String sessionId,
    required String roundId,
    required FocusRoundSnapshot round,
    String? accessToken,
  }) {
    return _client.patch(
      '/users/$userId/focus-sessions/$sessionId/rounds/$roundId',
      body: round.toJson(),
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> uploadEvents({
    required String userId,
    required String sessionId,
    required Iterable<CompanionEvent> events,
    String? accessToken,
  }) {
    return _client.post(
      '/users/$userId/focus-sessions/$sessionId/events/batch',
      body: CompanionEvent.batchPayload(events),
      accessToken: accessToken,
    );
  }
}
