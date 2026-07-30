import '../models/merchant_query_context.dart';
import '../models/reward_evaluation_result.dart';
import '../models/user_card_bundle.dart';
import 'evaluators/cube_reward_evaluator.dart';
import 'evaluators/jiho_reward_evaluator.dart';

class RecommendationOrchestrator {
  final CubeRewardEvaluator _cubeRewardEvaluator;
  final JihoRewardEvaluator _jihoRewardEvaluator;

  RecommendationOrchestrator({
    CubeRewardEvaluator? cubeRewardEvaluator,
    JihoRewardEvaluator? jihoRewardEvaluator,
  })  : _cubeRewardEvaluator = cubeRewardEvaluator ?? CubeRewardEvaluator(),
        _jihoRewardEvaluator = jihoRewardEvaluator ?? JihoRewardEvaluator();

  List<RewardEvaluationResult> evaluate({
    required MerchantQueryContext merchantContext,
    required List<UserCardBundle> userCards,
  }) {
    final results = <RewardEvaluationResult>[];

    for (final userCard in userCards) {
      final cardId = userCard.walletCard.cardId;

      if (cardId == 'cathay_cube' && userCard.cubeProfile != null) {
        results.add(
          _cubeRewardEvaluator.evaluate(
            profile: userCard.cubeProfile!,
            merchantContext: merchantContext,
          ),
        );
      }

      if (cardId == 'ubot_jiho' && userCard.jihoProfile != null) {
        results.add(
          _jihoRewardEvaluator.evaluate(
            profile: userCard.jihoProfile!,
            merchantContext: merchantContext,
          ),
        );
      }
    }

    results.sort((a, b) {
      final rateCompare = b.rewardRate.compareTo(a.rewardRate);
      if (rateCompare != 0) return rateCompare;

      final tagCompare = b.matchedTags.length.compareTo(a.matchedTags.length);
      if (tagCompare != 0) return tagCompare;

      return a.cardName.compareTo(b.cardName);
    });

    return results.take(3).toList();
  }
}