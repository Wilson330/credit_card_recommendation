import Foundation

/// One case per card this package has real reward data for. Deliberately
/// does NOT include Unicard/商旅鈦金卡 — ContentView.swift's UI can keep
/// those options (per 2026-08-06 decision to leave that UI alone), but
/// there's no crawled data or evaluator for them yet. Add a case here
/// (mirroring RecommendationOrchestrator's registry pattern on the Dart
/// side — see lib/services/recommendation_orchestrator.dart) once real
/// data exists for a new card, and evaluate(_:) skips any card the user
/// has that doesn't have a case here, rather than crashing.
public enum UserCardInput {
    case cube(CubeCardInput)
    case jiho(JihoCardInput)
}

/// Mirrors lib/services/recommendation_orchestrator.dart: resolves the
/// merchant ONCE (shared across every card, not per-evaluator), runs
/// every card the user holds through its own evaluator, sorts by reward
/// rate (ties broken by number of matched tags, then card name), and
/// returns the top 3 — the same v1 behavior as the Flutter app.
public enum RecommendationOrchestrator {
    /// Call only after RewardRulesRepository.shared.load() and
    /// MerchantRepository.shared.load() have both completed (e.g. at app
    /// launch) — this function itself does no I/O and doesn't throw.
    public static func evaluate(
        merchantName: String,
        userCards: [UserCardInput]
    ) -> [RewardEvaluationResult] {
        let trimmed = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !userCards.isEmpty else { return [] }

        let resolvedMerchant = MerchantResolver.shared.resolve(trimmed)
        let context = MerchantQueryContext(
            merchantName: trimmed,
            merchantTags: resolvedMerchant?.tags ?? [],
            resolvedCanonicalName: resolvedMerchant?.canonicalName
        )

        var results: [RewardEvaluationResult] = []
        for card in userCards {
            switch card {
            case .cube(let input):
                results.append(CubeRewardEvaluator.evaluate(merchantContext: context, input: input))
            case .jiho(let input):
                results.append(JihoRewardEvaluator.evaluate(merchantContext: context, input: input))
            }
        }

        results.sort { lhs, rhs in
            if lhs.rewardRate != rhs.rewardRate { return lhs.rewardRate > rhs.rewardRate }
            if lhs.matchedTags.count != rhs.matchedTags.count {
                return lhs.matchedTags.count > rhs.matchedTags.count
            }
            return lhs.cardName < rhs.cardName
        }

        return Array(results.prefix(3))
    }
}
