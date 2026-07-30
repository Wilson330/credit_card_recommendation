import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/models/card_profiles/card_profile.dart';
import 'package:my_first_app/models/card_profiles/cube_card_profile.dart';
import 'package:my_first_app/models/card_profiles/jiho_card_profile.dart';
import 'package:my_first_app/models/merchant_query_context.dart';
import 'package:my_first_app/models/reward_evaluation_result.dart';
import 'package:my_first_app/models/user_card_bundle.dart';
import 'package:my_first_app/models/wallet_card.dart';
import 'package:my_first_app/services/evaluators/card_reward_evaluator.dart';
import 'package:my_first_app/services/recommendation_orchestrator.dart';

class _FakeThirdCardProfile extends CardProfile {
  const _FakeThirdCardProfile();
}

class _FakeThirdCardEvaluator implements CardRewardEvaluator {
  @override
  String get cardId => 'fake_third_card';

  @override
  RewardEvaluationResult evaluate({
    required CardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    return const RewardEvaluationResult(
      cardId: 'fake_third_card',
      cardName: 'Fake Third Card',
      rewardRate: 99.0,
      matchedTags: ['測試用假卡片'],
    );
  }
}

void main() {
  test('registering a brand-new evaluator does not require touching the orchestrator body', () {
    final orchestrator = RecommendationOrchestrator(
      evaluators: [_FakeThirdCardEvaluator()],
    );

    final results = orchestrator.evaluate(
      merchantContext: const MerchantQueryContext(merchantName: '任何商家'),
      userCards: [
        UserCardBundle(
          walletCard: const WalletCard(
            id: 'w1',
            cardId: 'fake_third_card',
            bankName: '測試銀行',
            cardName: 'Fake Third Card',
            network: 'Visa',
          ),
          profile: const _FakeThirdCardProfile(),
        ),
      ],
    );

    expect(results, hasLength(1));
    expect(results.single.rewardRate, 99.0);
  });

  test('a user card with no registered evaluator is silently skipped, not crashed', () {
    final orchestrator = RecommendationOrchestrator(evaluators: []);

    final results = orchestrator.evaluate(
      merchantContext: const MerchantQueryContext(merchantName: '任何商家'),
      userCards: [
        UserCardBundle(
          walletCard: const WalletCard(
            id: 'w1',
            cardId: 'cathay_cube',
            bankName: '國泰世華',
            cardName: 'CUBE Card',
            network: 'Visa',
          ),
          profile: const CubeCardProfile(
            selectedLevel: 'level_1',
            isNewCardHolder: false,
          ),
        ),
      ],
    );

    expect(results, isEmpty);
  });

  test('results are sorted by reward rate, highest first, across different cards', () {
    final orchestrator = RecommendationOrchestrator(
      evaluators: [_FakeThirdCardEvaluator()],
    );

    final results = orchestrator.evaluate(
      merchantContext: const MerchantQueryContext(merchantName: '任何商家'),
      userCards: [
        UserCardBundle(
          walletCard: const WalletCard(
            id: 'w1',
            cardId: 'fake_third_card',
            bankName: '測試銀行',
            cardName: 'Fake Third Card',
            network: 'Visa',
          ),
          profile: const _FakeThirdCardProfile(),
        ),
      ],
    );

    expect(results.first.cardId, 'fake_third_card');
  });

  test('a mismatched profile type throws instead of silently misreading fields', () {
    // A JihoCardProfile attached to a WalletCard whose cardId routes to the
    // real CUBE evaluator — this is a bug the registry can't catch by
    // itself, but CubeRewardEvaluator's own guard clause should still fail
    // loudly instead of silently reading the wrong fields.
    final orchestrator = RecommendationOrchestrator();

    expect(
      () => orchestrator.evaluate(
        merchantContext: const MerchantQueryContext(merchantName: '任何商家'),
        userCards: [
          UserCardBundle(
            walletCard: const WalletCard(
              id: 'w1',
              cardId: 'cathay_cube',
              bankName: '國泰世華',
              cardName: 'CUBE Card',
              network: 'Visa',
            ),
            profile: const JihoCardProfile(isNewCardHolder: false),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
