import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:my_first_app/constants/popular_merchants.dart';
import 'package:my_first_app/models/card_profiles/cube_card_profile.dart';
import 'package:my_first_app/models/user_card_bundle.dart';
import 'package:my_first_app/models/wallet_card.dart';
import 'package:my_first_app/pages/home_page.dart';
import 'package:my_first_app/pages/result_page.dart';
import 'package:my_first_app/services/reward_rules_repository.dart';
import 'package:my_first_app/state/search_history_store.dart';
import 'package:my_first_app/state/user_cards_store.dart';

Future<void> _pumpHomePageWithOneCard(WidgetTester tester) async {
  await tester.runAsync(() => RewardRulesRepository.instance.load());

  final userCardsStore = UserCardsStore()
    ..addCard(
      const UserCardBundle(
        walletCard: WalletCard(
          id: 'w1',
          cardId: 'cathay_cube',
          bankName: '國泰世華',
          cardName: 'CUBE Card',
          network: 'Visa',
        ),
        profile: CubeCardProfile(
          selectedLevel: 'level_1',
          selectedRights: 'daily_select',
          isNewCardHolder: false,
        ),
      ),
    );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserCardsStore>.value(value: userCardsStore),
        ChangeNotifierProvider(create: (_) => SearchHistoryStore()),
      ],
      child: const MaterialApp(home: HomePage()),
    ),
  );
}

void main() {
  testWidgets('tapping the empty search field shows the 熱門商家 section', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('熱門商家'), findsOneWidget);
    expect(find.text(PopularMerchants.suggestions.first), findsOneWidget);
  });

  testWidgets('tapping a popular merchant navigates to ResultPage', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.tap(find.text(PopularMerchants.suggestions.first));
    await tester.pumpAndSettle();

    expect(find.byType(ResultPage), findsOneWidget);
  });

  testWidgets('a completed search is recorded and shows up as 歷史查詢 next time', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text(PopularMerchants.suggestions.first));
    await tester.pumpAndSettle();

    // back to HomePage
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('歷史查詢'), findsOneWidget);
    expect(find.text(PopularMerchants.suggestions.first), findsWidgets);
  });
}
