import Foundation

// MARK: - AudioNote

/// A single completed audio recording with its transcript and generated AI notes.
struct AudioNote: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let date: Date
    var transcript: String
    var notes: String          // markdown; empty until notes generated
    var durationSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case transcript
        case notes
        case durationSeconds
    }

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        transcript: String,
        notes: String = "",
        durationSeconds: Double
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.transcript = transcript
        self.notes = notes
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        date = try container.decode(Date.self, forKey: .date)
        transcript = try container.decode(String.self, forKey: .transcript)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
    }
}
