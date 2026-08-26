import Foundation

/// Resolves a user's typed merchant text to a canonical Merchant, so its
/// tags can feed RuleMatcher's category-type rules and its canonicalName
/// can feed merchant-type matching for aliases. Mirrors
/// lib/services/merchant_resolver.dart. Same two-tier philosophy as
/// RuleMatcher: exact match (checked against canonicalName AND every
/// alias) wins outright when present, conservative substring match
/// (>= minSafeMatchLength chars, either side contains the other) is only
/// a fallback.
public final class MerchantResolver {
    public static let shared = MerchantResolver()

    private static let minSafeMatchLength = 2

    private let repository: MerchantRepository

    public init(repository: MerchantRepository = .shared) {
        self.repository = repository
    }

    private func names(for merchant: Merchant) -> [String] {
        [merchant.canonicalName] + merchant.aliases
    }

    public func resolve(_ query: String) -> Merchant? {
        let normalizedQuery = MerchantMatcher.normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }

        let merchants = repository.all().filter { $0.active }

        for merchant in merchants {
            for name in names(for: merchant) {
                if MerchantMatcher.normalize(name) == normalizedQuery {
                    return merchant
                }
            }
        }

        guard normalizedQuery.count >= Self.minSafeMatchLength else { return nil }

        for merchant in merchants {
            for name in names(for: merchant) {
                let normalizedName = MerchantMatcher.normalize(name)
                guard normalizedName.count >= Self.minSafeMatchLength else { continue }
                if normalizedName.contains(normalizedQuery) || normalizedQuery.contains(normalizedName) {
                    return merchant
                }
            }
        }

        return nil
    }

    public func tags(for query: String) -> [String] {
        resolve(query)?.tags ?? []
    }
}
