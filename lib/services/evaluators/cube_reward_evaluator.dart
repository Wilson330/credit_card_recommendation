import '../../models/card_profiles/card_profile.dart';
import '../../models/card_profiles/cube_card_profile.dart';
import '../../models/card_reward_rule.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';
import '../merchant_matcher.dart';
import '../reward_rules_repository.dart';
import '../rule_matcher.dart';
import 'card_reward_evaluator.dart';

class CubeRewardEvaluator implements CardRewardEvaluator {
  CubeRewardEvaluator({List<CardRewardRule>? rules})
      : _rules = rules ?? RewardRulesRepository.instance.rulesFor('cathay_cube');

  final List<CardRewardRule> _rules;

  @override
  String get cardId => 'cathay_cube';

  @override
  RewardEvaluationResult evaluate({
    required CardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    if (profile is! CubeCardProfile) {
      throw ArgumentError(
        'CubeRewardEvaluator requires a CubeCardProfile, got ${profile.runtimeType}',
      );
    }

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
      cardId: cardId,
      cardName: 'CUBE Card',
      rewardRate: rule.rewardRate,
      matchedTags: matchedTags,
      requiredAction: rule.requiredAction,
      constraints: rule.constraints,
    );
  }
}
