import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';
import 'package:my_first_app/services/reward_rules_repository.dart';

void main() {
  testWidgets('HomePage shows the empty state when no cards are added', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() => RewardRulesRepository.instance.load());
    await tester.pumpWidget(const MyApp());

    expect(find.text('尚未設定卡片'), findsOneWidget);
    expect(find.text('設定我的卡片'), findsWidgets);
  });
}
