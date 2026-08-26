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
///      at least [_minSafeMatchLength] chars).
/// [normalizedQueries] can carry more than one string — typically the
/// user's raw typed text plus the resolved canonical merchant name (see
/// MerchantResolver) — because a rule's match_value is Allen's raw
/// crawled name, which an alias like "小七" or "KFC" won't ever equal or
/// substring-match on its own; only the canonical name will. Each tier
/// checks every candidate query and keeps the best result found across
/// all of them.
/// category rules are always tier 1 alongside an exact merchant hit — see
/// SCHEMA.md's "category 規則的比對邏輯" for the multi-tag design.
/// If multiple rules match within whichever tier fires, the highest
/// reward_rate wins — this also applies to 'default'-type rules now that
/// a card can have more than one (e.g. jiho's unconditional 1.0% plus a
/// new_customer-conditioned 1.5%): whichever qualifying default has the
/// highest rate is used, not just the first one found.
///
/// [activeConditions] is the set of eligibility flags the current card
/// profile satisfies (e.g. {'new_customer'}, {'kids_club'}). A rule whose
/// requiredConditions isn't fully contained in activeConditions is
/// excluded from the candidate pool entirely, same as applicableLevel.
class RuleMatcher {
  static const _minSafeMatchLength = 2;

  static CardRewardRule selectBestRule({
    required List<CardRewardRule> rules,
    required List<String> normalizedQueries,
    required List<String> merchantTags,
    String? currentLevel,
    Set<String> activeConditions = const {},
  }) {
    final applicable = rules
        .where(
          (r) =>
              r.active &&
              (r.applicableLevel == null || r.applicableLevel == currentLevel) &&
              r.requiredConditions.every(activeConditions.contains),
        )
        .toList();

    final exactMerchantMatches = applicable.where((r) {
      if (r.ruleType != 'merchant') return false;
      final normalizedMatchValue = MerchantMatcher.normalize(r.matchValue);
      return normalizedQueries.contains(normalizedMatchValue);
    });
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
      if (normalizedMatchValue.length < _minSafeMatchLength) return false;

      return normalizedQueries.any((query) {
        if (query.length < _minSafeMatchLength) return false;
        return normalizedMatchValue.contains(query) || query.contains(normalizedMatchValue);
      });
    });

    if (substringMatches.isNotEmpty) {
      return _highestRate(substringMatches);
    }

    final defaults = applicable.where((r) => r.ruleType == 'default');
    return _highestRate(defaults);
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
