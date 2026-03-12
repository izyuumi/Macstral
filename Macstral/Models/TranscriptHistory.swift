import Foundation
import Observation

// MARK: - TranscriptEntry

/// A single completed dictation result stored in the local history log.
struct TranscriptEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let appBundleIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case date
        case appBundleIdentifier
    }

    init(id: UUID = UUID(), text: String, date: Date = Date(), appBundleIdentifier: String) {
        self.id = id
        self.text = text
        self.date = date
        self.appBundleIdentifier = appBundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        date = try container.decode(Date.self, forKey: .date)
        appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier) ?? "unknown"
    }
}

// MARK: - TranscriptHistoryRetention

struct TranscriptHistoryRetention {
    static let defaultMaxAgeDays = 30
    static let defaultMaxEntries = 500
    static let maxAgeDaysKey = "transcriptHistoryRetentionDays"
    static let maxEntriesKey = "transcriptHistoryRetentionMaxEntries"

    let maxAgeDays: Int
    let maxEntries: Int

    init(maxAgeDays: Int, maxEntries: Int) {
        self.maxAgeDays = max(1, maxAgeDays)
        self.maxEntries = max(1, maxEntries)
    }

    static func load(from defaults: UserDefaults = .standard) -> TranscriptHistoryRetention {
        let storedDays = defaults.object(forKey: maxAgeDaysKey) as? Int ?? defaultMaxAgeDays
        let storedEntries = defaults.object(forKey: maxEntriesKey) as? Int ?? defaultMaxEntries
        return TranscriptHistoryRetention(maxAgeDays: storedDays, maxEntries: storedEntries)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(maxAgeDays, forKey: Self.maxAgeDaysKey)
        defaults.set(maxEntries, forKey: Self.maxEntriesKey)
    }
}

// MARK: - TranscriptHistory

@Observable
final class TranscriptHistory {

    static let maxEntries = TranscriptHistoryRetention.defaultMaxEntries

    private(set) var entries: [TranscriptEntry] = []

    private let fileURL: URL
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        fileURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.nowProvider = nowProvider
        load()
    }

    func add(_ text: String, appBundleIdentifier: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(
            TranscriptEntry(
                text: trimmed,
                date: nowProvider(),
                appBundleIdentifier: appBundleIdentifier
            )
        )
        applyRetentionAndPersist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func applyRetentionSettings() {
        applyRetentionAndPersist()
    }

    func exportText() -> String {
        entries.map(\.text).joined(separator: "\n\n")
    }

    func matches(_ entry: TranscriptEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return entry.text.localizedCaseInsensitiveContains(trimmed)
            || entry.appBundleIdentifier.localizedCaseInsensitiveContains(trimmed)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            entries = try decoder.decode([TranscriptEntry].self, from: data)
            applyRetentionAndPersist()
        } catch {
            entries = []
            print("[TranscriptHistory] Failed to load history: \(error)")
            return
        }
    }

    private func applyRetentionAndPersist() {
        applyRetention()
        persist()
    }

    private func applyRetention() {
        let retention = TranscriptHistoryRetention.load(from: userDefaults)
        let cutoffDate = calendar.date(byAdding: .day, value: -retention.maxAgeDays, to: nowProvider()) ?? .distantPast
        entries = Array(
            entries
                .filter { $0.date >= cutoffDate }
                .suffix(retention.maxEntries)
        )
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[TranscriptHistory] Failed to persist history: \(error)")
        }
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport
            .appendingPathComponent("Macstral", isDirectory: true)
            .appendingPathComponent("dictation_history.json")
    }
}
