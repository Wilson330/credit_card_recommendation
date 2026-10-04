import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/pages/card_form_page.dart';
import 'package:my_first_app/pages/home_page.dart';
import 'package:my_first_app/pages/my_cards_page.dart';
import 'package:my_first_app/pages/pick_merchants_page.dart';

import 'support/fake_backend.dart';

Future<void> openCardForm(WidgetTester tester, String cardName) async {
  await tester.tap(find.text('設定我的卡片'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('新增卡片'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(cardName));
  await tester.pumpAndSettle();
}

Map<String, dynamic> lastPutBody(FakeBackend backend) {
  final put = backend.requests.lastWhere((r) => r.method == 'PUT');
  return jsonDecode(utf8.decode(put.bodyBytes)) as Map<String, dynamic>;
}

void main() {
  testWidgets('新增卡片的清單來自後端,三張卡都在', (tester) async {
    await pumpApp(tester, loggedIn: true);
    await tester.tap(find.text('設定我的卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增卡片'));
    await tester.pumpAndSettle();

    expect(find.text('CUBE卡'), findsOneWidget);
    expect(find.text('Unicard'), findsOneWidget);
    expect(find.text('吉鶴卡'), findsOneWidget);
  });

  testWidgets('新增 CUBE:選 Level 2、開童樂匯,送出的 config 正確', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    await openCardForm(tester, 'CUBE卡');
    expect(find.text('權益等級'), findsOneWidget);

    await tester.tap(find.text('Level 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    expect(lastPutBody(backend), {'config': {'level': 'Level 2', 'kids_club': true}});
    expect(find.byType(MyCardsPage), findsOneWidget);
    expect(find.text('國泰世華 · Level 2 · 童樂匯'), findsOneWidget);
  });

  testWidgets('吉鶴卡沒有等級,只有「新戶自動扣繳」開關', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    await openCardForm(tester, '吉鶴卡');

    expect(find.text('權益等級'), findsNothing);
    expect(find.text('方案'), findsNothing);
    expect(find.text('新戶自動扣繳'), findsOneWidget);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    expect(lastPutBody(backend), {'config': {'new_customer': true}});
  });

  testWidgets('Unicard 選任意選才出現「挑選店家」,最多 8 家', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    await openCardForm(tester, 'Unicard');
    expect(find.text('挑選店家'), findsNothing);

    await tester.tap(find.text('任意選'));
    await tester.pumpAndSettle();
    expect(find.text('挑選店家'), findsOneWidget);
    expect(find.text('0 / 8'), findsOneWidget);

    await tester.tap(find.text('挑選店家'));
    await tester.pumpAndSettle();
    expect(find.byType(PickMerchantsPage), findsOneWidget);

    // 依序挑 8 家,第 9 家會被擋下
    for (final m in FakeBackend.merchants.take(8)) {
      await tester.tap(find.text(m['name'] as String));
      await tester.pumpAndSettle();
    }
    expect(find.text('挑選店家 8 / 8'), findsOneWidget);
    await tester.ensureVisible(find.text('台灣高鐵'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('台灣高鐵'));
    await tester.pumpAndSettle();
    expect(find.text('已達上限'), findsOneWidget);
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('8 / 8'), findsOneWidget);

    await tester.tap(find.byType(CupertinoSwitch).first);   // 電子帳單
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    final config = lastPutBody(backend)['config'] as Map<String, dynamic>;
    expect(config['plan'], '任意選');
    expect(config['e_bill'], true);
    expect(config['auto_debit'], false);
    expect((config['chosen_merchants'] as List).length, 8);
  });

  testWidgets('切回簡單選就不送 chosen_merchants', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    await openCardForm(tester, 'Unicard');
    await tester.tap(find.text('任意選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('簡單選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    expect((lastPutBody(backend)['config'] as Map).containsKey('chosen_merchants'), isFalse);
  });

  testWidgets('後端拒絕時顯示原因,停在表單,卡片不會加入', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    await openCardForm(tester, 'CUBE卡');
    backend.rejectSave = '設定不合法';
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    expect(find.text('無法儲存'), findsOneWidget);
    expect(find.text('設定不合法'), findsOneWidget);
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(find.byType(CardFormPage), findsOneWidget);
    expect(backend.cards, isEmpty);
  });

  testWidgets('登入時從後端載入卡片,首頁顯示張數', (tester) async {
    final backend = FakeBackend()
      ..cards['cathay_cube'] = {'level': 'Level 3', 'kids_club': false}
      ..cards['ubot_jiho'] = {'new_customer': false};
    await pumpApp(tester, loggedIn: true, backend: backend);

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('已設定 2 張卡片'), findsOneWidget);
  });

  testWidgets('編輯頁可以移除卡片', (tester) async {
    final backend = FakeBackend()..cards['ubot_jiho'] = {'new_customer': false};
    await pumpApp(tester, loggedIn: true, backend: backend);
    await tester.tap(find.text('管理我的卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('吉鶴卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除這張卡'));
    await tester.pumpAndSettle();

    expect(backend.cards, isEmpty);
    expect(find.text('目前還沒有加入任何卡片'), findsOneWidget);
  });
}
