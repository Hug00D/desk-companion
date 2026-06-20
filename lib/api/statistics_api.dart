import '../statistics/statistics_summary.dart';
import 'api_client.dart';

class StatisticsApi {
  const StatisticsApi(this._client);

  final ApiClient _client;

  Future<StatisticsSummary> getSummary({
    required String userId,
    required DateTime from,
    required DateTime to,
    required String timezone,
    String? accessToken,
  }) async {
    final data = await _client.get(
      '/users/$userId/statistics',
      accessToken: accessToken,
      queryParameters: <String, String?>{
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'timezone': timezone,
      },
    );
    return StatisticsSummary.fromJson(data);
  }
}
