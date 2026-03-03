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
}
