import XCTest
@testable import Macstral

@MainActor
final class TranscriptHistoryTests: XCTestCase {

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
        defaultsSuiteName = "TranscriptHistoryTests.\(UUID().uuidString)"
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

    // MARK: - Adding entries

    func testEmptyOnInit() {
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testAddSingleEntry() {
        history.add("Hello world", appBundleIdentifier: "com.apple.TextEdit")
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "Hello world")
        XCTAssertEqual(history.entries.first?.appBundleIdentifier, "com.apple.TextEdit")
    }

    func testAddMultipleEntriesPreservesFIFOOrder() {
        history.add("First", appBundleIdentifier: "app")
        history.add("Second", appBundleIdentifier: "app")
        history.add("Third", appBundleIdentifier: "app")
        XCTAssertEqual(history.entries.map(\.text), ["First", "Second", "Third"])
    }

    // MARK: - Retention

    func testCapAtConfiguredEntriesDropsOldest() {
        TranscriptHistoryRetention(maxAgeDays: 30, maxEntries: 3).save(to: defaults)
        history = TranscriptHistory(fileURL: fileURL, userDefaults: defaults)

        for i in 1...4 {
            history.add("Entry \(i)", appBundleIdentifier: "app")
        }

        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.entries.map(\.text), ["Entry 2", "Entry 3", "Entry 4"])
    }

    func testApplyRetentionDropsExpiredEntries() {
        let now = Date()
        let staleDate = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        let recentDate = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let seeded = [
            TranscriptEntry(text: "Old", date: staleDate, appBundleIdentifier: "old.app"),
            TranscriptEntry(text: "Recent", date: recentDate, appBundleIdentifier: "recent.app")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode(seeded)
        try? data?.write(to: fileURL)

        TranscriptHistoryRetention(maxAgeDays: 30, maxEntries: 500).save(to: defaults)
        history = TranscriptHistory(fileURL: fileURL, userDefaults: defaults, nowProvider: { now })

        XCTAssertEqual(history.entries.map(\.text), ["Recent"])
    }

    // MARK: - Clear

    func testClearEmptiesAllEntries() {
        history.add("A", appBundleIdentifier: "app")
        history.add("B", appBundleIdentifier: "app")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testCanAddAfterClear() {
        history.add("Before clear", appBundleIdentifier: "app")
        history.clear()
        history.add("After clear", appBundleIdentifier: "app")
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "After clear")
    }

    // MARK: - Entry identity

    func testEachEntryHasUniqueID() {
        for i in 1...10 {
            history.add("Entry \(i)", appBundleIdentifier: "app")
        }
        let ids = history.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEntryTextMatchesAdded() {
        let text = "The quick brown fox"
        history.add(text, appBundleIdentifier: "com.apple.TextEdit")
        XCTAssertEqual(history.entries.first?.text, text)
    }

    func testMatchesSearchAcrossTextAndBundleIdentifier() throws {
        history.add("Draft reply", appBundleIdentifier: "com.apple.mail")
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(history.matches(entry, query: "reply"))
        XCTAssertTrue(history.matches(entry, query: "mail"))
        XCTAssertFalse(history.matches(entry, query: "safari"))
    }

    func testPersistsEntriesToDisk() {
        history.add("Persist me", appBundleIdentifier: "com.apple.Notes")
        let reloaded = TranscriptHistory(fileURL: fileURL, userDefaults: defaults)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.text, "Persist me")
        XCTAssertEqual(reloaded.entries.first?.appBundleIdentifier, "com.apple.Notes")
    }

    func testLoadsLegacyEntriesWithoutBundleIdentifier() throws {
        let legacyJSON = """
        [
          {
            "id": "\(UUID())",
            "text": "Legacy entry",
            "date": "2026-03-12T00:00:00Z"
          }
        ]
        """
        try legacyJSON.data(using: .utf8)?.write(to: fileURL)

        // Pin "now" close to the legacy entry's date so the 30-day retention window does not
        // age it out — keeps this test deterministic regardless of the wall-clock date it runs.
        let fixedNow = ISO8601DateFormatter().date(from: "2026-03-13T00:00:00Z")!
        let reloaded = TranscriptHistory(fileURL: fileURL, userDefaults: defaults, nowProvider: { fixedNow })

        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.text, "Legacy entry")
        XCTAssertEqual(reloaded.entries.first?.appBundleIdentifier, "unknown")
    }
}
