import XCTest
@testable import Macstral

/// Tests for TranscriptHistory.exportText() — the logic that generates
/// the content written to a .txt file via NSSavePanel.
@MainActor
final class ExportTests: XCTestCase {

    private var history: TranscriptHistory!

    override func setUp() {
        super.setUp()
        history = TranscriptHistory()
    }

    override func tearDown() {
        history = nil
        super.tearDown()
    }

    // MARK: - Empty history

    func testExportEmptyHistoryReturnsEmptyString() {
        XCTAssertEqual(history.exportText(), "")
    }

    func testExportEmptyHistoryNeverCrashes() {
        // Calling exportText() on empty history must not throw or crash
        _ = history.exportText()
    }

    // MARK: - Single entry

    func testExportSingleEntryEqualsItsText() {
        history.add("Only entry")
        XCTAssertEqual(history.exportText(), "Only entry")
    }

    func testExportSingleEntryHasNoTrailingNewline() {
        history.add("No trailing newline")
        let output = history.exportText()
        XCTAssertFalse(output.hasSuffix("\n\n"), "Single-entry export should not end with double newline")
    }

    // MARK: - Multiple entries

    func testExportTwoEntriesJoinedByDoubleNewline() {
        history.add("First line")
        history.add("Second line")
        XCTAssertEqual(history.exportText(), "First line\n\nSecond line")
    }

    func testExportThreeEntriesJoinedByDoubleNewlines() {
        history.add("Alpha")
        history.add("Beta")
        history.add("Gamma")
        XCTAssertEqual(history.exportText(), "Alpha\n\nBeta\n\nGamma")
    }

    func testExportPreservesOrder() {
        let texts = ["First", "Second", "Third", "Fourth", "Fifth"]
        texts.forEach { history.add($0) }
        let exported = history.exportText()
        let parts = exported.components(separatedBy: "\n\n")
        XCTAssertEqual(parts, texts, "Export must preserve FIFO order")
    }

    // MARK: - Edge cases

    func testExportPreservesInternalNewlines() {
        history.add("Line one\nLine two")
        history.add("Other entry")
        let exported = history.exportText()
        XCTAssertTrue(exported.contains("Line one\nLine two"))
    }

    func testExportEmptyEntryText() {
        history.add("")
        XCTAssertEqual(history.exportText(), "")
    }

    func testExportCountMatchesNumberOfSeparators() {
        let n = 5
        for i in 1...n { history.add("Entry \(i)") }
        let separatorCount = history.exportText()
            .components(separatedBy: "\n\n")
            .count - 1
        XCTAssertEqual(separatorCount, n - 1,
                       "n entries should be joined by n-1 double-newline separators")
    }
}
