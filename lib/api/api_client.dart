import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 呼叫後端失敗。[message] 是後端回的 {"error": ...},可以直接顯示給使用者。
class ApiException implements Exception {
  final int status;
  final String message;

  const ApiException(this.status, this.message);

  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status): $message';
}

/// 後端 API 的呼叫(對應 backend/README.md 的 API 一覽)。
///
/// 統一處理:token、UTF-8 編碼、錯誤訊息。Flask 回應的 Content-Type 沒有標 charset,
/// http 套件預設會用 latin1 解碼,所以一律自己用 UTF-8 解碼 bodyBytes。
class ApiClient {
  final String baseUrl;
  final http.Client _http;

  /// 登入後由 SessionStore 設定。
  String? token;

  /// token 過期或無效(401)時呼叫,用來把使用者送回登入畫面。
  void Function()? onUnauthorized;

  ApiClient({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 15);

  // ---- 帳號 ----

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String birthday,
  }) async {
    await _send('POST', '/api/register', body: {
      'email': email,
      'password': password,
      'full_name': fullName,
      'birthday': birthday,
    });
  }

  /// 回傳 (token, 使用者資料)。
  Future<(String, LoggedInUser)> login(String email, String password) async {
    final data = await _send('POST', '/api/login', body: {'email': email, 'password': password}) as Map;
    return (data['token'] as String, LoggedInUser.fromJson(Map<String, dynamic>.from(data['user'] as Map)));
  }

  // ---- 卡片 ----

  Future<List<CardOption>> cardOptions() async {
    final data = await _send('GET', '/api/cards') as List;
    return [for (final c in data) CardOption.fromJson(Map<String, dynamic>.from(c as Map))];
  }

  Future<List<MerchantSuggestion>> pickableMerchants(String cardId) async {
    final data = await _send('GET', '/api/cards/$cardId/pickable_merchants') as List;
    return [for (final m in data) MerchantSuggestion.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  Future<List<UserCard>> myCards() async {
    final data = await _send('GET', '/api/user/cards') as List;
    return [for (final c in data) UserCard.fromJson(Map<String, dynamic>.from(c as Map))];
  }

  /// 新增或更新一張卡,回傳後端整理過的設定。
  Future<UserCard> saveCard(String cardId, Map<String, dynamic> config) async {
    final data = await _send('PUT', '/api/user/cards/$cardId', body: {'config': config}) as Map;
    return UserCard.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteCard(String cardId) async {
    await _send('DELETE', '/api/user/cards/$cardId');
  }

  // ---- 搜尋與推薦 ----

  Future<List<MerchantSuggestion>> suggest(String query) async {
    final data = await _send('GET', '/api/merchants/suggest', query: {'q': query}) as List;
    return [for (final m in data) MerchantSuggestion.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  Future<Recommendation> recommendByMerchantId(int merchantId) async =>
      Recommendation.fromJson(Map<String, dynamic>.from(
          await _send('POST', '/api/recommend', body: {'merchant_id': merchantId}) as Map));

  Future<Recommendation> recommendByQuery(String query) async =>
      Recommendation.fromJson(Map<String, dynamic>.from(
          await _send('POST', '/api/recommend', body: {'query': query}) as Map));

  // ---- 共用 ----

  Future<Object?> _send(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json; charset=utf-8';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.bodyBytes = utf8.encode(jsonEncode(body));

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const ApiException(0, '伺服器沒有回應,請稍後再試');
    } catch (_) {
      throw const ApiException(0, '連不到伺服器,請確認後端有啟動');
    }

    final Object? data;
    try {
      final text = utf8.decode(response.bodyBytes);
      data = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw ApiException(response.statusCode, '伺服器回應格式不正確(${response.statusCode})');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    final message = data is Map && data['error'] is String ? data['error'] as String : '發生錯誤(${response.statusCode})';
    final error = ApiException(response.statusCode, message);
    // 登入、註冊本身回 401 是「帳號或密碼錯誤」,不是登入狀態失效
    if (error.isUnauthorized && path != '/api/login' && path != '/api/register') {
      onUnauthorized?.call();
    }
    throw error;
  }
}
