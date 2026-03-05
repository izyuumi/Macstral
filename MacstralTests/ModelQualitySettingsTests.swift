import XCTest
@testable import Macstral

final class ModelQualitySettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "com.macstral.tests.ModelQualitySettings"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default

    func testDefaultQualityIsFastWhenKeyAbsent() {
        let quality = ModelQualitySettings.load(from: defaults)
        XCTAssertEqual(quality, .fast, "Fresh install should default to Fast tier")
    }

    func testDefaultQualityMatchesConstant() {
        XCTAssertEqual(ModelQualitySettings.defaultQuality, .fast)
    }

    // MARK: - Round-trip persistence

    func testRoundTripFast() {
        ModelQualitySettings.save(.fast, to: defaults)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .fast)
    }

    func testRoundTripBalanced() {
        ModelQualitySettings.save(.balanced, to: defaults)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .balanced)
    }

    func testRoundTripAccurate() {
        ModelQualitySettings.save(.accurate, to: defaults)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .accurate)
    }

    // MARK: - Overwrite

    func testSaveOverwritesPreviousValue() {
        ModelQualitySettings.save(.accurate, to: defaults)
        ModelQualitySettings.save(.balanced, to: defaults)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .balanced)
    }

    // MARK: - Reset

    func testResetRestoresDefaultFast() {
        ModelQualitySettings.save(.accurate, to: defaults)
        ModelQualitySettings.reset(in: defaults)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .fast)
    }

    // MARK: - Corrupt data

    func testUnknownRawValueFallsBackToFast() {
        defaults.set("ultra", forKey: ModelQualitySettings.key)
        XCTAssertEqual(ModelQualitySettings.load(from: defaults), .fast)
    }

    // MARK: - ModelQuality enum properties

    func testFastDoesNotRequireDownload() {
        XCTAssertFalse(ModelQuality.fast.requiresDownload)
    }

    func testBalancedRequiresDownload() {
        XCTAssertTrue(ModelQuality.balanced.requiresDownload)
    }

    func testAccurateRequiresDownload() {
        XCTAssertTrue(ModelQuality.accurate.requiresDownload)
    }

    func testModelIDsAreDistinct() {
        let ids = ModelQuality.allCases.map(\.modelID)
        XCTAssertEqual(ids.count, Set(ids).count, "Every tier must map to a unique model ID")
    }

    func testModelIDsPointToMlxCommunity() {
        for tier in ModelQuality.allCases {
            XCTAssertTrue(tier.modelID.hasPrefix("mlx-community/"),
                          "\(tier.displayName) modelID should be an mlx-community repo")
        }
    }

    func testDisplayNamesAreNonEmpty() {
        for tier in ModelQuality.allCases {
            XCTAssertFalse(tier.displayName.isEmpty)
        }
    }

    func testDownloadConfirmationMessageContainsSizeLabel() {
        for tier in ModelQuality.allCases where tier.requiresDownload {
            XCTAssertTrue(tier.downloadConfirmationMessage.contains(tier.sizeLabel),
                          "\(tier.displayName) confirmation should mention its size")
        }
    }
}
