import Foundation
import Observation

// MARK: - TranscriptEntry

/// A single completed dictation result stored in the session history.
struct TranscriptEntry: Equatable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id   = id
        self.text = text
        self.date = date
    }
}

// MARK: - TranscriptHistory

/// Maintains an ordered list of completed dictation entries for the current session.
///
/// Capped at `maxEntries` — when the limit is exceeded the oldest entry is dropped (FIFO).
/// Designed to be observable from SwiftUI and testable without AppState dependencies.
@Observable
final class TranscriptHistory {

    // MARK: Constants

    /// Maximum number of entries retained. The oldest is discarded when this is exceeded.
    static let maxEntries = 50

    // MARK: State

    private(set) var entries: [TranscriptEntry] = []

    // MARK: Mutations

    /// Append a new entry. Trims the oldest entry when the cap is reached.
    func add(_ text: String) {
        let entry = TranscriptEntry(text: text)
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst()
        }
    }

    /// Remove all entries from the current session.
    func clear() {
        entries.removeAll()
    }

    // MARK: Export

    /// Returns all entries joined by double newlines — suitable for saving to a .txt file.
    /// Returns an empty string (never crashes) when the history is empty.
    func exportText() -> String {
        entries.map(\.text).joined(separator: "\n\n")
    }
}
