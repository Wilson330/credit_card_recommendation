import Foundation

/// Normalization shared by RuleMatcher (rule.matchValue comparisons) and
/// MerchantResolver (merchants.json canonicalName/aliases comparisons).
/// Mirrors lib/services/merchant_matcher.dart exactly — trim, lowercase,
/// strip ALL whitespace (not just leading/trailing).
public enum MerchantMatcher {
    public static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return lowered.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    /// A rule's matchValue is always Allen's raw crawled name — an alias
    /// like "小七" or "KFC" alone will never equal or substring-match it,
    /// only the resolved canonical name will. Evaluators pass both as
    /// candidates to RuleMatcher so an alias can still find the real
    /// merchant-type rule.
    public static func normalizedCandidates(
        _ merchantName: String,
        _ resolvedCanonicalName: String?
    ) -> [String] {
        var candidates: Set<String> = [normalize(merchantName)]
        if let resolved = resolvedCanonicalName {
            candidates.insert(normalize(resolved))
        }
        return Array(candidates)
    }
}
