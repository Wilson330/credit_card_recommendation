import 'package:flutter/foundation.dart';

/// 後端網址。
///
/// 可以在執行時覆蓋:flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.10:5000
/// 沒指定時:
///   - Chrome / Windows / iOS 模擬器:http://127.0.0.1:5000(後端跑在同一台電腦)
///   - Android 模擬器:http://10.0.2.2:5000(模擬器裡的 127.0.0.1 是模擬器自己)
String resolveApiBaseUrl() {
  const fromDefine = String.fromEnvironment('API_BASE_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:5000';
  }
  return 'http://127.0.0.1:5000';
}
