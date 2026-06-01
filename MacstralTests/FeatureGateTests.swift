import XCTest
@testable import Macstral

// MARK: - FeatureGateTests

/// Locks in the Macstral monetization model: every on-device capability is Free for everyone,
/// and only the online (Macstral-hosted) processing path is Pro-gated.
final class FeatureGateTests: XCTestCase {

    // MARK: On-device features are Free for everyone

    func testEveryLanguageIsFreeForNonPro() {
        for language in TranscriptionLanguage.allCases {
            XCTAssertTrue(
                FeatureGate.isLanguageUnlocked(language, isPro: false),
                "\(language.rawValue) runs on-device and must be Free"
            )
        }
    }

    func testEveryModelQualityIsFreeForNonPro() {
        for quality in ModelQuality.allCases {
            XCTAssertTrue(
                FeatureGate.isModelQualityUnlocked(quality, isPro: false),
                "\(quality.rawValue) runs on-device and must be Free"
            )
        }
    }

    func testHistoryIsFreeForNonPro() {
        XCTAssertTrue(FeatureGate.isHistoryUnlocked(isPro: false))
    }

    func testAutoPunctuationIsFreeForNonPro() {
        XCTAssertTrue(FeatureGate.isAutoPunctuationEnabled(isPro: false))
    }

    // MARK: No clamping of on-device settings

    func testEffectiveLanguageNeverClamps() {
        XCTAssertEqual(FeatureGate.effectiveLanguage(.ja, isPro: false), .ja)
        XCTAssertEqual(FeatureGate.effectiveLanguage(.zh, isPro: false), .zh)
        XCTAssertEqual(FeatureGate.effectiveLanguage(.en, isPro: true), .en)
    }

    func testEffectiveModelQualityNeverClamps() {
        XCTAssertEqual(FeatureGate.effectiveModelQuality(.accurate, isPro: false), .accurate)
        XCTAssertEqual(FeatureGate.effectiveModelQuality(.balanced, isPro: false), .balanced)
        XCTAssertEqual(FeatureGate.effectiveModelQuality(.fast, isPro: true), .fast)
    }

    // MARK: Online processing is the only Pro gate

    func testCloudProcessingIsProOnly() {
        XCTAssertFalse(
            FeatureGate.isCloudProcessingUnlocked(isPro: false),
            "Free users must not reach the online processing path"
        )
        XCTAssertTrue(
            FeatureGate.isCloudProcessingUnlocked(isPro: true),
            "Pro unlocks the online processing path"
        )
    }
}
