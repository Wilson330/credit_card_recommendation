/// v1 simplification: no canonical merchant/alias resolution yet (see
/// SCHEMA.md "已知簡化"). This currently only exposes the normalization
/// used to compare a user's typed merchant name against a rule's
/// match_value. Once merchant_id-based matching is built, this is where
/// the real alias lookup (merchants.json + merchants_aliases.json) goes.
class MerchantMatcher {
  static String normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }
}
