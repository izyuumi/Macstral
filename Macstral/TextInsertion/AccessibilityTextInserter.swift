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
        insertText(text, into: captureTargetContext())
    }

    /// Inserts or replaces text in the captured target. If `target` includes a selected text range,
    /// that range is replaced; if the range is a cursor location, text is inserted there.
    func insertText(_ text: String, into target: TextInsertionTarget?) {
        if let target, tryAccessibilityInsertion(text, target: target) {
            return
        }
        pasteboardFallback(text)
    }

    /// Captures the focused text target and the local context around its selection/cursor.
    func captureTargetContext() -> TextInsertionTarget {
        let app = NSWorkspace.shared.frontmostApplication
        let appBundleID = app?.bundleIdentifier ?? "unknown"
        let appName = app?.localizedName ?? ""

        guard let pid = app?.processIdentifier,
              let focusedElement = focusedElement(for: pid)
        else {
            return TextInsertionTarget(
                focusedElement: nil,
                selectedRange: nil,
                context: FocusedTextContext(
                    appBundleIdentifier: appBundleID,
                    appName: appName,
                    elementRole: "",
                    elementTitle: "",
                    selectedText: "",
                    textBeforeSelection: "",
                    textAfterSelection: ""
                )
            )
        }

        let value = Self.copyStringAttribute(kAXValueAttribute, from: focusedElement) ?? ""
        let selectedRange = Self.copySelectedTextRange(from: focusedElement)
        let selectedText = Self.selectedText(
            from: focusedElement,
            value: value,
            selectedRange: selectedRange
        )
        let surrounding = Self.surroundingText(value: value, selectedRange: selectedRange)
        let context = FocusedTextContext(
            appBundleIdentifier: appBundleID,
            appName: appName,
            elementRole: Self.copyStringAttribute(kAXRoleAttribute, from: focusedElement) ?? "",
            elementTitle: Self.copyStringAttribute(kAXTitleAttribute, from: focusedElement) ?? "",
            selectedText: selectedText,
            textBeforeSelection: surrounding.before,
            textAfterSelection: surrounding.after
        )
        return TextInsertionTarget(
            focusedElement: focusedElement,
            selectedRange: selectedRange,
            context: context
        )
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

    /// Attempts to set the captured focused element's value via the Accessibility API.
    /// - Returns: `true` on success, `false` if any step fails.
    @discardableResult
    private func tryAccessibilityInsertion(_ text: String, target: TextInsertionTarget) -> Bool {
        guard let focusedElement = target.focusedElement else { return false }

        // Prefer range replacement/insertion when the element exposes text value + selection.
        if replaceValue(text, in: focusedElement, selectedRange: target.selectedRange) {
            return true
        }

        // Some controls accept direct selected-text replacement even if they do not expose a
        // mutable full value. This is best-effort and falls through to pasteboard if unsupported.
        let selectedSetResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return selectedSetResult == .success
    }

    /// Attempts to set the focused element's value via AX by replacing the captured range.
    @discardableResult
    private func replaceValue(_ text: String, in focusedElement: AXUIElement, selectedRange: CFRange?) -> Bool {
        guard let currentText = Self.copyStringAttribute(kAXValueAttribute, from: focusedElement) else {
            return false
        }

        let range = selectedRange ?? CFRange(location: (currentText as NSString).length, length: 0)
        guard range.location >= 0, range.length >= 0 else { return false }
        let nsText = currentText as NSString
        guard range.location <= nsText.length,
              range.location + range.length <= nsText.length
        else { return false }

        let newValue = nsText.replacingCharacters(
            in: NSRange(location: range.location, length: range.length),
            with: text
        )
        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )
        guard setResult == .success else { return false }

        setCursor(afterInsertedText: text, originalRange: range, in: focusedElement)
        return true
    }

    private func setCursor(afterInsertedText text: String, originalRange: CFRange, in focusedElement: AXUIElement) {
        var newRange = CFRange(
            location: originalRange.location + (text as NSString).length,
            length: 0
        )
        guard let rangeValue = AXValueCreate(.cfRange, &newRange) else { return }
        _ = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
    }

    private func focusedElement(for pid: pid_t) -> AXUIElement? {
        // 1. Create an AXUIElement representing the application.
        let appElement = AXUIElementCreateApplication(pid)

        // 2. Retrieve the currently focused UI element.
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedResult == .success, let focusedElementRef = focusedElementRef else {
            return nil
        }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = focusedElementRef as! AXUIElement // swiftlint:disable:this force_cast
        return focusedElement
    }

    private static func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard result == .success else { return nil }
        return valueRef as? String
    }

    private static func copySelectedTextRange(from element: AXUIElement) -> CFRange? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &valueRef
        )
        guard result == .success, let valueRef else { return nil }
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        let value = valueRef as! AXValue // swiftlint:disable:this force_cast
        guard AXValueGetType(value) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private static func selectedText(
        from element: AXUIElement,
        value: String,
        selectedRange: CFRange?
    ) -> String {
        if let selected = copyStringAttribute(kAXSelectedTextAttribute, from: element), !selected.isEmpty {
            return selected
        }
        guard let selectedRange, selectedRange.length > 0 else { return "" }
        return substring(value, range: selectedRange) ?? ""
    }

    private static func surroundingText(value: String, selectedRange: CFRange?) -> (before: String, after: String) {
        let nsText = value as NSString
        let range = selectedRange ?? CFRange(location: nsText.length, length: 0)
        guard range.location >= 0, range.location <= nsText.length else { return ("", "") }

        let beforeStart = max(0, range.location - 1_200)
        let beforeLength = range.location - beforeStart
        let afterStart = min(nsText.length, range.location + max(0, range.length))
        let afterLength = min(1_200, nsText.length - afterStart)
        let before = nsText.substring(with: NSRange(location: beforeStart, length: beforeLength))
        let after = nsText.substring(with: NSRange(location: afterStart, length: afterLength))
        return (before, after)
    }

    private static func substring(_ value: String, range: CFRange) -> String? {
        let nsText = value as NSString
        guard range.location >= 0,
              range.length >= 0,
              range.location <= nsText.length,
              range.location + range.length <= nsText.length
        else { return nil }
        return nsText.substring(with: NSRange(location: range.location, length: range.length))
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
