import '../../models/card_profiles/card_profile.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';

/// Implementations register under [cardId] in RecommendationOrchestrator's
/// registry. [profile]'s runtime type must match what that specific card
/// expects (e.g. CubeRewardEvaluator expects a CubeCardProfile) — the
/// registry only ever calls an evaluator for a UserCardBundle whose
/// walletCard.cardId matches, so this invariant holds by construction.
abstract class CardRewardEvaluator {
  String get cardId;

  RewardEvaluationResult evaluate({
    required CardProfile profile,
    required MerchantQueryContext merchantContext,
  });
}
