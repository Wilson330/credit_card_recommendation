import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:my_first_app/api/api_client.dart';
import 'package:my_first_app/api/models.dart';

ApiClient clientReturning(int status, Object body, {void Function(http.Request)? onRequest}) {
  return ApiClient(
    baseUrl: 'http://fake',
    httpClient: MockClient((r) async {
      onRequest?.call(r);
      // 跟 Flask 一樣不帶 charset
      return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  test('回應沒有標 charset 時,中文仍以 UTF-8 正確解碼', () async {
    final api = clientReturning(200, [{'merchant_id': 1, 'name': '鼎泰豐'}]);
    final result = await api.suggest('鼎');
    expect(result.single.name, '鼎泰豐');
  });

  test('送出的中文是 UTF-8,並帶上 token', () async {
    late http.Request sent;
    final api = clientReturning(200, {'merchant': null, 'merchant_found': false, 'message': 'x', 'results': []},
        onRequest: (r) => sent = r)
      ..token = 'abc';
    await api.recommendByQuery('鼎泰豐');
    expect(utf8.decode(sent.bodyBytes), '{"query":"鼎泰豐"}');
    expect(sent.headers['Authorization'], 'Bearer abc');
  });

  test('錯誤時拋出後端的訊息', () async {
    final api = clientReturning(400, {'error': 'CUBE卡 的 level 要是以下其中之一'});
    expect(
      () => api.saveCard('cathay_cube', {'level': 'level_1'}),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 400)
          .having((e) => e.message, 'message', contains('level'))),
    );
  });

  test('401 會通知登出;但登入失敗的 401 不會', () async {
    var loggedOut = 0;
    final api = clientReturning(401, {'error': '帳號或密碼錯誤'})..onUnauthorized = () => loggedOut++;

    await expectLater(api.login('a@b.c', 'x'), throwsA(isA<ApiException>()));
    expect(loggedOut, 0);
    await expectLater(api.myCards(), throwsA(isA<ApiException>()));
    expect(loggedOut, 1);
  });

  test('連不到伺服器時給看得懂的訊息', () async {
    final api = ApiClient(baseUrl: 'http://fake', httpClient: MockClient((_) => throw Exception('connection refused')));
    expect(() => api.myCards(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('連不到伺服器'))));
  });

  test('回應不是 JSON 時給看得懂的訊息', () async {
    final api = ApiClient(
        baseUrl: 'http://fake', httpClient: MockClient((_) async => http.Response('<html>502</html>', 502)));
    expect(() => api.myCards(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('格式不正確'))));
  });

  test('回饋率顯示不帶多餘的 0', () {
    CardRecommendation rec(double rate) => CardRecommendation(
        cardId: 'c', cardName: 'c', bankName: 'b', rewardRate: rate, schemeName: 's',
        isGeneral: false, requiredAction: null, notes: const []);
    expect(rec(3).rateText, '3');
    expect(rec(3.5).rateText, '3.5');
    expect(rec(0.3).rateText, '0.3');
    expect(rec(3.3).rateText, '3.3');
  });

  test('卡片設定摘要', () {
    final option = CardOption.fromJson({
      'card_id': 'esun_unicard', 'name': 'Unicard', 'bank': '玉山銀行', 'rate_by': 'plan',
      'options': ['簡單選', '任意選', 'UP選'],
      'toggles': [{'key': 'e_bill', 'label': '電子帳單'}, {'key': 'auto_debit', 'label': '自動扣繳'}],
      'pick_merchants_when': ['任意選'], 'max_chosen_merchants': 8,
    });
    const card = UserCard(cardId: 'esun_unicard', cardName: 'Unicard', config: {
      'plan': '任意選', 'e_bill': true, 'auto_debit': false, 'chosen_merchants': [1, 2],
    });
    expect(card.summary(option), '任意選 · 電子帳單 · 挑選 2 家');
    expect(option.defaultConfig(), {'plan': '簡單選', 'e_bill': false, 'auto_debit': false});
  });
}
