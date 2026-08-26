import XCTest
@testable import CreditCardRewardLogic

/// Ported from test/rule_matcher_test.dart — uses synthetic data (not the
/// bundled real JSON) so each scenario can be constructed precisely,
/// same reasoning as the Dart original.
final class RuleMatcherTests: XCTestCase {
    private func rule(
        ruleId: String,
        ruleType: String,
        matchValue: String,
        rewardRate: Double,
        applicableLevel: String? = nil,
        requiredConditions: [String] = []
    ) -> CardRewardRule {
        CardRewardRule(
            ruleId: ruleId,
            cardId: "test_card",
            ruleType: ruleType,
            matchValue: matchValue,
            applicableLevel: applicableLevel,
            rewardRate: rewardRate,
            benefitLabel: ruleId,
            requiredAction: nil,
            requiredConditions: requiredConditions,
            constraints: [],
            isSyntheticCondition: false,
            active: true
        )
    }

    func testSecondCandidateFindsExactMatchFirstAloneCannot() {
        let rules = [
            rule(ruleId: "kfc", ruleType: "merchant", matchValue: "肯德基", rewardRate: 5.0),
            rule(ruleId: "default", ruleType: "default", matchValue: "*", rewardRate: 0.3),
        ]

        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["kfc", "肯德基"],
            merchantTags: []
        )

        XCTAssertEqual(result.ruleId, "kfc")
        XCTAssertEqual(result.rewardRate, 5.0)
    }

    func testExactMatchNeverDisplacedByHigherRateSubstring() {
        let rules = [
            rule(ruleId: "exact", ruleType: "merchant", matchValue: "全家", rewardRate: 1.0),
            rule(ruleId: "wrong_merchant", ruleType: "merchant", matchValue: "全家福超市", rewardRate: 10.0),
        ]

        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["全家"],
            merchantTags: []
        )

        XCTAssertEqual(result.ruleId, "exact")
        XCTAssertEqual(result.rewardRate, 1.0)
    }

    func testFallsBackToSubstringOnlyWhenNoExactMatch() {
        let rules = [
            rule(ruleId: "full_name", ruleType: "merchant", matchValue: "全家便利商店 實體門市", rewardRate: 2.0),
        ]

        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["全家"],
            merchantTags: []
        )

        XCTAssertEqual(result.ruleId, "full_name")
    }

    func testDoesNotSubstringMatchBelowSafetyMinimum() {
        let rules = [
            rule(ruleId: "short", ruleType: "merchant", matchValue: "A", rewardRate: 5.0),
            rule(ruleId: "default", ruleType: "default", matchValue: "*", rewardRate: 0.1),
        ]

        // "A" is a substring of "AB", but both are below the 2-char
        // safety floor — must NOT match, or a single-letter rule would
        // swallow almost every query containing that letter.
        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["ab"],
            merchantTags: []
        )

        XCTAssertEqual(result.ruleId, "default")
    }

    func testCategoryRuleMatchesViaMerchantTagsNotMatchValueText() {
        let rules = [
            rule(ruleId: "dining_category", ruleType: "category", matchValue: "dining", rewardRate: 3.0),
            rule(ruleId: "default", ruleType: "default", matchValue: "*", rewardRate: 0.1),
        ]

        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["某個沒人聽過的餐廳"],
            merchantTags: ["dining"]
        )

        XCTAssertEqual(result.ruleId, "dining_category")
    }

    func testRequiredConditionsExcludesRuleWhenConditionNotActive() {
        let rules = [
            rule(
                ruleId: "kids_club_only",
                ruleType: "merchant",
                matchValue: "麗寶樂園",
                rewardRate: 10.0,
                requiredConditions: ["kids_club"]
            ),
            rule(ruleId: "default", ruleType: "default", matchValue: "*", rewardRate: 0.3),
        ]

        let without = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["麗寶樂園"],
            merchantTags: []
        )
        let with = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["麗寶樂園"],
            merchantTags: [],
            activeConditions: ["kids_club"]
        )

        XCTAssertEqual(without.ruleId, "default")
        XCTAssertEqual(with.ruleId, "kids_club_only")
        XCTAssertEqual(with.rewardRate, 10.0)
    }

    func testMultipleDefaultRulesHighestRateQualifyingOneWins() {
        let rules = [
            rule(ruleId: "plain_default", ruleType: "default", matchValue: "*", rewardRate: 1.0),
            rule(
                ruleId: "new_customer_default",
                ruleType: "default",
                matchValue: "*",
                rewardRate: 1.5,
                requiredConditions: ["new_customer"]
            ),
        ]

        let asExisting = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["某個完全沒聽過的店"],
            merchantTags: []
        )
        let asNew = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["某個完全沒聽過的店"],
            merchantTags: [],
            activeConditions: ["new_customer"]
        )

        XCTAssertEqual(asExisting.ruleId, "plain_default")
        XCTAssertEqual(asNew.ruleId, "new_customer_default")
        XCTAssertEqual(asNew.rewardRate, 1.5)
    }

    func testApplicableLevelFiltersOutRulesForDifferentLevel() {
        let rules = [
            rule(
                ruleId: "level_2_only",
                ruleType: "merchant",
                matchValue: "誠品生活",
                rewardRate: 3.0,
                applicableLevel: "level_2"
            ),
            rule(ruleId: "default", ruleType: "default", matchValue: "*", rewardRate: 0.3),
        ]

        let result = RuleMatcher.selectBestRule(
            rules: rules,
            normalizedQueries: ["誠品生活"],
            merchantTags: [],
            currentLevel: "level_1"
        )

        XCTAssertEqual(result.ruleId, "default")
    }
}
