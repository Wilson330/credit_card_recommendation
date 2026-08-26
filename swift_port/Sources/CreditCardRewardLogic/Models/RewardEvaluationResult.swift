import Foundation

/// Mirrors lib/models/reward_evaluation_result.dart. What ContentView.swift
/// should render per card: reward rate, required action (e.g. "switch to
/// this benefit program"), and constraints — matches the v1 result-page
/// requirements (see the product spec memory: reward rate / required
/// action / constraints are the v1 must-haves, a "why this card" reason
/// string is explicitly not required for v1).
public struct RewardEvaluationResult {
    public let cardId: String
    public let cardName: String
    public let rewardRate: Double
    public let matchedTags: [String]
    public let requiredAction: String?
    public let constraints: [String]

    public init(
        cardId: String,
        cardName: String,
        rewardRate: Double,
        matchedTags: [String],
        requiredAction: String? = nil,
        constraints: [String] = []
    ) {
        self.cardId = cardId
        self.cardName = cardName
        self.rewardRate = rewardRate
        self.matchedTags = matchedTags
        self.requiredAction = requiredAction
        self.constraints = constraints
    }
}
