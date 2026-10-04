import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_first_app/pages/home_page.dart';
import 'package:my_first_app/pages/login_page.dart';
import 'package:my_first_app/pages/register_page.dart';

import 'support/fake_backend.dart';

void main() {
  testWidgets('沒登入過時顯示登入畫面', (tester) async {
    await pumpApp(tester);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('前往註冊'), findsOneWidget);
  });

  testWidgets('登入失敗顯示後端的訊息,不會進入首頁', (tester) async {
    await pumpApp(tester);
    await tester.enterText(textField('name@example.com'), demoEmail);
    await tester.enterText(textField('密碼'), 'wrong-password');
    await tester.tap(find.widgetWithText(CupertinoButton, '登入'));
    await tester.pumpAndSettle();

    expect(find.text('帳號或密碼錯誤'), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('登入成功進入首頁,並把 token 存在手機上', (tester) async {
    await pumpApp(tester);
    await tester.enterText(textField('name@example.com'), demoEmail);
    await tester.enterText(textField('密碼'), demoPassword);
    await tester.tap(find.widgetWithText(CupertinoButton, '登入'));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('嗨,測試用戶'), findsOneWidget);
    expect(find.text('尚未設定卡片'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_token'), 'fake-token');
  });

  testWidgets('上次登入過就直接進首頁', (tester) async {
    await pumpApp(tester, loggedIn: true);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('註冊後直接登入', (tester) async {
    final backend = await pumpApp(tester);
    await tester.tap(find.text('前往註冊'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsOneWidget);

    await tester.enterText(textField('name@example.com'), 'new@local.test');
    await tester.enterText(textField('至少 8 個字元'), 'new-password');
    await tester.enterText(textField('姓名'), '新使用者');
    await tester.tap(find.text('選擇日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('註冊並登入'));
    await tester.pumpAndSettle();

    expect(backend.users['new@local.test'], 'new-password');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('註冊時密碼太短,前端先擋下', (tester) async {
    final backend = await pumpApp(tester);
    await tester.tap(find.text('前往註冊'));
    await tester.pumpAndSettle();
    await tester.enterText(textField('name@example.com'), 'new@local.test');
    await tester.enterText(textField('至少 8 個字元'), 'short');
    await tester.enterText(textField('姓名'), '新使用者');
    await tester.tap(find.text('選擇日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('註冊並登入'));
    await tester.pumpAndSettle();

    expect(find.text('密碼至少要 8 個字元'), findsOneWidget);
    expect(backend.users.containsKey('new@local.test'), isFalse);
  });

  testWidgets('token 過期時,從深層頁面直接回到登入畫面,不另外跳錯誤', (tester) async {
    final backend = await pumpApp(tester, loggedIn: true);
    // 首頁 → 我的卡片 → 新增卡片 → CUBE 表單
    await tester.tap(find.text('設定我的卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUBE卡'));
    await tester.pumpAndSettle();

    backend.tokenExpired = true;
    await tester.tap(find.text('加入我的卡片'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('無法儲存'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_token'), isNull);
  });
}
