import '../../models/card_profiles/card_profile.dart';
import '../../models/card_profiles/jiho_card_profile.dart';
import '../../models/card_reward_rule.dart';
import '../../models/merchant_query_context.dart';
import '../../models/reward_evaluation_result.dart';
import '../merchant_matcher.dart';
import '../reward_rules_repository.dart';
import '../rule_matcher.dart';
import 'card_reward_evaluator.dart';

class JihoRewardEvaluator implements CardRewardEvaluator {
  JihoRewardEvaluator({List<CardRewardRule>? rules})
      : _rules = rules ?? RewardRulesRepository.instance.rulesFor('ubot_jiho');

  final List<CardRewardRule> _rules;

  @override
  String get cardId => 'ubot_jiho';

  @override
  RewardEvaluationResult evaluate({
    required CardProfile profile,
    required MerchantQueryContext merchantContext,
  }) {
    if (profile is! JihoCardProfile) {
      throw ArgumentError(
        'JihoRewardEvaluator requires a JihoCardProfile, got ${profile.runtimeType}',
      );
    }

    final normalizedQuery = MerchantMatcher.normalize(merchantContext.merchantName);

    final rule = RuleMatcher.selectBestRule(
      rules: _rules,
      normalizedQuery: normalizedQuery,
      merchantTags: merchantContext.merchantTags,
      currentLevel: null,
    );

    final matchedTags = <String>[rule.benefitLabel];
    if (profile.isNewCardHolder) {
      // Real new-customer bonus rows exist in jiho_reward_rules.json
      // (is_synthetic_condition: true) but aren't reachable from a typed
      // merchant name — see SCHEMA.md. Tag only, doesn't affect rewardRate
      // yet; revisit once conditional rule matching is built.
      matchedTags.add('新戶身份（尚未反映在回饋率，待條件式規則支援）');
    }

    return RewardEvaluationResult(
      cardId: cardId,
      cardName: '吉鶴卡',
      rewardRate: rule.rewardRate,
      matchedTags: matchedTags,
      requiredAction: rule.requiredAction,
      constraints: rule.constraints,
    );
  }
}
