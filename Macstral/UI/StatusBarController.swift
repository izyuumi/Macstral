import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem
    private var statusMenuItem: NSMenuItem
    private var historyMenuItem: NSMenuItem

    // MARK: - Callbacks

    var onPreferencesRequested: (() -> Void)?
    var onPasteLastTranscriptionRequested: (() -> Void)?

    /// Called when the History submenu opens; returns entries newest-first.
    var historyProvider: (() -> [String])?

    /// Called when the user clicks a history entry (full text for clipboard).
    var onHistoryItemCopyRequested: ((String) -> Void)?

    /// Called when the user clicks "Clear History".
    var onClearHistoryRequested: (() -> Void)?

    /// Called when the user clicks "Save Transcript…".
    var onSaveTranscriptRequested: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusMenuItem = NSMenuItem()
        historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")

        super.init()

        setupButton()
        setupMenu()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "Macstral Dictation"
        )
        button.image?.isTemplate = true
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Status line (informational, disabled)
        statusMenuItem.title = "Status: Stopped"
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Preferences item
        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Paste Last Transcription
        let pasteLastItem = NSMenuItem(
            title: "Paste Last Transcription",
            action: #selector(pasteLastTranscription),
            keyEquivalent: ""
        )
        pasteLastItem.target = self
        menu.addItem(pasteLastItem)

        // History submenu
        let historySubmenu = NSMenu(title: "History")
        historySubmenu.delegate = self
        historyMenuItem.submenu = historySubmenu
        menu.addItem(historyMenuItem)

        menu.addItem(.separator())

        // Quit item
        let quitItem = NSMenuItem(
            title: "Quit Macstral",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Only rebuild when the history submenu is opening.
        guard menu === historyMenuItem.submenu else { return }
        rebuildHistorySubmenu(menu)
    }

    private func rebuildHistorySubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let entries = historyProvider?() ?? []

        if entries.isEmpty {
            let empty = NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, text) in entries.enumerated() {
                let label = text.count > 80
                    ? String(text.prefix(80)) + "…"
                    : text
                let item = NSMenuItem(
                    title: "\(index + 1). \(label)",
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = text
                menu.addItem(item)
            }

            menu.addItem(.separator())

            let saveItem = NSMenuItem(
                title: "Save Transcript…",
                action: #selector(saveTranscript),
                keyEquivalent: ""
            )
            saveItem.target = self
            menu.addItem(saveItem)

            let clearItem = NSMenuItem(
                title: "Clear History",
                action: #selector(clearHistory),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    // MARK: - Actions

    @objc private func openPreferences() {
        onPreferencesRequested?()
    }

    @objc private func pasteLastTranscription() {
        onPasteLastTranscriptionRequested?()
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        onHistoryItemCopyRequested?(text)
    }

    @objc private func clearHistory() {
        onClearHistoryRequested?()
    }

    @objc private func saveTranscript() {
        onSaveTranscriptRequested?()
    }

    // MARK: - Public Interface

    func updateStatus(_ status: BackendStatus) {
        let label: String
        switch status {
        case .stopped:
            label = "Stopped"
        case .starting:
            label = "Starting..."
        case .ready:
            label = "Ready"
        case .error(let message):
            label = "Error: \(message)"
        }
        statusMenuItem.title = "Status: \(label)"
    }
}
