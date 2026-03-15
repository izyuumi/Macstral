import XCTest
@testable import Macstral

/// Tests for TranscriptHistory.exportText() — the logic that generates
/// the content written to a .txt file via NSSavePanel.
@MainActor
final class ExportTests: XCTestCase {

    private var history: TranscriptHistory!
    private var tempDirectoryURL: URL!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        fileURL = tempDirectoryURL.appendingPathComponent("history.json")
        defaultsSuiteName = "ExportTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        TranscriptHistoryRetention(maxAgeDays: 30, maxEntries: 500).save(to: defaults)
        history = TranscriptHistory(fileURL: fileURL, userDefaults: defaults)
    }

    override func tearDown() {
        history = nil
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        fileURL = nil
        tempDirectoryURL = nil
        super.tearDown()
    }

    // MARK: - Empty history

    func testExportEmptyHistoryReturnsEmptyString() {
        XCTAssertEqual(history.exportText(), "")
    }

    func testExportEmptyHistoryNeverCrashes() {
        _ = history.exportText()
    }

    // MARK: - Single entry

    func testExportSingleEntryEqualsItsText() {
        history.add("Only entry", appBundleIdentifier: "app")
        XCTAssertEqual(history.exportText(), "Only entry")
    }

    func testExportSingleEntryHasNoTrailingNewline() {
        history.add("No trailing newline", appBundleIdentifier: "app")
        let output = history.exportText()
        XCTAssertFalse(output.hasSuffix("\n\n"))
    }

    // MARK: - Multiple entries

    func testExportTwoEntriesJoinedByDoubleNewline() {
        history.add("First line", appBundleIdentifier: "app")
        history.add("Second line", appBundleIdentifier: "app")
        XCTAssertEqual(history.exportText(), "First line\n\nSecond line")
    }

    func testExportThreeEntriesJoinedByDoubleNewlines() {
        history.add("Alpha", appBundleIdentifier: "app")
        history.add("Beta", appBundleIdentifier: "app")
        history.add("Gamma", appBundleIdentifier: "app")
        XCTAssertEqual(history.exportText(), "Alpha\n\nBeta\n\nGamma")
    }

    func testExportPreservesOrder() {
        let texts = ["First", "Second", "Third", "Fourth", "Fifth"]
        texts.forEach { history.add($0, appBundleIdentifier: "app") }
        let exported = history.exportText()
        let parts = exported.components(separatedBy: "\n\n")
        XCTAssertEqual(parts, texts)
    }

    // MARK: - Edge cases

    func testExportPreservesInternalNewlines() {
        history.add("Line one\nLine two", appBundleIdentifier: "app")
        history.add("Other entry", appBundleIdentifier: "app")
        let exported = history.exportText()
        XCTAssertTrue(exported.contains("Line one\nLine two"))
    }

    func testExportEmptyEntryText() {
        history.add("", appBundleIdentifier: "app")
        XCTAssertEqual(history.exportText(), "")
    }

    func testExportCountMatchesNumberOfSeparators() {
        let n = 5
        for i in 1...n { history.add("Entry \(i)", appBundleIdentifier: "app") }
        let separatorCount = history.exportText()
            .components(separatedBy: "\n\n")
            .count - 1
        XCTAssertEqual(separatorCount, n - 1)
    }
}
