/// Normalization shared by RuleMatcher (rule.match_value comparisons) and
/// MerchantResolver (merchants.json canonical_name/aliases comparisons).
class MerchantMatcher {
  static String normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// Rules' match_value is always Allen's raw crawled name — an alias
  /// like "小七" or "KFC" alone will never equal or substring-match it,
  /// only the resolved canonical name will. Evaluators pass both as
  /// candidates to RuleMatcher so an alias can still find the real
  /// merchant-type rule.
  static List<String> normalizedCandidates(
    String merchantName,
    String? resolvedCanonicalName,
  ) {
    final candidates = <String>{normalize(merchantName)};
    if (resolvedCanonicalName != null) {
      candidates.add(normalize(resolvedCanonicalName));
    }
    return candidates.toList();
  }
}
