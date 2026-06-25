import Foundation

// MARK: - AIWritingTask

enum AIWritingTask: String, Equatable {
    case dictation
    case editSelection
}

// MARK: - AIWritingRequest

struct AIWritingRequest: Equatable {
    var rawTranscript: String
    var task: AIWritingTask
    var context: FocusedTextContext
    var languageCode: String?
}

// MARK: - AIWritingIntentClassifier

enum AIWritingIntentClassifier {
    private static let editPhrases = [
        "make this", "rewrite", "revise", "edit this", "fix this", "clean this",
        "shorter", "longer", "more polite", "more professional", "friendlier",
        "translate", "summarize", "turn this into", "convert this", "bullet",
        "write a reply", "reply to", "respond to", "answer this", "improve this",
        "change this", "formal", "casual", "tone"
    ]

    static func classify(rawTranscript: String, context: FocusedTextContext) -> AIWritingTask {
        guard context.hasSelection else { return .dictation }
        let normalized = rawTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .dictation }
        if editPhrases.contains(where: { normalized.contains($0) }) {
            return .editSelection
        }
        return .dictation
    }
}

// MARK: - AIWritingPromptBuilder

enum AIWritingPromptBuilder {
    static let instructions = """
    You are Macstral's writing layer. Convert messy spoken input into finished writing.

    Rules:
    - Output only the final text. No preamble, labels, quotes, or markdown fences unless the user asked for markdown.
    - Preserve the user's intended meaning. Do not invent facts, names, dates, commitments, links, or external context.
    - Remove filler words, repetitions, false starts, verbal corrections, and speech artifacts.
    - Keep the result natural and human. Avoid generic AI phrasing.
    - Use the focused app and selected-text context only to disambiguate tone, format, and reply direction.
    - If editing selected text, follow the spoken command and return the replacement text only.
    - If the command asks for a reply, write only the reply, based strictly on the selected text.
    """

    static func input(for request: AIWritingRequest) -> String {
        var sections: [String] = []
        sections.append("Task: \(request.task == .editSelection ? "edit selected text" : "polish dictated text")")

        let appSummary = [
            request.context.appName,
            request.context.appBundleIdentifier,
            request.context.elementRole,
            request.context.elementTitle,
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        if !appSummary.isEmpty {
            sections.append("Focused app/context:\n\(appSummary)")
        }

        if let languageCode = request.languageCode, !languageCode.isEmpty, languageCode != "auto" {
            sections.append("Requested transcription language: \(languageCode)")
        }

        if !request.context.textBeforeSelection.isEmpty {
            sections.append("Text before selection:\n\(request.context.textBeforeSelection)")
        }
        if request.context.hasSelection {
            sections.append("Selected text:\n\(request.context.selectedText)")
        }
        if !request.context.textAfterSelection.isEmpty {
            sections.append("Text after selection:\n\(request.context.textAfterSelection)")
        }

        switch request.task {
        case .dictation:
            sections.append("Raw spoken dictation:\n\(request.rawTranscript)")
            sections.append("Return the polished text to insert at the cursor or replace the current selection.")
        case .editSelection:
            sections.append("Spoken edit command:\n\(request.rawTranscript)")
            sections.append("Return only the replacement for the selected text.")
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    static func fallbackText(for request: AIWritingRequest) -> String {
        switch request.task {
        case .dictation:
            return TranscriptFormatter.format(request.rawTranscript)
        case .editSelection:
            // Avoid replacing a user's selected text with "make this shorter" when every AI path
            // fails. A no-op replacement is the least surprising failure mode.
            return request.context.selectedText
        }
    }
}
