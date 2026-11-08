import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/auth/auth_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid credentials are not described as an expired session', () {
    final message = authErrorMessage(
      ApiException(
        statusCode: 401,
        errorCode: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password.',
      ),
    );
    expect(message, contains('電子郵件或密碼'));
    expect(message, isNot(contains('重新登入')));
  });

  test('unknown auth rejection retains the server explanation', () {
    expect(
      authErrorMessage(ApiException(statusCode: 403, message: '此服務目前未開放登入')),
      '此服務目前未開放登入',
    );
  });

  test('account status failures remain distinct', () {
    expect(
      authErrorMessage(
        ApiException(
          statusCode: 403,
          errorCode: 'ACCOUNT_SUSPENDED',
          message: 'suspended',
        ),
      ),
      contains('已停用'),
    );
    expect(
      authErrorMessage(
        ApiException(
          statusCode: 403,
          errorCode: 'ACCOUNT_DELETED',
          message: 'deleted',
        ),
      ),
      contains('已刪除'),
    );
  });
}
