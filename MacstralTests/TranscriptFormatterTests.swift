import XCTest
@testable import Macstral

/// Tests for `TranscriptFormatter.format(_:)` — the pure Phase-1 heuristic
/// transcript punctuation/capitalization formatter.
final class TranscriptFormatterTests: XCTestCase {

    // MARK: - Empty / whitespace input

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(TranscriptFormatter.format(""), "",
                       "Empty input must return an empty string")
    }

    func testWhitespaceOnlyReturnsEmpty() {
        XCTAssertEqual(TranscriptFormatter.format("   \n\t  \n  "), "",
                       "Whitespace/newline-only input must return an empty string")
    }

    func testWhitespaceOnlyNeverCrashes() {
        _ = TranscriptFormatter.format("\n\n\n")
    }

    // MARK: - Trimming

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(TranscriptFormatter.format("   hello world   "), "Hello world.",
                       "Leading/trailing whitespace should be trimmed before formatting")
    }

    func testTrimsLeadingAndTrailingNewlines() {
        XCTAssertEqual(TranscriptFormatter.format("\n\nhello world\n\n"), "Hello world.",
                       "Leading/trailing newlines should be trimmed")
    }

    // MARK: - Whitespace collapsing

    func testCollapsesDoubleSpaces() {
        XCTAssertEqual(TranscriptFormatter.format("hello    world"), "Hello world.",
                       "Runs of 2+ spaces should collapse to a single space")
    }

    func testCollapsesManySpacesBetweenManyWords() {
        XCTAssertEqual(TranscriptFormatter.format("a  b   c    d"), "A b c d.",
                       "Every multi-space run should collapse to one space")
    }

    func testCollapsesThreePlusNewlinesToTwo() {
        let input = "first sentence.\n\n\n\nsecond sentence"
        XCTAssertEqual(TranscriptFormatter.format(input), "First sentence.\n\nSecond sentence.",
                       "3+ consecutive newlines should collapse to at most two")
    }

    func testPreservesSingleAndDoubleNewlines() {
        let input = "line one\nline two\n\nline three"
        XCTAssertEqual(TranscriptFormatter.format(input), "Line one\nline two\n\nline three.",
                       "Single and double newlines should be preserved as-is")
    }

    // MARK: - Space before punctuation

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(TranscriptFormatter.format("hello , world ; bye : end !"),
                       "Hello, world; bye: end!",
                       "Spaces before , ; : ! should be removed")
    }

    func testRemovesSpaceBeforePeriodAndQuestionMark() {
        XCTAssertEqual(TranscriptFormatter.format("what ? really ."),
                       "What? Really.",
                       "Spaces before ? and . should be removed and sentences capitalized")
    }

    // MARK: - Capitalization

    func testCapitalizesFirstCharacter() {
        XCTAssertEqual(TranscriptFormatter.format("hello"), "Hello.",
                       "First alphabetic character should be capitalized")
    }

    func testCapitalizesEachSentence() {
        let input = "first sentence. second sentence! third sentence?"
        XCTAssertEqual(TranscriptFormatter.format(input),
                       "First sentence. Second sentence! Third sentence?",
                       "Each sentence after a terminator should be capitalized")
    }

    func testDoesNotLowercaseExistingCapitals() {
        XCTAssertEqual(TranscriptFormatter.format("HELLO world"), "HELLO world.",
                       "Already-capitalized text should not be down-cased")
    }

    func testCapitalizesFirstAlphabeticCharacterAfterLeadingDigits() {
        XCTAssertEqual(TranscriptFormatter.format("123 things happened"),
                       "123 Things happened.",
                       "The first alphabetic character of the string should be capitalized even after leading digits")
    }

    // MARK: - Terminal punctuation

    func testAppendsPeriodWhenMissing() {
        XCTAssertEqual(TranscriptFormatter.format("no terminator here"),
                       "No terminator here.",
                       "A period should be appended when terminal punctuation is missing")
    }

    func testPreservesTrailingQuestionMark() {
        XCTAssertEqual(TranscriptFormatter.format("are you sure?"),
                       "Are you sure?",
                       "A trailing question mark must be preserved, not given a period")
    }

    func testPreservesTrailingExclamation() {
        XCTAssertEqual(TranscriptFormatter.format("watch out!"),
                       "Watch out!",
                       "A trailing exclamation mark must be preserved")
    }

    func testPreservesTrailingEllipsis() {
        XCTAssertEqual(TranscriptFormatter.format("to be continued…"),
                       "To be continued…",
                       "A trailing ellipsis character should count as terminal punctuation")
    }

    func testTerminatorBeforeClosingQuoteIsAccepted() {
        XCTAssertEqual(TranscriptFormatter.format("she said \"hello.\""),
                       "She said \"hello.\"",
                       "Terminal punctuation followed by a closing quote should not get a period")
    }

    func testNoTerminatorBeforeClosingParenGetsPeriod() {
        XCTAssertEqual(TranscriptFormatter.format("an aside (no terminator)"),
                       "An aside (no terminator).",
                       "A closing paren with no preceding terminator should still receive a period")
    }

    // MARK: - Idempotency

    func testAlreadyFormattedIsIdempotent() {
        let formatted = "Hello world. This is fine!"
        XCTAssertEqual(TranscriptFormatter.format(formatted), formatted,
                       "Formatting already-clean text should be a no-op")
    }

    func testDoubleFormattingIsStable() {
        let once = TranscriptFormatter.format("hello   world . next one")
        let twice = TranscriptFormatter.format(once)
        XCTAssertEqual(once, twice,
                       "Running the formatter twice should produce the same result")
    }

    // MARK: - Multibyte / emoji safety

    func testEmojiInputDoesNotCrash() {
        _ = TranscriptFormatter.format("hello 👋🏽 world 🎉")
    }

    func testEmojiInputIsFormatted() {
        XCTAssertEqual(TranscriptFormatter.format("hello 👋 world"),
                       "Hello 👋 world.",
                       "Emoji should pass through while surrounding text is formatted")
    }

    func testMultibyteScriptIsPreservedAndTerminated() {
        XCTAssertEqual(TranscriptFormatter.format("これはテストです"),
                       "これはテストです.",
                       "Non-Latin text should be preserved unchanged and given terminal punctuation")
    }

    func testGraphemeClusterEmojiNotSplit() {
        // A flag is a multi-scalar grapheme cluster; it must survive intact.
        let output = TranscriptFormatter.format("flag 🇯🇵 here")
        XCTAssertTrue(output.contains("🇯🇵"),
                      "Multi-scalar emoji grapheme clusters must not be split")
    }
}
