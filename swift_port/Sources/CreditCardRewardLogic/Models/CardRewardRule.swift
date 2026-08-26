import Foundation

/// Mirrors lib/models/card_reward_rule.dart in the Flutter reference app —
/// see SCHEMA.md there for the authoritative field-by-field description.
/// Ported by Claude (not hand-verified in Xcode); the Dart implementation
/// and its test suite are the source of truth this was translated from.
public struct CardRewardRule: Codable {
    public let ruleId: String
    public let cardId: String
    /// "merchant" | "category" | "default"
    public let ruleType: String
    public let matchValue: String
    public let applicableLevel: String?
    public let rewardRate: Double
    public let benefitLabel: String
    public let requiredAction: String?
    /// All of these must be present in the evaluator's activeConditions
    /// for this rule to be eligible at all (e.g. ["kids_club"]). Empty
    /// means no extra condition. See SCHEMA.md's 2026-08-06 redesign note.
    public let requiredConditions: [String]
    public let constraints: [String]
    /// true = matchValue is a condition label (e.g. a payment-method or
    /// country condition), not a real merchant name — currently
    /// unreachable from a plain merchant-name search. See SCHEMA.md.
    public let isSyntheticCondition: Bool
    public let active: Bool

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case cardId = "card_id"
        case ruleType = "rule_type"
        case matchValue = "match_value"
        case applicableLevel = "applicable_level"
        case rewardRate = "reward_rate"
        case benefitLabel = "benefit_label"
        case requiredAction = "required_action"
        case requiredConditions = "required_conditions"
        case constraints
        case isSyntheticCondition = "is_synthetic_condition"
        case active
    }

    public init(
        ruleId: String,
        cardId: String,
        ruleType: String,
        matchValue: String,
        applicableLevel: String?,
        rewardRate: Double,
        benefitLabel: String,
        requiredAction: String?,
        requiredConditions: [String],
        constraints: [String],
        isSyntheticCondition: Bool,
        active: Bool
    ) {
        self.ruleId = ruleId
        self.cardId = cardId
        self.ruleType = ruleType
        self.matchValue = matchValue
        self.applicableLevel = applicableLevel
        self.rewardRate = rewardRate
        self.benefitLabel = benefitLabel
        self.requiredAction = requiredAction
        self.requiredConditions = requiredConditions
        self.constraints = constraints
        self.isSyntheticCondition = isSyntheticCondition
        self.active = active
    }
}
