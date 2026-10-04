// 用 App 的 ApiClient 打「真的」後端,確認欄位名稱與資料格式和 Flutter 端的解析一致。
// 其他測試用的是 test/support/fake_backend.dart 的假後端,這個測試補上真後端的對照。
//
// 預設略過。要執行時先啟動後端(python -m backend.app),再:
//   PowerShell:$env:API_INTEGRATION=1; flutter test test/api_integration_test.dart
// 測試帳號是 pytest-flutter-*@test.local,後端的 pytest 會一併清掉。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/api/api_client.dart';

void main() {
  final enabled = Platform.environment['API_INTEGRATION'] == '1';
  final baseUrl = Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:5000';

  test('ApiClient 與真後端的完整流程', () async {
    final api = ApiClient(baseUrl: baseUrl);
    final email = 'pytest-flutter-${DateTime.now().millisecondsSinceEpoch}@test.local';

    await api.register(email: email, password: 'flutter-pass', fullName: '整合測試', birthday: '1990-01-01');
    final (token, user) = await api.login(email, 'flutter-pass');
    api.token = token;
    expect(user.fullName, '整合測試');

    // 卡片選項
    final options = {for (final o in await api.cardOptions()) o.cardId: o};
    expect(options.keys, containsAll(['cathay_cube', 'esun_unicard', 'ubot_jiho']));
    expect(options['esun_unicard']!.pickMerchantsWhen, ['任意選']);
    expect(options['esun_unicard']!.maxChosenMerchants, 8);
    expect(options['ubot_jiho']!.toggles.single.label, '新戶自動扣繳');

    // 自動補全(含別名)
    expect((await api.suggest('小七')).first.name, '7-ELEVEN (7-11) 實體門市');
    final taipei101 = (await api.suggest('台北101')).first;
    expect(taipei101.name, '台北101');

    // 儲存卡片
    final cube = await api.saveCard('cathay_cube', {'level': 'Level 2'});
    expect(cube.config, {'level': 'Level 2', 'kids_club': false});
    final pickable = await api.pickableMerchants('esun_unicard');
    expect(pickable.map((m) => m.merchantId), contains(taipei101.merchantId));
    await api.saveCard('esun_unicard', {
      'plan': '任意選', 'e_bill': true, 'auto_debit': true, 'chosen_merchants': [taipei101.merchantId],
    });
    expect((await api.myCards()).map((c) => c.cardId), containsAll(['cathay_cube', 'esun_unicard']));

    // 不合法的設定由後端擋下
    await expectLater(
      api.saveCard('cathay_cube', {'level': 'level_1'}),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );

    // 推薦
    final byId = await api.recommendByMerchantId(taipei101.merchantId);
    expect(byId.merchantName, '台北101');
    final rates = {for (final r in byId.results) r.cardId: r};
    expect(rates['esun_unicard']!.rewardRate, 3.5);         // 任意選 2.5% + 一般消費 1%
    expect(rates['cathay_cube']!.rewardRate, 3.0);
    expect(rates['cathay_cube']!.requiredAction, '需切換至樂饗購權益方案');

    final notFound = await api.recommendByQuery('完全不存在的店家xyz');
    expect(notFound.merchantFound, isFalse);
    expect(notFound.message, '此店家不在回饋名單中,以一般消費計算');

    // 移除
    await api.deleteCard('esun_unicard');
    expect((await api.myCards()).map((c) => c.cardId), ['cathay_cube']);
  }, skip: enabled ? false : '設定 API_INTEGRATION=1 並啟動後端才會執行');
}
