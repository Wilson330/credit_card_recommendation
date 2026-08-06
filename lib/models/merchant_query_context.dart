class MerchantQueryContext {
  final String merchantName;
  final String? channel;
  final String? country;
  final List<String> merchantTags;
  final String? paymentMethod;

  /// The canonical merchant name resolved via MerchantResolver, if any
  /// (e.g. merchantName="KFC" -> resolvedCanonicalName="肯德基"). Rules'
  /// match_value is always Allen's raw crawled name, which an alias
  /// alone will never equal/substring-match — RuleMatcher checks both
  /// merchantName and this field so an alias can still find the real
  /// merchant-type rule, not just fall through to category/default.
  final String? resolvedCanonicalName;

  const MerchantQueryContext({
    required this.merchantName,
    this.channel,
    this.country,
    this.merchantTags = const [],
    this.paymentMethod,
    this.resolvedCanonicalName,
  });
}
