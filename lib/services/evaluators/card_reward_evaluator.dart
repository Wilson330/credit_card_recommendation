import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';

abstract class CardRewardEvaluator<TProfile> {
  RewardEvaluationResult evaluate({
    required TProfile profile,
    required MerchantQueryContext merchantContext,
  });
}