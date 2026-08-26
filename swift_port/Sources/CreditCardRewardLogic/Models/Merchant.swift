import Foundation

/// Mirrors lib/models/merchant.dart — see SCHEMA.md "1. merchants" and
/// "2. merchant_aliases" for the field-by-field description.
public struct Merchant: Codable {
    public let merchantId: String
    public let canonicalName: String
    public let displayName: String
    public let primaryCategory: String
    public let subcategory: String?
    /// Category-rule matching checks THIS field, not primaryCategory —
    /// see SCHEMA.md, this distinction caused a real bug once already.
    public let tags: [String]
    /// Simplified inline aliases (not the formal one-row-per-alias
    /// merchant_aliases table) — see SCHEMA.md "2. merchant_aliases".
    public let aliases: [String]
    public let channel: String
    public let country: String
    public let active: Bool

    enum CodingKeys: String, CodingKey {
        case merchantId = "merchant_id"
        case canonicalName = "canonical_name"
        case displayName = "display_name"
        case primaryCategory = "primary_category"
        case subcategory
        case tags
        case aliases
        case channel
        case country
        case active
    }

    public init(
        merchantId: String,
        canonicalName: String,
        displayName: String,
        primaryCategory: String,
        subcategory: String?,
        tags: [String],
        aliases: [String],
        channel: String,
        country: String,
        active: Bool
    ) {
        self.merchantId = merchantId
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.primaryCategory = primaryCategory
        self.subcategory = subcategory
        self.tags = tags
        self.aliases = aliases
        self.channel = channel
        self.country = country
        self.active = active
    }
}
