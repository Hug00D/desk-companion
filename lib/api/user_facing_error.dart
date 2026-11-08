import 'dart:async';
import 'dart:io';

import 'api_client.dart';

String userFacingError(Object error) {
  if (error is TimeoutException) return '連線逾時，請確認網路與服務後重試。';
  if (error is SocketException || error is HttpException) {
    return '無法連線，請確認網路與服務是否已啟動。';
  }
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return '目前帳號無法存取資料，請重新登入後再試。';
    }
    if (error.statusCode >= 500) return '服務暫時無法使用，請稍後重試。';
    return error.message;
  }
  if (error is FormatException) return '服務回傳的資料不完整，請重試。';
  return '操作未完成，請確認連線後重試。';
}
