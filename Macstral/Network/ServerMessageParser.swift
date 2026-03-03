import Foundation

// MARK: - ServerMessageResult

enum ServerMessageResult {
    case delta(text: String, isIncremental: Bool, firstChunkToFirstDeltaMs: Double?, feedAudioMs: Double?)
    case done(text: String, finalizeMs: Double?)
    case error(message: String)
}

// MARK: - Parser

/// Parses a JSON text frame from the Voxtral WebSocket server.
/// Returns `nil` for malformed, missing, or unrecognised message types.
nonisolated func parseServerMessage(_ text: String) -> ServerMessageResult? {
    guard
        let data = text.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let type = json["type"] as? String,
        let transcript = json["text"] as? String
    else { return nil }

    switch type {
    case "delta":
        return .delta(
            text: transcript,
            isIncremental: (json["is_incremental"] as? Bool) ?? false,
            firstChunkToFirstDeltaMs: json["first_chunk_to_first_delta_ms"] as? Double,
            feedAudioMs: json["feed_audio_ms"] as? Double
        )
    case "done":
        return .done(text: transcript, finalizeMs: json["finalize_ms"] as? Double)
    case "error":
        return .error(message: transcript)
    default:
        return nil
    }
}
