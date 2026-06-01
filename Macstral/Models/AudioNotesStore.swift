import Foundation
import Observation

// MARK: - AudioNotesStore

@Observable
final class AudioNotesStore {

    private(set) var notes: [AudioNote] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    func add(_ note: AudioNote) {
        notes.append(note)
        persist()
    }

    func update(_ note: AudioNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        persist()
    }

    func remove(_ note: AudioNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    func clear() {
        notes.removeAll()
        persist()
    }

    func matches(_ note: AudioNote, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return note.title.localizedCaseInsensitiveContains(trimmed)
            || note.transcript.localizedCaseInsensitiveContains(trimmed)
            || note.notes.localizedCaseInsensitiveContains(trimmed)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            notes = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            notes = try decoder.decode([AudioNote].self, from: data)
        } catch {
            notes = []
            print("[AudioNotesStore] Failed to load audio notes: \(error)")
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AudioNotesStore] Failed to persist audio notes: \(error)")
        }
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport
            .appendingPathComponent("Macstral", isDirectory: true)
            .appendingPathComponent("audio_notes.json")
    }
}
