import '../models/card_reward_rule.dart';
import 'merchant_matcher.dart';

/// Picks the best-matching [CardRewardRule] for a query, following the
/// fixed lookup order agreed for v1: merchant > category > default.
///
/// Within "merchant", matching happens in two tiers, exact first:
///   1. exact match (after normalization) — always preferred when present,
///      never mixed with tier 2 candidates, so a lucky substring hit on an
///      unrelated merchant can't outrank a real exact match just because
///      its reward_rate happens to be higher.
///   2. conservative substring match (either side contains the other, both
///      at least [_minSafeMatchLength] chars) — this is what lets a user
///      typing "全家" find a rule whose match_value is the full raw crawled
///      name "全家便利商店 實體門市". This is still just a stand-in for real
///      alias-table matching (see SCHEMA.md); it only helps when the typed
///      text is a substring of the raw name or vice versa.
/// category rules are always tier 1 alongside an exact merchant hit — see
/// SCHEMA.md's "category 規則的比對邏輯" for the multi-tag design.
/// If multiple rules match within whichever tier fires, the highest
/// reward_rate wins.
class RuleMatcher {
  static const _minSafeMatchLength = 2;

  static CardRewardRule selectBestRule({
    required List<CardRewardRule> rules,
    required String normalizedQuery,
    required List<String> merchantTags,
    String? currentLevel,
  }) {
    final applicable = rules
        .where(
          (r) =>
              r.active &&
              (r.applicableLevel == null || r.applicableLevel == currentLevel),
        )
        .toList();

    final exactMerchantMatches = applicable.where(
      (r) =>
          r.ruleType == 'merchant' &&
          MerchantMatcher.normalize(r.matchValue) == normalizedQuery,
    );
    final categoryMatches = applicable.where(
      (r) => r.ruleType == 'category' && merchantTags.contains(r.matchValue),
    );

    final tier1 = [...exactMerchantMatches, ...categoryMatches];
    if (tier1.isNotEmpty) {
      return _highestRate(tier1);
    }

    final substringMatches = applicable.where((r) {
      if (r.ruleType != 'merchant') return false;

      final normalizedMatchValue = MerchantMatcher.normalize(r.matchValue);
      if (normalizedQuery.length < _minSafeMatchLength ||
          normalizedMatchValue.length < _minSafeMatchLength) {
        return false;
      }

      return normalizedMatchValue.contains(normalizedQuery) ||
          normalizedQuery.contains(normalizedMatchValue);
    });

    if (substringMatches.isNotEmpty) {
      return _highestRate(substringMatches);
    }

    return applicable.firstWhere((r) => r.ruleType == 'default');
  }

  static CardRewardRule _highestRate(Iterable<CardRewardRule> candidates) {
    CardRewardRule? best;
    for (final rule in candidates) {
      if (best == null || rule.rewardRate > best.rewardRate) {
        best = rule;
      }
    }
    return best!;
  }
}
