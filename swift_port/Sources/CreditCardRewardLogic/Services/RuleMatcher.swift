import Foundation

/// Ported from lib/services/rule_matcher.dart — see that file's doc
/// comment and SCHEMA.md for the full design rationale. Summary:
///
/// Picks the best-matching CardRewardRule for a query, following the
/// fixed lookup order: merchant > category > default.
///
/// Within "merchant", two tiers, exact first:
///   1. exact match (after normalization) — always preferred when
///      present, never mixed with tier 2, so a lucky substring hit on an
///      unrelated merchant can't outrank a real exact match just because
///      its rewardRate happens to be higher.
///   2. conservative substring match (either side contains the other,
///      both at least minSafeMatchLength chars).
/// normalizedQueries can carry more than one string — typically the
/// user's raw typed text plus the resolved canonical merchant name (see
/// MerchantResolver) — because a rule's matchValue is Allen's raw
/// crawled name, which an alias won't equal/substring-match on its own.
/// Each tier checks every candidate query and keeps the best result
/// found across all of them.
///
/// category rules are always tier 1 alongside an exact merchant hit.
/// If multiple rules match within whichever tier fires, the highest
/// rewardRate wins — this also applies to 'default'-type rules, since a
/// card can have more than one (e.g. jiho's unconditional 1.0% plus a
/// new_customer-conditioned 1.5%).
///
/// activeConditions is the set of eligibility flags the current card
/// profile satisfies (e.g. ["new_customer"], ["kids_club"]). A rule
/// whose requiredConditions isn't fully contained in activeConditions is
/// excluded from the candidate pool entirely, same as applicableLevel.
public enum RuleMatcher {
    private static let minSafeMatchLength = 2

    public static func selectBestRule(
        rules: [CardRewardRule],
        normalizedQueries: [String],
        merchantTags: [String],
        currentLevel: String? = nil,
        activeConditions: Set<String> = []
    ) -> CardRewardRule {
        let applicable = rules.filter { rule in
            rule.active
                && (rule.applicableLevel == nil || rule.applicableLevel == currentLevel)
                && rule.requiredConditions.allSatisfy { activeConditions.contains($0) }
        }

        let exactMerchantMatches = applicable.filter { rule in
            guard rule.ruleType == "merchant" else { return false }
            let normalizedMatchValue = MerchantMatcher.normalize(rule.matchValue)
            return normalizedQueries.contains(normalizedMatchValue)
        }
        let categoryMatches = applicable.filter { rule in
            rule.ruleType == "category" && merchantTags.contains(rule.matchValue)
        }

        let tier1 = exactMerchantMatches + categoryMatches
        if let best = highestRate(tier1) {
            return best
        }

        let substringMatches = applicable.filter { rule -> Bool in
            guard rule.ruleType == "merchant" else { return false }

            let normalizedMatchValue = MerchantMatcher.normalize(rule.matchValue)
            guard normalizedMatchValue.count >= minSafeMatchLength else { return false }

            return normalizedQueries.contains { query in
                guard query.count >= minSafeMatchLength else { return false }
                return normalizedMatchValue.contains(query) || query.contains(normalizedMatchValue)
            }
        }

        if let best = highestRate(substringMatches) {
            return best
        }

        let defaults = applicable.filter { $0.ruleType == "default" }
        guard let result = highestRate(defaults) else {
            preconditionFailure(
                "RuleMatcher.selectBestRule found no candidate at all — every card's reward-rule file must include at least one unconditional (required_conditions: []) rule_type: 'default' row. Check the JSON bundled for cardId \(rules.first?.cardId ?? "<empty rules array>")."
            )
        }
        return result
    }

    /// Mirrors the Dart version's manual loop exactly (first-seen wins
    /// ties) rather than relying on Array.max(by:)'s own tie-breaking
    /// behavior, so this stays byte-for-byte equivalent to the tested
    /// Dart reference regardless of stdlib differences.
    private static func highestRate(_ candidates: [CardRewardRule]) -> CardRewardRule? {
        var best: CardRewardRule?
        for rule in candidates {
            if best == nil || rule.rewardRate > best!.rewardRate {
                best = rule
            }
        }
        return best
    }
}
