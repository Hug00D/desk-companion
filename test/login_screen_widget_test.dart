import 'package:desk_companion/screens/login_screen.dart';
import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/auth_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'a rejected login shows its actual cause and can be submitted again',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempts = 0;
      final api = AuthApi(
        ApiClient(
          httpClient: MockClient((_) async {
            attempts++;
            return http.Response(
              '{"errorCode":"INVALID_CREDENTIALS","message":"Invalid email or password."}',
              401,
            );
          }),
        ),
      );
      await tester.pumpWidget(MaterialApp(home: LoginScreen(authApi: api)));
      await tester.enterText(find.byType(TextField).at(0), 'test@example.test');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.text('登入'));
      await tester.pumpAndSettle();
      expect(find.text('電子郵件或密碼未通過驗證，請確認後再試。'), findsOneWidget);
      expect(find.text('目前帳號無法存取資料，請重新登入後再試。'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.text('登入'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
    },
  );

  testWidgets('login hides unfinished recovery and Google entry points', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Forgot Password?'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('OR'), findsNothing);
    expect(find.text('登入'), findsOneWidget);
    expect(find.textContaining('註冊帳號', findRichText: true), findsOneWidget);
  });
}
