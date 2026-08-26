import XCTest
@testable import CreditCardRewardLogic

/// Ported from test/evaluators_test.dart and test/recommendation_orchestrator_test.dart
/// against the real bundled cube_reward_rules.json / jiho_reward_rules.json /
/// merchants.json — same reasoning as the Dart originals: these prove the
/// actual shipped data behaves correctly, not just the matching algorithm
/// in isolation (that's RuleMatcherTests's job).
final class EvaluatorTests: XCTestCase {
    override func setUpWithError() throws {
        try RewardRulesRepository.shared.load()
        try MerchantRepository.shared.load()
    }

    // MARK: - CubeRewardEvaluator

    func testMatchesNamedMerchantUnderTaiPlasFamilyLevelInvariant() {
        let result = CubeRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(merchantName: "台塑石油加油站"),
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)
        )

        XCTAssertEqual(result.rewardRate, 2.0)
        XCTAssertTrue(result.matchedTags.contains("台塑家"))
    }

    func testSameMerchantYieldsDifferentRateAtDifferentLevel() {
        let context = MerchantQueryContext(merchantName: "誠品生活")

        let level1 = CubeRewardEvaluator.evaluate(
            merchantContext: context,
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)
        )
        let level3 = CubeRewardEvaluator.evaluate(
            merchantContext: context,
            input: CubeCardInput(level: "level_3", isNewCardHolder: false, hasKidsClub: false)
        )

        XCTAssertEqual(level1.rewardRate, 2.0)
        XCTAssertEqual(level3.rewardRate, 3.3)
        XCTAssertEqual(level3.requiredAction, "需切換至樂饗購權益方案")
    }

    func testCubeFallsBackToDefaultForUnknownMerchant() {
        let result = CubeRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(merchantName: "完全沒聽過的店"),
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)
        )

        XCTAssertEqual(result.rewardRate, 0.3)
        XCTAssertTrue(result.matchedTags.contains("一般消費"))
    }

    func testAliasFindsRealMerchantRuleViaResolvedCanonicalName() {
        // Regression guard: an alias like "小七" never equals/substring-
        // matches "7-ELEVEN (7-11) 實體門市" on its own — only passing
        // the resolved canonical name as a second candidate query finds
        // the real 2.0% rate instead of silently falling to default.
        guard let resolved = MerchantResolver.shared.resolve("小七") else {
            XCTFail("expected 小七 to resolve to a merchant")
            return
        }

        let result = CubeRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(
                merchantName: "小七",
                merchantTags: resolved.tags,
                resolvedCanonicalName: resolved.canonicalName
            ),
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)
        )

        XCTAssertEqual(result.rewardRate, 2.0)
        XCTAssertTrue(["台塑家", "集精選"].contains(result.matchedTags.first))
    }

    func testCategoryRuleFiresForMerchantNeverNamedByAllen() {
        // 藏壽司 has no card_reward_rules entry at all — only merchants.json
        // gives it the "restaurant" tag, which is what lets the 樂饗購
        // category rule (see SCHEMA.md) fire for it.
        guard let resolved = MerchantResolver.shared.resolve("藏壽司") else {
            XCTFail("expected 藏壽司 to resolve to a merchant")
            return
        }

        let result = CubeRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(
                merchantName: "藏壽司",
                merchantTags: resolved.tags,
                resolvedCanonicalName: resolved.canonicalName
            ),
            input: CubeCardInput(level: "level_2", isNewCardHolder: false, hasKidsClub: false)
        )

        XCTAssertEqual(result.rewardRate, 3.0)
        XCTAssertTrue(result.matchedTags.contains("樂饗購"))
        XCTAssertEqual(result.requiredAction, "需切換至樂饗購權益方案")
    }

    func testKidsClubGatesTongLeHuiScheme() {
        let context = MerchantQueryContext(merchantName: "麗寶樂園")

        let without = CubeRewardEvaluator.evaluate(
            merchantContext: context,
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)
        )
        let with = CubeRewardEvaluator.evaluate(
            merchantContext: context,
            input: CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: true)
        )

        XCTAssertEqual(without.rewardRate, 0.3)
        XCTAssertEqual(with.rewardRate, 5.0)
        XCTAssertTrue(with.matchedTags.contains("童樂匯"))
    }

    // MARK: - JihoRewardEvaluator

    func testMatchesNamedMerchantUnderJapaneseBrandDiscount() {
        let result = JihoRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(merchantName: "UNIQLO"),
            input: JihoCardInput(isNewCardHolder: false)
        )

        XCTAssertEqual(result.rewardRate, 5.5)
        XCTAssertTrue(result.matchedTags.contains("國內日系特店加碼"))
    }

    func testJihoFallsBackToDefaultForUnknownMerchant() {
        let result = JihoRewardEvaluator.evaluate(
            merchantContext: MerchantQueryContext(merchantName: "完全沒聽過的店"),
            input: JihoCardInput(isNewCardHolder: false)
        )

        XCTAssertEqual(result.rewardRate, 1.0)
    }

    func testNewCustomerDefaultRateAppliesInsteadOfPlainDefault() {
        let context = MerchantQueryContext(merchantName: "完全沒聽過的店")

        let existing = JihoRewardEvaluator.evaluate(
            merchantContext: context,
            input: JihoCardInput(isNewCardHolder: false)
        )
        let newCustomer = JihoRewardEvaluator.evaluate(
            merchantContext: context,
            input: JihoCardInput(isNewCardHolder: true)
        )

        XCTAssertEqual(existing.rewardRate, 1.0)
        XCTAssertEqual(newCustomer.rewardRate, 1.5)
    }

    // MARK: - RecommendationOrchestrator

    func testOrchestratorReturnsTopResultsSortedByRate() {
        let results = RecommendationOrchestrator.evaluate(
            merchantName: "全家",
            userCards: [
                .cube(CubeCardInput(level: "level_1", isNewCardHolder: false, hasKidsClub: false)),
                .jiho(JihoCardInput(isNewCardHolder: false)),
            ]
        )

        XCTAssertEqual(results.count, 2)
        // CUBE finds a real 2.0% merchant rule for 全家; jiho has no such
        // rule and falls to its 1.0% default — CUBE should sort first.
        XCTAssertEqual(results.first?.cardId, "cathay_cube")
        XCTAssertEqual(results.first?.rewardRate, 2.0)
    }

    func testOrchestratorReturnsEmptyForBlankQueryOrNoCards() {
        XCTAssertTrue(
            RecommendationOrchestrator.evaluate(
                merchantName: "",
                userCards: [.jiho(JihoCardInput(isNewCardHolder: false))]
            ).isEmpty
        )
        XCTAssertTrue(
            RecommendationOrchestrator.evaluate(merchantName: "全家", userCards: []).isEmpty
        )
    }
}
