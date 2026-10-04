import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/constants/popular_merchants.dart';
import 'package:my_first_app/pages/result_page.dart';

import 'support/fake_backend.dart';

final _search = textField('輸入商家名稱,例如:全家、Uber Eats、UNIQLO');

Future<FakeBackend> pumpWithCube(WidgetTester tester) {
  final backend = FakeBackend()..cards['cathay_cube'] = {'level': 'Level 2', 'kids_club': false};
  return pumpApp(tester, loggedIn: true, backend: backend);
}

Map<String, dynamic> lastRecommendBody(FakeBackend backend) {
  final r = backend.requests.lastWhere((r) => r.url.path == '/api/recommend');
  return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
}

/// 模擬輸入法送進來的文字;composing 不為空表示還在組字。
Future<void> typeWithIme(WidgetTester tester, String text, {TextRange composing = TextRange.empty}) async {
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
    composing: composing,
  ));
  await tester.pump();
}

void main() {
  testWidgets('點空白搜尋框顯示熱門商家', (tester) async {
    await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();

    expect(find.text('熱門商家'), findsOneWidget);
    expect(find.text(PopularMerchants.suggestions.first), findsOneWidget);
  });

  testWidgets('點熱門商家:用文字查推薦,進入結果頁', (tester) async {
    final backend = await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();
    await realisticTap(tester, find.text('全家'));

    expect(find.byType(ResultPage), findsOneWidget);
    expect(lastRecommendBody(backend), {'query': '全家'});
    // 用別名「全家」查,結果頁顯示店家正式名稱
    expect(find.text('全家便利商店 實體門市 推薦卡片'), findsOneWidget);
    expect(find.text('依「全家」找到這家店'), findsOneWidget);
    expect(find.text('需切換至樂饗購權益方案'), findsOneWidget);
  });

  testWidgets('查過的店下次出現在歷史查詢', (tester) async {
    await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();
    await realisticTap(tester, find.text('全家'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(_search);
    await tester.pumpAndSettle();
    expect(find.text('歷史查詢'), findsOneWidget);
  });

  testWidgets('打字出現後端的建議,點建議用店家編號查', (tester) async {
    final backend = await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.enterText(_search, '台北');
    await tester.pumpAndSettle();

    expect(find.text('台北101'), findsOneWidget);
    await realisticTap(tester, find.text('台北101'));

    expect(find.byType(ResultPage), findsOneWidget);
    expect(lastRecommendBody(backend), {'merchant_id': 2});
  });

  testWidgets('找不到店家時顯示提示與一般消費', (tester) async {
    await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.enterText(_search, '不存在的店');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('此店家不在回饋名單中,以一般消費計算'), findsOneWidget);
    expect(find.text('0.3%'), findsOneWidget);
    expect(find.text('一般消費(不需要切換方案)'), findsOneWidget);
    expect(find.text('不含保費'), findsOneWidget);
  });

  testWidgets('輸入法組字中不送查詢,選字完成才送', (tester) async {
    final backend = await pumpWithCube(tester);
    await tester.tap(_search);
    await tester.pumpAndSettle();

    await typeWithIme(tester, 'ㄉㄧㄥˇ', composing: const TextRange(start: 0, end: 4));
    expect(backend.suggestQueries, isEmpty);

    await typeWithIme(tester, '鼎');
    await tester.pumpAndSettle();
    expect(backend.suggestQueries, ['鼎']);
  });

  testWidgets('同時只送一個請求;回來後若文字變了,只補送最新的文字', (tester) async {
    final backend = await pumpWithCube(tester);
    final gate = backend.suggestGate = Completer<void>();
    await tester.tap(_search);
    await tester.pumpAndSettle();

    await typeWithIme(tester, '鼎');
    await typeWithIme(tester, '鼎泰');
    await typeWithIme(tester, '鼎泰豐');
    expect(backend.suggestQueries, ['鼎'], reason: '第一個請求還沒回來,不該再送');

    gate.complete();
    await tester.pumpAndSettle();
    expect(backend.suggestQueries, ['鼎', '鼎泰豐'], reason: '中間的「鼎泰」不該送');
    expect(find.text('鼎泰豐'), findsWidgets);
  });

  testWidgets('沒有卡片時不能查詢', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    expect(find.text('開始推薦'), findsNothing);
    await tester.tap(_search);
    await tester.enterText(_search, '鼎泰豐');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(ResultPage), findsNothing);
    expect(backend.requests.where((r) => r.url.path == '/api/recommend'), isEmpty);
  });
}
