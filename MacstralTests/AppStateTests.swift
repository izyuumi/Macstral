import XCTest
@testable import Macstral

@MainActor
final class AppStateTests: XCTestCase {

    func testInitialValues() {
        let state = AppState()
        XCTAssertEqual(state.backendStatus, .stopped)
        XCTAssertEqual(state.dictationStatus, .idle)
        XCTAssertEqual(state.setupStep, .idle)
        XCTAssertEqual(state.setupProgress, 0.0)
        XCTAssertEqual(state.liveTranscript, "")
        XCTAssertEqual(state.finalTranscript, "")
        XCTAssertTrue(state.isOnboardingNeeded)
        XCTAssertFalse(state.hasMicPermission)
        XCTAssertFalse(state.hasAccessibilityPermission)
    }

    func testIsVoxtralReadyFalseWhenIdle() {
        let state = AppState()
        XCTAssertFalse(state.isVoxtralReady)
    }

    func testIsVoxtralReadyTrueWhenReady() {
        let state = AppState()
        state.setupStep = .ready
        XCTAssertTrue(state.isVoxtralReady)
    }

    func testIsVoxtralReadyFalseForIntermediateSteps() {
        let state = AppState()
        let intermediateSteps: [SetupStep] = [
            .downloadingPython, .installingDeps, .downloadingModel, .launching
        ]
        for step in intermediateSteps {
            state.setupStep = step
            XCTAssertFalse(state.isVoxtralReady, "Expected isVoxtralReady == false for step \(step)")
        }
    }

    func testIsVoxtralReadyFalseOnError() {
        let state = AppState()
        state.setupStep = .error("something went wrong")
        XCTAssertFalse(state.isVoxtralReady)
    }

    // MARK: - Transcript History

    func testInitialHistoryIsEmpty() {
        let state = AppState()
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testAppendToHistoryAddsEntry() {
        let state = AppState()
        state.appendToHistory("Hello world")
        XCTAssertEqual(state.transcriptHistory, ["Hello world"])
    }

    func testAppendToHistoryNewestFirst() {
        let state = AppState()
        state.appendToHistory("First")
        state.appendToHistory("Second")
        XCTAssertEqual(state.transcriptHistory.first, "Second")
        XCTAssertEqual(state.transcriptHistory.last, "First")
    }

    func testAppendToHistoryIgnoresEmpty() {
        let state = AppState()
        state.appendToHistory("")
        state.appendToHistory("   ")
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }

    func testAppendToHistoryTrimsWhitespace() {
        let state = AppState()
        state.appendToHistory("  hello  ")
        XCTAssertEqual(state.transcriptHistory.first, "hello")
    }

    func testAppendToHistoryCapsAt50() {
        let state = AppState()
        for i in 1...55 {
            state.appendToHistory("Entry \(i)")
        }
        XCTAssertEqual(state.transcriptHistory.count, 50)
        // Newest entry (55) should be first.
        XCTAssertEqual(state.transcriptHistory.first, "Entry 55")
    }

    func testClearHistoryEmptiesArray() {
        let state = AppState()
        state.appendToHistory("One")
        state.appendToHistory("Two")
        state.clearHistory()
        XCTAssertTrue(state.transcriptHistory.isEmpty)
    }
}
