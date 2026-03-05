import XCTest
@testable import Macstral

@MainActor
final class TranscriptHistoryTests: XCTestCase {

    private var history: TranscriptHistory!

    override func setUp() {
        super.setUp()
        history = TranscriptHistory()
    }

    override func tearDown() {
        history = nil
        super.tearDown()
    }

    // MARK: - Adding entries

    func testEmptyOnInit() {
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testAddSingleEntry() {
        history.add("Hello world")
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "Hello world")
    }

    func testAddMultipleEntriesPreservesFIFOOrder() {
        history.add("First")
        history.add("Second")
        history.add("Third")
        XCTAssertEqual(history.entries.map(\.text), ["First", "Second", "Third"])
    }

    // MARK: - Cap at 50 entries

    func testCapAt50EntriesDropsOldest() {
        for i in 1...51 {
            history.add("Entry \(i)")
        }
        XCTAssertEqual(history.entries.count, TranscriptHistory.maxEntries)
        // The oldest ("Entry 1") should have been dropped
        XCTAssertEqual(history.entries.first?.text, "Entry 2")
        XCTAssertEqual(history.entries.last?.text, "Entry 51")
    }

    func testExactlyAtCapDoesNotDrop() {
        for i in 1...50 {
            history.add("Entry \(i)")
        }
        XCTAssertEqual(history.entries.count, 50)
        XCTAssertEqual(history.entries.first?.text, "Entry 1")
    }

    func testAddingManyEntriesNeverExceedsCap() {
        for i in 1...200 {
            history.add("Entry \(i)")
        }
        XCTAssertEqual(history.entries.count, TranscriptHistory.maxEntries)
        XCTAssertEqual(history.entries.first?.text, "Entry 151")
        XCTAssertEqual(history.entries.last?.text, "Entry 200")
    }

    // MARK: - Clear

    func testClearEmptiesAllEntries() {
        history.add("A")
        history.add("B")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClearOnEmptyHistoryIsNoop() {
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testCanAddAfterClear() {
        history.add("Before clear")
        history.clear()
        history.add("After clear")
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "After clear")
    }

    // MARK: - Entry identity

    func testEachEntryHasUniqueID() {
        for i in 1...10 {
            history.add("Entry \(i)")
        }
        let ids = history.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All entry IDs should be unique")
    }

    func testEntryTextMatchesAdded() {
        let text = "The quick brown fox"
        history.add(text)
        XCTAssertEqual(history.entries.first?.text, text)
    }

    // MARK: - Copy-to-clipboard content

    func testCopyContentMatchesEntryText() throws {
        let expected = "Dictation result for clipboard"
        history.add(expected)
        let entry = try XCTUnwrap(history.entries.first)
        // The text available for clipboard copy is the entry's text property
        XCTAssertEqual(entry.text, expected)
    }
}
