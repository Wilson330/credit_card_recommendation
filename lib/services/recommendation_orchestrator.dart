import '../models/merchant_query_context.dart';
import '../models/reward_evaluation_result.dart';
import '../models/user_card_bundle.dart';
import 'evaluators/card_reward_evaluator.dart';
import 'evaluators/cube_reward_evaluator.dart';
import 'evaluators/jiho_reward_evaluator.dart';

class RecommendationOrchestrator {
  RecommendationOrchestrator({List<CardRewardEvaluator>? evaluators})
      : _evaluatorsByCardId = {
          for (final evaluator in evaluators ?? _defaultEvaluators)
            evaluator.cardId: evaluator,
        };

  // The one place that needs to know about every supported card. Adding a
  // new card means adding its evaluator here — nowhere else in this file.
  static List<CardRewardEvaluator> get _defaultEvaluators => [
        CubeRewardEvaluator(),
        JihoRewardEvaluator(),
      ];

  final Map<String, CardRewardEvaluator> _evaluatorsByCardId;

  List<RewardEvaluationResult> evaluate({
    required MerchantQueryContext merchantContext,
    required List<UserCardBundle> userCards,
  }) {
    final results = <RewardEvaluationResult>[];

    for (final userCard in userCards) {
      final evaluator = _evaluatorsByCardId[userCard.walletCard.cardId];
      if (evaluator == null) continue; // no evaluator registered for this card yet

      results.add(
        evaluator.evaluate(
          profile: userCard.profile,
          merchantContext: merchantContext,
        ),
      );
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
