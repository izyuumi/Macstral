// AccessibilityTextInserter.swift
// Macstral
//
// Handles inserting transcribed text into the frontmost application
// using the macOS Accessibility API, with a pasteboard fallback for
// apps that don't support AXUIElement (e.g., Electron apps).
//
// Requirements: macOS 26.2+, Swift 5.0

import ApplicationServices
import AppKit

// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; all types default to MainActor.
class AccessibilityTextInserter {

    // MARK: - Public API

    /// Inserts `text` into the currently focused UI element of the frontmost
    /// application.  Tries the Accessibility API first; falls back to a
    /// pasteboard + Cmd-V simulation when AX is unavailable or unsupported.
    func insertText(_ text: String) {
        if tryAccessibilityInsertion(text) {
            return
        }
        pasteboardFallback(text)
    }

    // MARK: - Accessibility permission helpers

    /// Returns `true` when the process is already trusted for Accessibility.
    static func isAccessibilityEnabled() -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompts the user to grant Accessibility permission via System Settings.
    static func requestAccessibilityPermission() {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - AXUIElement insertion

    /// Attempts to set the focused element's value via the Accessibility API.
    /// - Returns: `true` on success, `false` if any step fails.
    @discardableResult
    private func tryAccessibilityInsertion(_ text: String) -> Bool {
        // 1. Obtain the PID of the frontmost application.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }

        // 2. Create an AXUIElement representing the application.
        let appElement = AXUIElementCreateApplication(pid)

        // 3. Retrieve the currently focused UI element.
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedResult == .success, let focusedElementRef = focusedElementRef else {
            return false
        }

        // Safe cast: the returned CFTypeRef is an AXUIElement.
        let focusedElement = focusedElementRef as! AXUIElement // swiftlint:disable:this force_cast

        // 4. Read the current value of the focused element.
        var currentValueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValueRef
        )

        let currentText: String
        if valueResult == .success, let existing = currentValueRef as? String {
            currentText = existing
        } else {
            // Element may not expose a value (e.g., it is not a text field).
            // Still attempt to append — some elements accept a set even without
            // a readable value; treat current text as empty.
            currentText = ""
        }

        // 5. Build the new value by appending the transcribed text.
        let newValue = currentText + text

        // 6. Write the new value back to the element.
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        return setResult == .success
    }

    // MARK: - Pasteboard + Cmd-V fallback

    /// Copies `text` to the general pasteboard, simulates Cmd-V to paste it,
    /// then restores the previous pasteboard contents after a short delay.
    private func pasteboardFallback(_ text: String) {
        let pasteboard = NSPasteboard.general

        // 1. Save the current pasteboard contents so they can be restored.
        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        // 2. Place the transcribed text onto the pasteboard.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Simulate Cmd-V using CGEvent.
        let keyDownEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(9), // 'v'
            keyDown: true
        )
        keyDownEvent?.flags = .maskCommand
        keyDownEvent?.post(tap: .cghidEventTap)

        let keyUpEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(9), // 'v'
            keyDown: false
        )
        keyUpEvent?.flags = .maskCommand
        keyUpEvent?.post(tap: .cghidEventTap)

        // 4. Restore the previous pasteboard contents after a short delay so
        //    the paste action has time to complete before we clear the board.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
    }
}
