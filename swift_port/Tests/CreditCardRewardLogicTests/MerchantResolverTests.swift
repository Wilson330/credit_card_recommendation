import XCTest
@testable import CreditCardRewardLogic

/// Ported from test/merchant_resolver_test.dart, against the real bundled
/// merchants.json (not synthetic data), same as the Dart original.
final class MerchantResolverTests: XCTestCase {
    override func setUpWithError() throws {
        try MerchantRepository.shared.load()
    }

    func testResolvesExactCanonicalNameToItsTags() {
        let resolver = MerchantResolver()
        let tags = resolver.tags(for: "藏壽司")

        XCTAssertTrue(tags.contains("restaurant"))
    }

    func testResolvesViaConservativeSubstringMatch() {
        let resolver = MerchantResolver()
        // "小北" is a substring of the canonical name "小北百貨", and
        // isn't registered as an alias, so this exercises tier 2.
        let tags = resolver.tags(for: "小北")

        XCTAssertTrue(tags.contains("general_retail"))
    }

    func testResolvesEnglishAliasToSameMerchantAsCanonicalName() {
        let resolver = MerchantResolver()

        let viaAlias = resolver.resolve("KFC")
        let viaCanonical = resolver.resolve("肯德基")

        XCTAssertNotNil(viaAlias)
        XCTAssertNotNil(viaCanonical)
        XCTAssertEqual(viaAlias?.merchantId, viaCanonical?.merchantId)
        XCTAssertTrue(viaAlias?.tags.contains("fast_food") ?? false)
    }

    func testResolvesCommonChineseShortFormAlias() {
        let resolver = MerchantResolver()
        let tags = resolver.tags(for: "7-11")

        XCTAssertTrue(tags.contains("chain_store"))
    }

    func testResolvesOfficialCorporateNameAlias() {
        // User-reported gap in the Flutter app: "統一超商" (7-11 Taiwan's
        // operating company name) should resolve the same as "7-11".
        let resolver = MerchantResolver()

        let viaAlias = resolver.resolve("統一超商")
        let viaShortForm = resolver.resolve("7-11")

        XCTAssertNotNil(viaAlias)
        XCTAssertEqual(viaAlias?.merchantId, viaShortForm?.merchantId)
    }

    func testReturnsNoTagsForMerchantNotInDirectory() {
        let resolver = MerchantResolver()
        let tags = resolver.tags(for: "完全沒聽過的店家名稱")

        XCTAssertTrue(tags.isEmpty)
    }

    func testEmptyQueryReturnsNoTags() {
        let resolver = MerchantResolver()
        XCTAssertTrue(resolver.tags(for: "").isEmpty)
    }
}
