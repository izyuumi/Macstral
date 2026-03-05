import XCTest
@testable import Macstral

final class TranscriptPostProcessorTests: XCTestCase {

    // MARK: - Enabled (default behaviour)

    func testLowercaseInputIsCapitalized() {
        let result = TranscriptPostProcessor.process("hello world", enabled: true)
        XCTAssertEqual(result, "Hello world.")
    }

    func testAlreadyCapitalizedIsUnchanged() {
        let result = TranscriptPostProcessor.process("Hello world", enabled: true)
        XCTAssertEqual(result, "Hello world.")
    }

    func testAlreadyPunctuatedWithPeriodNoPeriodAdded() {
        let result = TranscriptPostProcessor.process("Hello world.", enabled: true)
        XCTAssertEqual(result, "Hello world.")
    }

    func testAlreadyPunctuatedWithExclamationNoPeriodAdded() {
        let result = TranscriptPostProcessor.process("Hello world!", enabled: true)
        XCTAssertEqual(result, "Hello world!")
    }

    func testAlreadyPunctuatedWithQuestionNoPeriodAdded() {
        let result = TranscriptPostProcessor.process("are you there?", enabled: true)
        XCTAssertEqual(result, "Are you there?")
    }

    func testAlreadyPunctuatedWithEllipsisNoPeriodAdded() {
        let result = TranscriptPostProcessor.process("well…", enabled: true)
        XCTAssertEqual(result, "Well…")
    }

    func testLeadingAndTrailingWhitespaceStripped() {
        let result = TranscriptPostProcessor.process("  hello world  ", enabled: true)
        XCTAssertEqual(result, "Hello world.")
    }

    func testLeadingNewlinesStripped() {
        let result = TranscriptPostProcessor.process("\n\nhello", enabled: true)
        XCTAssertEqual(result, "Hello.")
    }

    // MARK: - Empty and whitespace-only inputs

    func testEmptyStringReturnsEmpty() {
        let result = TranscriptPostProcessor.process("", enabled: true)
        XCTAssertEqual(result, "")
    }

    func testWhitespaceOnlyReturnsEmpty() {
        let result = TranscriptPostProcessor.process("   \t\n  ", enabled: true)
        XCTAssertEqual(result, "")
    }

    // MARK: - Disabled (toggle off)

    func testDisabledReturnsOnlyTrimmedText() {
        let result = TranscriptPostProcessor.process("  hello world  ", enabled: false)
        XCTAssertEqual(result, "hello world",
                       "When disabled, only trimming should happen — no capitalization or period")
    }

    func testDisabledEmptyStringReturnsEmpty() {
        let result = TranscriptPostProcessor.process("", enabled: false)
        XCTAssertEqual(result, "")
    }

    func testDisabledAlreadyCapitalizedAndPunctuatedUnchanged() {
        let result = TranscriptPostProcessor.process("Hello world.", enabled: false)
        XCTAssertEqual(result, "Hello world.")
    }

    // MARK: - Non-ASCII first characters

    func testJapaneseTextUnchangedFirstChar() {
        // Japanese text has no casing; no capitalization should be applied.
        let result = TranscriptPostProcessor.process("日本語のテスト", enabled: true)
        XCTAssertEqual(result, "日本語のテスト.")
    }

    func testUppercaseFirstCharRemainsUppercase() {
        let result = TranscriptPostProcessor.process("UPPER CASE TEXT", enabled: true)
        XCTAssertEqual(result, "UPPER CASE TEXT.")
    }

    // MARK: - AutoPunctuationSettings defaults

    func testDefaultIsEnabled() {
        let suite = "com.macstral.tests.AutoPunctuationSettings"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        XCTAssertTrue(AutoPunctuationSettings.load(from: defaults),
                      "Default should be true when key has never been written")
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripDisabled() {
        let suite = "com.macstral.tests.AutoPunctuationSettings.roundtrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        AutoPunctuationSettings.save(false, to: defaults)
        XCTAssertFalse(AutoPunctuationSettings.load(from: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testResetRestoresDefault() {
        let suite = "com.macstral.tests.AutoPunctuationSettings.reset"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        AutoPunctuationSettings.save(false, to: defaults)
        AutoPunctuationSettings.reset(in: defaults)
        XCTAssertTrue(AutoPunctuationSettings.load(from: defaults))
        defaults.removePersistentDomain(forName: suite)
    }
}
