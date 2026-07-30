import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/card_profiles/cube_card_profile.dart';
import 'package:my_first_app/models/card_profiles/jiho_card_profile.dart';
import 'package:my_first_app/models/merchant_query_context.dart';
import 'package:my_first_app/services/evaluators/cube_reward_evaluator.dart';
import 'package:my_first_app/services/evaluators/jiho_reward_evaluator.dart';
import 'package:my_first_app/services/reward_rules_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RewardRulesRepository.instance.load();
  });

  group('CubeRewardEvaluator against real cube_reward_rules.json', () {
    test('matches a named merchant under 台塑家 (level-invariant)', () {
      final result = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_1',
          isNewCardHolder: false,
        ),
        merchantContext: const MerchantQueryContext(merchantName: '台塑石油加油站'),
      );

      expect(result.rewardRate, 2.0);
      expect(result.matchedTags, contains('台塑家'));
    });

    test('same merchant yields a different rate at a different level', () {
      final query = const MerchantQueryContext(merchantName: '誠品生活');

      final level1 = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_1',
          isNewCardHolder: false,
        ),
        merchantContext: query,
      );
      final level3 = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_3',
          isNewCardHolder: false,
        ),
        merchantContext: query,
      );

      expect(level1.rewardRate, 2.0);
      expect(level3.rewardRate, 3.3);
      expect(level3.requiredAction, '需切換至樂饗購權益方案');
    });

    test('falls back to the default rule for an unknown merchant', () {
      final result = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_1',
          isNewCardHolder: false,
        ),
        merchantContext: const MerchantQueryContext(merchantName: '完全沒聽過的店'),
      );

      expect(result.rewardRate, 0.3);
      expect(result.matchedTags, contains('一般消費'));
    });

    test('a short substring of the real crawled name still matches (誠品 → 誠品生活)', () {
      final result = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_1',
          isNewCardHolder: false,
        ),
        merchantContext: const MerchantQueryContext(merchantName: '誠品'),
      );

      expect(result.rewardRate, 2.0);
      expect(result.matchedTags, contains('樂饗購'));
    });

    test('substring match picks among multiple real hits (全家 → 台塑家/集精選, same rate)', () {
      // "全家便利商店 實體門市" is listed under both 台塑家 (no required
      // action) and 集精選 (requires switching) at the same 2.0% rate —
      // this just confirms the substring path doesn't crash or pick
      // something unrelated when there's a genuine tie in the real data.
      final result = CubeRewardEvaluator().evaluate(
        profile: const CubeCardProfile(
          selectedLevel: 'level_1',
          isNewCardHolder: false,
        ),
        merchantContext: const MerchantQueryContext(merchantName: '全家'),
      );

      expect(result.rewardRate, 2.0);
      expect(['台塑家', '集精選'], contains(result.matchedTags.first));
    });
  });

  group('JihoRewardEvaluator against real jiho_reward_rules.json', () {
    test('matches a named merchant under 國內日系特店加碼', () {
      final result = JihoRewardEvaluator().evaluate(
        profile: const JihoCardProfile(isNewCardHolder: false),
        merchantContext: const MerchantQueryContext(merchantName: 'UNIQLO'),
      );

      expect(result.rewardRate, 5.5);
      expect(result.matchedTags, contains('國內日系特店加碼'));
    });

    test('falls back to the default rule for an unknown merchant', () {
      final result = JihoRewardEvaluator().evaluate(
        profile: const JihoCardProfile(isNewCardHolder: false),
        merchantContext: const MerchantQueryContext(merchantName: '完全沒聽過的店'),
      );

      expect(result.rewardRate, 1.0);
    });
  });
}
