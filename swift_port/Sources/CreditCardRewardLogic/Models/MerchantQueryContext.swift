import Foundation

/// Mirrors lib/models/merchant_query_context.dart. Built once per search by
/// RecommendationOrchestrator.evaluate(_:userCards:) after resolving the
/// typed text via MerchantResolver — you shouldn't normally need to
/// construct this yourself unless calling an evaluator directly.
public struct MerchantQueryContext {
    public let merchantName: String
    public let merchantTags: [String]
    /// The canonical merchant name resolved via MerchantResolver, if any
    /// (e.g. merchantName="KFC" -> resolvedCanonicalName="肯德基"). A
    /// rule's matchValue is always the raw crawled name, which an alias
    /// alone will never equal/substring-match — RuleMatcher checks both
    /// merchantName and this field so an alias can still find the real
    /// merchant-type rule, not just fall through to category/default.
    public let resolvedCanonicalName: String?

    public init(
        merchantName: String,
        merchantTags: [String] = [],
        resolvedCanonicalName: String? = nil
    ) {
        self.merchantName = merchantName
        self.merchantTags = merchantTags
        self.resolvedCanonicalName = resolvedCanonicalName
    }
}
