import Foundation

// MARK: - ServerMessageResult

enum ServerMessageResult {
    case done(text: String, finalizeMs: Double?)
    case error(message: String)
}

// MARK: - Parser

/// Parses a JSON text frame from the Granite WebSocket server.
/// Returns `nil` for malformed, missing, or unrecognised message types.
nonisolated func parseServerMessage(_ text: String) -> ServerMessageResult? {
    guard
        let data = text.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let type = json["type"] as? String,
        let transcript = json["text"] as? String
    else { return nil }

    switch type {
    case "done":
        return .done(text: transcript, finalizeMs: json["finalize_ms"] as? Double)
    case "error":
        return .error(message: transcript)
    default:
        return nil
    }
}
