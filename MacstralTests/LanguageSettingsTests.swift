import XCTest
@testable import Macstral

final class LanguageSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "com.macstral.tests.LanguageSettings"

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

    func testDefaultLanguageIsAutoWhenKeyAbsent() {
        let lang = LanguageSettings.load(from: defaults)
        XCTAssertEqual(lang, .auto, "Fresh install should default to auto-detect")
    }

    func testDefaultLanguageMatchesConstant() {
        XCTAssertEqual(LanguageSettings.defaultLanguage, .auto)
    }

    // MARK: - Round-trip persistence

    func testRoundTripAuto() {
        LanguageSettings.save(.auto, to: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .auto)
    }

    func testRoundTripJapanese() {
        LanguageSettings.save(.ja, to: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .ja)
    }

    func testRoundTripFrench() {
        LanguageSettings.save(.fr, to: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .fr)
    }

    func testRoundTripSpanish() {
        LanguageSettings.save(.es, to: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .es)
    }

    // MARK: - Overwrite

    func testSaveOverwritesPreviousValue() {
        LanguageSettings.save(.fr, to: defaults)
        LanguageSettings.save(.de, to: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .de)
    }

    // MARK: - Reset

    func testResetRestoresDefault() {
        LanguageSettings.save(.ja, to: defaults)
        LanguageSettings.reset(in: defaults)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .auto)
    }

    // MARK: - Corrupt data

    func testUnknownRawValueFallsBackToAuto() {
        defaults.set("klingon", forKey: LanguageSettings.key)
        XCTAssertEqual(LanguageSettings.load(from: defaults), .auto)
    }

    // MARK: - TranscriptionLanguage enum properties

    func testAutoBackendCodeIsNil() {
        XCTAssertNil(TranscriptionLanguage.auto.backendCode)
    }

    func testNonAutoBackendCodeEqualsRawValue() {
        for lang in TranscriptionLanguage.allCases where lang != .auto {
            XCTAssertEqual(lang.backendCode, lang.rawValue,
                           "\(lang.displayName) backendCode should equal rawValue")
        }
    }

    func testIsBetaLanguages() {
        XCTAssertTrue(TranscriptionLanguage.ja.isBeta)
        XCTAssertTrue(TranscriptionLanguage.zh.isBeta)
        XCTAssertFalse(TranscriptionLanguage.en.isBeta)
        XCTAssertFalse(TranscriptionLanguage.fr.isBeta)
        XCTAssertFalse(TranscriptionLanguage.auto.isBeta)
    }
}
