import Foundation

/// Everything CubeRewardEvaluator needs to know about the user's CUBE
/// card — deliberately a plain struct, not a class hierarchy, to keep
/// integration with an existing @AppStorage-based state design (like
/// ContentView.swift's) simple: build one of these from whatever local
/// storage you're already using.
public struct CubeCardInput {
    /// "level_1" | "level_2" | "level_3" — note this is snake_case, NOT
    /// ContentView.swift's existing "Level 1"/"Level 2"/"Level 3" strings.
    /// Map your UI's level string to this format before calling evaluate.
    public let level: String
    public let isNewCardHolder: Bool
    /// Gates the 童樂匯 scheme (see SCHEMA.md's required_conditions design).
    public let hasKidsClub: Bool

    public init(level: String, isNewCardHolder: Bool, hasKidsClub: Bool) {
        self.level = level
        self.isNewCardHolder = isNewCardHolder
        self.hasKidsClub = hasKidsClub
    }
}

/// Mirrors lib/services/evaluators/cube_reward_evaluator.dart.
public enum CubeRewardEvaluator {
    public static let cardId = "cathay_cube"

    public static func evaluate(
        merchantContext: MerchantQueryContext,
        input: CubeCardInput,
        rules: [CardRewardRule]? = nil
    ) -> RewardEvaluationResult {
        let activeRules = rules ?? RewardRulesRepository.shared.rulesFor(cardId)

        var activeConditions: Set<String> = []
        if input.hasKidsClub { activeConditions.insert("kids_club") }

        let rule = RuleMatcher.selectBestRule(
            rules: activeRules,
            normalizedQueries: MerchantMatcher.normalizedCandidates(
                merchantContext.merchantName,
                merchantContext.resolvedCanonicalName
            ),
            merchantTags: merchantContext.merchantTags,
            currentLevel: input.level,
            activeConditions: activeConditions
        )

        var matchedTags = [rule.benefitLabel]
        if input.isNewCardHolder {
            matchedTags.append("新戶身份已套用")
        }

        return RewardEvaluationResult(
            cardId: cardId,
            cardName: "CUBE Card",
            rewardRate: rule.rewardRate,
            matchedTags: matchedTags,
            requiredAction: rule.requiredAction,
            constraints: rule.constraints
        )
    }
}
