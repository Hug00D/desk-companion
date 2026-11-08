import '../api/api_client.dart';
import '../api/user_facing_error.dart';

/// Login failures must describe the server's rejection, not expired sessions.
String authErrorMessage(ApiException error) {
  return switch (error.errorCode) {
    'INVALID_CREDENTIALS' => '電子郵件或密碼未通過驗證，請確認後再試。',
    'ACCOUNT_SUSPENDED' => '此帳號已停用，請聯絡專題團隊確認帳號狀態。',
    'ACCOUNT_DELETED' => '此帳號已刪除，請聯絡專題團隊確認帳號狀態。',
    'EMAIL_ALREADY_EXISTS' => '這個電子郵件已註冊，請切換至登入。',
    _ => error.statusCode >= 500 ? userFacingError(error) : error.message,
  };
}
