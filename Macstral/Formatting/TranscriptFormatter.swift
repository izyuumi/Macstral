import Foundation

// MARK: - TranscriptFormatter

/// A pure, stateless formatter that applies Phase-1 heuristic punctuation and
/// capitalization to a *finished* transcript.
///
/// The formatter is intended to run once over a complete transcript (never over a
/// streaming partial), so every heuristic operates on the whole string. It performs
/// no I/O and reads no globals, which keeps it trivially testable and thread-safe.
///
/// Behaviour is ASCII-correct and operates on `Character`s / unicode scalars so that
/// multibyte input (including emoji) is never split or corrupted.
enum TranscriptFormatter {

    /// Applies Phase-1 heuristic formatting to a finished transcript.
    ///
    /// The pipeline, in order:
    /// 1. Trim leading/trailing whitespace and newlines.
    /// 2. Normalize whitespace: collapse 2+ spaces into one, 3+ newlines into two,
    ///    and remove spaces that sit before punctuation or a newline.
    /// 3. Capitalize the first alphabetic character of the string.
    /// 4. Capitalize the first letter of each sentence (after `.`/`!`/`?` + whitespace).
    /// 5. Ensure the result ends with terminal punctuation, appending `.` when needed.
    ///
    /// - Parameter text: The raw transcript text.
    /// - Returns: The formatted transcript, or `""` for empty/whitespace-only input.
    static func format(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var result = collapseWhitespace(trimmed)
        result = capitalizeSentences(result)
        result = ensureTerminalPunctuation(result)
        return result
    }

    // MARK: - Whitespace normalization

    /// Collapses runs of horizontal spaces, limits consecutive newlines to two,
    /// and removes spaces that immediately precede punctuation or a newline.
    private static func collapseWhitespace(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)

        var pendingSpaces = 0      // run of " " not yet emitted
        var pendingNewlines = 0    // run of "\n" not yet emitted

        func flushNewlines() {
            // A newline run supersedes any pending spaces (drop trailing spaces).
            if pendingNewlines > 0 {
                output.append(String(repeating: "\n", count: min(pendingNewlines, 2)))
                pendingNewlines = 0
                pendingSpaces = 0
            }
        }

        func flushSpaces() {
            if pendingSpaces > 0 {
                output.append(" ")
                pendingSpaces = 0
            }
        }

        for character in text {
            if character == "\n" {
                pendingNewlines += 1
                pendingSpaces = 0
            } else if character == " " || character == "\t" {
                if pendingNewlines == 0 { pendingSpaces += 1 }
                // tabs/spaces after a newline run are swallowed by flushNewlines.
            } else {
                // A real character: resolve any pending whitespace first.
                if pendingNewlines > 0 {
                    flushNewlines()
                } else if isPunctuationFollower(character) {
                    // Drop spaces before punctuation entirely.
                    pendingSpaces = 0
                } else {
                    flushSpaces()
                }
                output.append(character)
            }
        }
        // Trailing whitespace was trimmed by the caller, so nothing to flush.
        return output
    }

    /// Punctuation that should never be preceded by a space.
    private static func isPunctuationFollower(_ character: Character) -> Bool {
        switch character {
        case ",", ".", "!", "?", ";", ":": return true
        default: return false
        }
    }

    // MARK: - Capitalization

    /// Capitalizes the first alphabetic character of the string and the first letter
    /// of each sentence that follows a sentence terminator (`.`/`!`/`?`) + whitespace.
    private static func capitalizeSentences(_ text: String) -> String {
        var characters = Array(text)
        var atSentenceStart = true   // start of string behaves like a sentence start.
        var sawTerminator = false    // we have passed `.`/`!`/`?`
        var sawWhitespaceAfterTerminator = false

        for index in characters.indices {
            let character = characters[index]

            if atSentenceStart, character.isLetter {
                if character.isLowercase {
                    let upper = String(character).uppercased()
                    if let first = upper.first { characters[index] = first }
                }
                atSentenceStart = false
                sawTerminator = false
                sawWhitespaceAfterTerminator = false
                continue
            }

            if character == "." || character == "!" || character == "?" {
                sawTerminator = true
                sawWhitespaceAfterTerminator = false
            } else if sawTerminator, character == " " || character == "\n" || character == "\t" {
                sawWhitespaceAfterTerminator = true
            } else if sawTerminator, sawWhitespaceAfterTerminator {
                // First non-whitespace character after "terminator + whitespace".
                atSentenceStart = true
                sawTerminator = false
                sawWhitespaceAfterTerminator = false
                if character.isLetter {
                    if character.isLowercase {
                        let upper = String(character).uppercased()
                        if let first = upper.first { characters[index] = first }
                    }
                    atSentenceStart = false
                }
            } else if character.isLetter || character.isNumber {
                // Inside a word: reset terminator tracking.
                sawTerminator = false
                sawWhitespaceAfterTerminator = false
            }
        }
        return String(characters)
    }

    // MARK: - Terminal punctuation

    /// Sentence-terminating punctuation accepted as a valid ending.
    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    /// Closing characters allowed to trail terminal punctuation (e.g. `said it."`).
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "”", "’", "»"]

    /// Appends a period unless the string already ends in terminal punctuation,
    /// optionally followed by one or more closing quotes/parentheses.
    private static func ensureTerminalPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Walk backwards over any trailing closing characters.
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            if closers.contains(text[previous]) {
                index = previous
            } else {
                break
            }
        }

        // The character just before the (possibly empty) closer run.
        if index > text.startIndex {
            let candidate = text[text.index(before: index)]
            if terminators.contains(candidate) { return text }
        }
        return text + "."
    }
}
