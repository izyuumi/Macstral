import XCTest
@testable import Macstral

@MainActor
final class AIWritingPromptBuilderTests: XCTestCase {

    func testClassifierTreatsSelectedEditCommandAsEdit() {
        let context = makeContext(selectedText: "This is too long and kind of harsh.")
        let task = AIWritingIntentClassifier.classify(
            rawTranscript: "make this shorter and more polite",
            context: context
        )
        XCTAssertEqual(task, .editSelection)
    }

    func testClassifierTreatsNoSelectionAsDictation() {
        let task = AIWritingIntentClassifier.classify(
            rawTranscript: "make this shorter",
            context: makeContext(selectedText: "")
        )
        XCTAssertEqual(task, .dictation)
    }

    func testPromptIncludesSelectedTextAndSurroundingContext() {
        let context = FocusedTextContext(
            appBundleIdentifier: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            elementRole: "AXTextArea",
            elementTitle: "Message",
            selectedText: "Can you send the update today?",
            textBeforeSelection: "Alice wrote:\n",
            textAfterSelection: "\nThanks."
        )
        let request = AIWritingRequest(
            rawTranscript: "write a friendly reply",
            task: .editSelection,
            context: context,
            languageCode: "en"
        )
        let input = AIWritingPromptBuilder.input(for: request)
        XCTAssertTrue(input.contains("Task: edit selected text"))
        XCTAssertTrue(input.contains("Slack"))
        XCTAssertTrue(input.contains("Can you send the update today?"))
        XCTAssertTrue(input.contains("Alice wrote:"))
        XCTAssertTrue(input.contains("write a friendly reply"))
    }

    func testEditFallbackKeepsOriginalSelectedText() {
        let request = AIWritingRequest(
            rawTranscript: "make this shorter",
            task: .editSelection,
            context: makeContext(selectedText: "Original text"),
            languageCode: nil
        )
        XCTAssertEqual(AIWritingPromptBuilder.fallbackText(for: request), "Original text")
    }

    func testDictationFallbackUsesTranscriptFormatter() {
        let request = AIWritingRequest(
            rawTranscript: "hello   world",
            task: .dictation,
            context: makeContext(selectedText: ""),
            languageCode: nil
        )
        XCTAssertEqual(AIWritingPromptBuilder.fallbackText(for: request), "Hello world.")
    }

    private func makeContext(selectedText: String) -> FocusedTextContext {
        FocusedTextContext(
            appBundleIdentifier: "test.app",
            appName: "Test",
            elementRole: "AXTextArea",
            elementTitle: "",
            selectedText: selectedText,
            textBeforeSelection: "",
            textAfterSelection: ""
        )
    }
}
