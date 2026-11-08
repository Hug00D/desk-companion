import 'dart:async';
import 'dart:convert';

import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/profile_api.dart';
import 'package:desk_companion/auth/auth_session.dart';
import 'package:desk_companion/screens/profile_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final auth = AuthSession.instance;
  setUp(() => auth.setSession(userId: 'user-a', email: 'reader@example.test'));
  tearDown(auth.clear);

  testWidgets('saving a profile refreshes an already visible settings name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = ProfileApi(
      ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'displayName': '新的暱稱'}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileHubScreen()));
    expect(find.text('reader'), findsOneWidget);
    await api.updateMyProfile(session: auth, body: {'displayName': '新的暱稱'});
    await tester.pump();
    expect(find.text('新的暱稱'), findsOneWidget);
    expect(find.text('reader'), findsNothing);
  });

  test('a failed profile save keeps the previously confirmed name', () async {
    auth.updateDisplayName('原本暱稱', userId: 'user-a');
    final api = ProfileApi(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response('{"message":"unavailable"}', 503),
        ),
      ),
    );
    await expectLater(
      api.updateMyProfile(session: auth, body: {'displayName': '未儲存暱稱'}),
      throwsA(isA<ApiException>()),
    );
    expect(auth.displayName, '原本暱稱');
  });

  test(
    'a delayed profile response does not rename a different account',
    () async {
      final response = Completer<http.Response>();
      final api = ProfileApi(
        ApiClient(httpClient: MockClient((_) => response.future)),
      );
      final pending = api.getMyProfile(auth);
      auth.setSession(userId: 'user-b', email: 'other@example.test');
      response.complete(http.Response('{"displayName":"old user"}', 200));
      await pending;
      expect(auth.displayName, 'other');
    },
  );
}
