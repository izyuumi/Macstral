import XCTest
@testable import Macstral

final class SessionTimerTests: XCTestCase {

    // MARK: - Initial state

    func testInitialElapsedIsZero() {
        let timer = SessionTimer()
        XCTAssertEqual(timer.elapsedSeconds, 0)
    }

    func testInitialFormattedTimeIsZeroZero() {
        let timer = SessionTimer()
        XCTAssertEqual(timer.formattedTime, "0:00")
    }

    // MARK: - MM:SS formatting

    func testFormattedAtOneMinute() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 60
        XCTAssertEqual(timer.formattedTime, "1:00")
    }

    func testFormattedAtOneMinuteFiveSeconds() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 65
        XCTAssertEqual(timer.formattedTime, "1:05")
    }

    func testFormattedAtFiftyNineMinutesFiftyNineSeconds() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 59 * 60 + 59   // 3599
        XCTAssertEqual(timer.formattedTime, "59:59")
    }

    func testFormattedAtTenMinutes() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 600
        XCTAssertEqual(timer.formattedTime, "10:00")
    }

    func testFormattedSingleDigitSecondsHasLeadingZero() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 9
        XCTAssertEqual(timer.formattedTime, "0:09")
    }

    // MARK: - H:MM:SS formatting (≥ 1 hour)

    func testFormattedAtExactlyOneHour() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 3600
        XCTAssertEqual(timer.formattedTime, "1:00:00")
    }

    func testFormattedAtTwoHoursThreeMinutesFortySeven() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 2 * 3600 + 3 * 60 + 47   // 7427
        XCTAssertEqual(timer.formattedTime, "2:03:47")
    }

    func testFormattedAtOneHourOneMinuteOneSecond() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 3661
        XCTAssertEqual(timer.formattedTime, "1:01:01")
    }

    // MARK: - tick()

    func testTickIncrementsElapsedByOne() {
        var timer = SessionTimer()
        timer.tick()
        XCTAssertEqual(timer.elapsedSeconds, 1)
    }

    func testTickMultipleTimes() {
        var timer = SessionTimer()
        for _ in 0..<120 {
            timer.tick()
        }
        XCTAssertEqual(timer.elapsedSeconds, 120)
        XCTAssertEqual(timer.formattedTime, "2:00")
    }

    func testTickAcrossMinuteBoundary() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 59
        timer.tick()
        XCTAssertEqual(timer.formattedTime, "1:00")
    }

    func testTickAcrossHourBoundary() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 3599
        timer.tick()
        XCTAssertEqual(timer.formattedTime, "1:00:00")
    }

    // MARK: - reset()

    func testResetSetsElapsedToZero() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 500
        timer.reset()
        XCTAssertEqual(timer.elapsedSeconds, 0)
        XCTAssertEqual(timer.formattedTime, "0:00")
    }

    func testCanTickAfterReset() {
        var timer = SessionTimer()
        timer.elapsedSeconds = 100
        timer.reset()
        timer.tick()
        XCTAssertEqual(timer.elapsedSeconds, 1)
    }
}
