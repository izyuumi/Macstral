import ApplicationServices
import Foundation

// MARK: - FocusedTextContext

/// Lightweight context captured from the focused app before dictation starts.
///
/// Only local, user-visible text is captured. The rewrite prompt uses this to make selected-text
/// edits context-aware without needing screen capture or broad automation.
struct FocusedTextContext: Equatable {
    var appBundleIdentifier: String
    var appName: String
    var elementRole: String
    var elementTitle: String
    var selectedText: String
    var textBeforeSelection: String
    var textAfterSelection: String

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = FocusedTextContext(
        appBundleIdentifier: "unknown",
        appName: "",
        elementRole: "",
        elementTitle: "",
        selectedText: "",
        textBeforeSelection: "",
        textAfterSelection: ""
    )
}

// MARK: - TextInsertionTarget

/// The concrete focused AX element and selection range captured at hotkey down.
/// Keeping this target lets Macstral replace the original selection after the async AI rewrite
/// completes, even when the rewrite takes longer than a raw dictation insert.
final class TextInsertionTarget {
    let focusedElement: AXUIElement?
    let selectedRange: CFRange?
    let context: FocusedTextContext

    init(focusedElement: AXUIElement?, selectedRange: CFRange?, context: FocusedTextContext) {
        self.focusedElement = focusedElement
        self.selectedRange = selectedRange
        self.context = context
    }
}
