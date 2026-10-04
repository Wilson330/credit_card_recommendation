import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_first_app/api/api_client.dart';
import 'package:my_first_app/main.dart';

const demoEmail = 'demo@local.test';
const demoPassword = 'demo-password';
const _token = 'fake-token';

/// 模擬後端:回應格式與 backend/app.py 相同,資料放在記憶體裡。
/// 回應的 Content-Type 刻意不帶 charset(跟 Flask 一樣),用來確認 App 用 UTF-8 解碼。
class FakeBackend {
  final requests = <http.Request>[];
  final users = <String, String>{demoEmail: demoPassword};
  final cards = <String, Map<String, dynamic>>{};

  /// 設成 true 時,所有需要登入的 API 都回 401(模擬 token 過期)。
  bool tokenExpired = false;

  /// 設定後,自動補全會等到 complete 才回應(模擬網路慢)。
  Completer<void>? suggestGate;

  /// 設定後,儲存卡片一律回 400 與這個訊息(模擬後端檢查不通過)。
  String? rejectSave;

  late final MockClient client = MockClient(_handle);

  ApiClient api() => ApiClient(baseUrl: 'http://fake', httpClient: client);

  List<String> get suggestQueries => [
        for (final r in requests)
          if (r.url.path == '/api/merchants/suggest') r.url.queryParameters['q']!,
      ];

  static const merchants = [
    {'merchant_id': 1, 'name': '鼎泰豐'},
    {'merchant_id': 2, 'name': '台北101'},
    {'merchant_id': 3, 'name': '7-ELEVEN (7-11) 實體門市'},
    {'merchant_id': 4, 'name': '全家便利商店 實體門市'},
    {'merchant_id': 5, 'name': 'UNIQLO'},
    {'merchant_id': 6, 'name': '誠品生活'},
    {'merchant_id': 7, 'name': '新光三越'},
    {'merchant_id': 8, 'name': '微風廣場'},
    {'merchant_id': 9, 'name': '遠東SOGO'},
    {'merchant_id': 10, 'name': '台灣高鐵'},
  ];
  static const _aliases = {'小七': 3, '全家': 4};

  static const cardOptions = [
    {
      'card_id': 'cathay_cube', 'name': 'CUBE卡', 'bank': '國泰世華', 'rate_by': 'level',
      'options': ['Level 1', 'Level 2', 'Level 3'],
      'toggles': [{'key': 'kids_club', 'label': '童樂匯'}],
      'pick_merchants_when': <String>[], 'max_chosen_merchants': null,
    },
    {
      'card_id': 'esun_unicard', 'name': 'Unicard', 'bank': '玉山銀行', 'rate_by': 'plan',
      'options': ['簡單選', '任意選', 'UP選'],
      'toggles': [{'key': 'e_bill', 'label': '電子帳單'}, {'key': 'auto_debit', 'label': '自動扣繳'}],
      'pick_merchants_when': ['任意選'], 'max_chosen_merchants': 8,
    },
    {
      'card_id': 'ubot_jiho', 'name': '吉鶴卡', 'bank': '聯邦銀行', 'rate_by': null,
      'options': <String>[],
      'toggles': [{'key': 'new_customer', 'label': '新戶自動扣繳'}],
      'pick_merchants_when': <String>[], 'max_chosen_merchants': null,
    },
  ];

  static String cardName(String cardId) =>
      cardOptions.firstWhere((c) => c['card_id'] == cardId)['name'] as String;

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

    if (path == '/api/login') {
      if (users[body!['email']] != body['password']) return _json(401, {'error': '帳號或密碼錯誤'});
      return _json(200, {
        'token': _token,
        'user': {'email': body['email'], 'full_name': '測試用戶', 'birthday': '1990-01-01'},
      });
    }
    if (path == '/api/register') {
      if (users.containsKey(body!['email'])) return _json(409, {'error': '這個 Email 已經被註冊過'});
      users[body['email'] as String] = body['password'] as String;
      return _json(201, {'message': '註冊成功', 'user_id': users.length});
    }

    if (tokenExpired || r.headers['Authorization'] != 'Bearer $_token') {
      return _json(401, {'error': '登入已過期,請重新登入'});
    }

    if (path == '/api/cards') return _json(200, cardOptions);
    if (path == '/api/cards/esun_unicard/pickable_merchants') return _json(200, merchants);
    if (path == '/api/user/cards' && r.method == 'GET') {
      return _json(200, [
        for (final e in cards.entries) {'card_id': e.key, 'card_name': cardName(e.key), 'config': e.value},
      ]);
    }
    if (path.startsWith('/api/user/cards/')) {
      final cardId = path.split('/').last;
      if (r.method == 'DELETE') {
        return cards.remove(cardId) == null ? _json(404, {'error': '你沒有這張卡'}) : _json(200, {'message': '已移除'});
      }
      final config = Map<String, dynamic>.from(body!['config'] as Map);
      if (rejectSave != null) return _json(400, {'error': rejectSave!});
      cards[cardId] = config;
      return _json(200, {'card_id': cardId, 'card_name': cardName(cardId), 'config': config});
    }
    if (path == '/api/merchants/suggest') {
      await suggestGate?.future;
      final q = r.url.queryParameters['q']!;
      return _json(200, [for (final m in merchants) if ((m['name'] as String).contains(q)) m]);
    }
    if (path == '/api/recommend') {
      final merchant = _resolve(body!);
      return _json(200, {
        'merchant': merchant == null ? null : {...merchant, 'category': 'dining', 'country': 'TW'},
        'merchant_found': merchant != null,
        'message': merchant == null ? '此店家不在回饋名單中,以一般消費計算' : null,
        'results': [
          if (cards.containsKey('cathay_cube'))
            {
              'card_id': 'cathay_cube', 'card_name': 'CUBE卡', 'bank_name': '國泰世華',
              'reward_rate': merchant == null ? 0.3 : 3.0,
              'scheme_name': merchant == null ? '一般消費' : '樂饗購',
              'is_general': merchant == null,
              'required_action': merchant == null ? null : '需切換至樂饗購權益方案',
              'notes': ['實際回饋依當期公告為準', if (merchant == null) '不含保費'],
            },
        ],
      });
    }
    return _json(404, {'error': '找不到這個 API'});
  }

  Map<String, Object>? _resolve(Map<String, dynamic> body) {
    if (body['merchant_id'] != null) {
      return merchants.firstWhere((m) => m['merchant_id'] == body['merchant_id']);
    }
    final q = body['query'] as String;
    final aliasId = _aliases[q];
    for (final m in merchants) {
      if (m['merchant_id'] == aliasId || m['name'] == q) return m;
    }
    return null;
  }

  static http.Response _json(int status, Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
}

/// 啟動整個 App。[loggedIn] 為 true 時模擬「上次登入過、手機上有存 token」。
Future<FakeBackend> pumpApp(WidgetTester tester, {bool loggedIn = false, FakeBackend? backend}) async {
  final fake = backend ?? FakeBackend();
  SharedPreferences.setMockInitialValues(loggedIn
      ? {
          'session_token': _token,
          'session_user': jsonEncode({'email': demoEmail, 'full_name': '測試用戶', 'birthday': '1990-01-01'}),
        }
      : {});
  await tester.pumpWidget(MyApp(api: fake.api()));
  await tester.pumpAndSettle();
  return fake;
}

/// tester.tap() 會在同一個 frame 送出按下與放開,重現不了「點建議時輸入框先失焦、
/// 建議清單被收掉」的真實情況;這個 helper 在按下與放開之間多跑一個 frame。
Future<void> realisticTap(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder textField(String placeholder) => find.byWidgetPredicate(
      (w) => w is CupertinoTextField && w.placeholder == placeholder,
    );
