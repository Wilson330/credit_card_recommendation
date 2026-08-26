import Foundation

public struct JihoCardInput {
    public let isNewCardHolder: Bool

    public init(isNewCardHolder: Bool) {
        self.isNewCardHolder = isNewCardHolder
    }
}

/// Mirrors lib/services/evaluators/jiho_reward_evaluator.dart.
public enum JihoRewardEvaluator {
    public static let cardId = "ubot_jiho"

    public static func evaluate(
        merchantContext: MerchantQueryContext,
        input: JihoCardInput,
        rules: [CardRewardRule]? = nil
    ) -> RewardEvaluationResult {
        let activeRules = rules ?? RewardRulesRepository.shared.rulesFor(cardId)

        var activeConditions: Set<String> = []
        if input.isNewCardHolder { activeConditions.insert("new_customer") }

        let rule = RuleMatcher.selectBestRule(
            rules: activeRules,
            normalizedQueries: MerchantMatcher.normalizedCandidates(
                merchantContext.merchantName,
                merchantContext.resolvedCanonicalName
            ),
            merchantTags: merchantContext.merchantTags,
            currentLevel: nil,
            activeConditions: activeConditions
        )

        var matchedTags = [rule.benefitLabel]
        if input.isNewCardHolder {
            // Only the 國內一般消費 new-customer bump (a plain
            // default-rate condition) is actually reflected in
            // rewardRate. The Japan new-customer rows also require
            // knowing payment method / being physically in Japan —
            // inputs no search bar collects yet — so those stay
            // unreachable regardless of this flag. See SCHEMA.md.
            matchedTags.append("新戶身份已套用（僅國內一般消費，日本相關新戶加碼待補輸入欄位）")
        }

        return RewardEvaluationResult(
            cardId: cardId,
            cardName: "吉鶴卡",
            rewardRate: rule.rewardRate,
            matchedTags: matchedTags,
            requiredAction: rule.requiredAction,
            constraints: rule.constraints
        )
    }
}
