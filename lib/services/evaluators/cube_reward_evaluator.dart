import '../../models/card_profiles/cube_card_profile.dart';
import '../../models/card_reward_rule.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';
import '../merchant_matcher.dart';
import '../reward_rules_repository.dart';
import '../rule_matcher.dart';

class CubeRewardEvaluator {
  CubeRewardEvaluator({List<CardRewardRule>? rules})
      : _rules = rules ?? RewardRulesRepository.instance.rulesFor('cathay_cube');

  final List<CardRewardRule> _rules;

  RewardEvaluationResult evaluate({
    required CubeCardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    final normalizedQuery = MerchantMatcher.normalize(merchantContext.merchantName);

    final rule = RuleMatcher.selectBestRule(
      rules: _rules,
      normalizedQuery: normalizedQuery,
      merchantTags: merchantContext.merchantTags,
      currentLevel: profile.selectedLevel,
    );

    final matchedTags = <String>[rule.benefitLabel];
    if (profile.isNewCardHolder) {
      matchedTags.add('新戶身份已套用');
    }

    return RewardEvaluationResult(
      cardId: 'cathay_cube',
      cardName: 'CUBE Card',
      rewardRate: rule.rewardRate,
      matchedTags: matchedTags,
      requiredAction: rule.requiredAction,
      constraints: rule.constraints,
    );
  }
}
