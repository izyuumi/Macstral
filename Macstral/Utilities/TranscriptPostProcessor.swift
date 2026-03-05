import Foundation

// MARK: - TranscriptPostProcessor

/// Applies heuristic formatting rules to a completed transcript.
///
/// This runs **only on the final transcript** (the `done` event), never on
/// streaming deltas, so there are no mid-word cursor jumps.
///
/// Rules (applied in order):
/// 1. Strip leading/trailing whitespace
/// 2. Capitalize the first Unicode scalar if it is a lowercase letter
/// 3. Append a period if the text does not already end with terminal punctuation (`.`, `!`, `?`)
///
/// All rules are no-ops on empty or whitespace-only input.
enum TranscriptPostProcessor {

    /// Terminal punctuation characters that suppress period insertion.
    private static let terminalPunctuation: Set<Character> = [".", "!", "?", "…"]

    /// Apply all formatting rules and return the result.
    ///
    /// - Parameters:
    ///   - text: Raw transcript text from the STT engine.
    ///   - enabled: When `false`, the text is returned unchanged (after trimming).
    /// - Returns: Formatted transcript ready for insertion and history.
    static func process(_ text: String, enabled: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, enabled else { return trimmed }

        let capitalized = capitalizeFirst(trimmed)
        let punctuated  = addTerminalPeriod(capitalized)
        return punctuated
    }

    // MARK: - Private helpers

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.unicodeScalars.first else { return text }
        // Only capitalize if the first character is a cased letter in lowercase
        guard CharacterSet.lowercaseLetters.contains(first) else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func addTerminalPeriod(_ text: String) -> String {
        guard let last = text.last else { return text }
        guard !terminalPunctuation.contains(last) else { return text }
        return text + "."
    }
}
