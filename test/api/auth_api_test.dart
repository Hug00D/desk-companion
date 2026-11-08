import 'dart:convert';

import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'login sends original credentials and accepts the backend success contract',
    () async {
      final api = AuthApi(
        ApiClient(
          baseUrl: 'http://auth.test/api/v1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/auth/login');
            expect(jsonDecode(request.body), {
              'email': 'test@example.test',
              'password': ' test-password ',
            });
            expect(request.headers.containsKey('authorization'), isFalse);
            return http.Response(
              jsonEncode({
                'userId': 'test-user',
                'email': 'test@example.test',
                'message': 'Login successful.',
              }),
              200,
            );
          }),
        ),
      );
      final result = await api.login(
        email: 'test@example.test',
        password: ' test-password ',
      );
      expect(result.userId, 'test-user');
      expect(result.email, 'test@example.test');
    },
  );
}
