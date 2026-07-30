import '../models/card_reward_rule.dart';
import 'merchant_matcher.dart';

/// Picks the best-matching [CardRewardRule] for a query, following the
/// fixed lookup order agreed for v1: merchant > category > default.
/// If multiple merchant/category rules match at once (e.g. the same
/// merchant appears under two benefit schemes), the highest reward_rate
/// wins — this is also how a merchant with multiple category tags
/// (see SCHEMA.md) gets resolved.
class RuleMatcher {
  static CardRewardRule selectBestRule({
    required List<CardRewardRule> rules,
    required String normalizedQuery,
    required List<String> merchantTags,
    String? currentLevel,
  }) {
    final applicable = rules.where(
      (r) =>
          r.active &&
          (r.applicableLevel == null || r.applicableLevel == currentLevel),
    );

    final candidates = applicable.where((r) {
      if (r.ruleType == 'merchant') {
        return MerchantMatcher.normalize(r.matchValue) == normalizedQuery;
      }
      if (r.ruleType == 'category') {
        return merchantTags.contains(r.matchValue);
      }
      return false;
    });

    CardRewardRule? best;
    for (final rule in candidates) {
      if (best == null || rule.rewardRate > best.rewardRate) {
        best = rule;
      }
    }

    return best ?? applicable.firstWhere((r) => r.ruleType == 'default');
  }
}
