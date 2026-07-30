import 'package:flutter/cupertino.dart';
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

/// tester.tap() sends pointer down+up back-to-back with no pump() between
/// them, which does NOT reproduce the real "tap on a suggestion unfocuses
/// the field and hides the panel out from under the tap" bug — on a real
/// device there's always at least one frame between down and up, giving
/// EditableText's onTapOutside-triggered unfocus a chance to remove the
/// widget before the up event arrives. This helper simulates that timing.
Future<void> _realisticTap(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

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
      child: const CupertinoApp(home: HomePage()),
    ),
  );
}

void main() {
  testWidgets('tapping the empty search field shows the 熱門商家 section', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();

    expect(find.text('熱門商家'), findsOneWidget);
    expect(find.text(PopularMerchants.suggestions.first), findsOneWidget);
  });

  testWidgets('tapping a popular merchant navigates to ResultPage', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();

    await _realisticTap(tester, find.text(PopularMerchants.suggestions.first));

    expect(find.byType(ResultPage), findsOneWidget);
  });

  testWidgets('a completed search is recorded and shows up as 歷史查詢 next time', (tester) async {
    await _pumpHomePageWithOneCard(tester);

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    await _realisticTap(tester, find.text(PopularMerchants.suggestions.first));

    // back to HomePage
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();

    expect(find.text('歷史查詢'), findsOneWidget);
    expect(find.text(PopularMerchants.suggestions.first), findsWidgets);
  });
}
