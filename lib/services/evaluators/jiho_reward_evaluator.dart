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

    final activeConditions = <String>{
      if (profile.isNewCardHolder) 'new_customer',
    };

    final rule = RuleMatcher.selectBestRule(
      rules: _rules,
      normalizedQueries: MerchantMatcher.normalizedCandidates(
        merchantContext.merchantName,
        merchantContext.resolvedCanonicalName,
      ),
      merchantTags: merchantContext.merchantTags,
      currentLevel: null,
      activeConditions: activeConditions,
    );

    final matchedTags = <String>[rule.benefitLabel];
    if (profile.isNewCardHolder) {
      // Only the 國內一般消費 new-customer bump (a plain default-rate
      // condition) is actually reflected in rewardRate now. The Japan
      // new-customer rows (新戶日本實體消費 etc.) also require knowing
      // payment method / being physically in Japan — inputs no search
      // bar collects yet — so those stay is_synthetic_condition and
      // unreachable regardless of this flag. See SCHEMA.md.
      matchedTags.add('新戶身份已套用（僅國內一般消費，日本相關新戶加碼待補輸入欄位）');
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
