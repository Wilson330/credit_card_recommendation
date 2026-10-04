import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';

enum SessionStatus { restoring, loggedOut, loggedIn }

/// 登入狀態。token 與使用者資料存在手機上,下次開 App 直接沿用;
/// 後端回 401(token 過期或無效)時自動登出,回到登入畫面。
class SessionStore extends ChangeNotifier {
  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';

  final ApiClient _api;
  SessionStatus _status = SessionStatus.restoring;
  LoggedInUser? _user;

  SessionStore(this._api) {
    _api.onUnauthorized = logout;
  }

  SessionStatus get status => _status;
  LoggedInUser? get user => _user;
  bool get isLoggedIn => _status == SessionStatus.loggedIn;

  /// App 啟動時呼叫:有存 token 就直接進入登入狀態。
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (token != null && userJson != null) {
      _api.token = token;
      _user = LoggedInUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      _status = SessionStatus.loggedIn;
    } else {
      _status = SessionStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final (token, user) = await _api.login(email.trim(), password);
    _api.token = token;
    _user = user;
    _status = SessionStatus.loggedIn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  /// 註冊成功後直接登入。
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String birthday,
  }) async {
    await _api.register(email: email.trim(), password: password, fullName: fullName.trim(), birthday: birthday);
    await login(email, password);
  }

  Future<void> logout() async {
    if (_status == SessionStatus.loggedOut) return;
    _api.token = null;
    _user = null;
    _status = SessionStatus.loggedOut;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }
}
