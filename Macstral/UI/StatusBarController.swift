import AppKit

final class StatusBarController {

    private var statusItem: NSStatusItem
    private var statusMenuItem: NSMenuItem
    private let recordAudioNotesItem = NSMenuItem()
    var onPreferencesRequested: (() -> Void)?
    var onHistoryRequested: (() -> Void)?
    var onPasteLastTranscriptionRequested: (() -> Void)?
    var onAudioNotesRequested: (() -> Void)?
    var onToggleAudioRecordingRequested: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusMenuItem = NSMenuItem()

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

        let historyItem = NSMenuItem(
            title: "History",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let pasteLastTranscriptionItem = NSMenuItem(
            title: "Paste Last Transcription",
            action: #selector(pasteLastTranscription),
            keyEquivalent: ""
        )
        pasteLastTranscriptionItem.target = self
        menu.addItem(pasteLastTranscriptionItem)

        menu.addItem(.separator())

        // Audio Notes: record system audio → transcript → AI notes.
        recordAudioNotesItem.title = "Record System Audio"
        recordAudioNotesItem.action = #selector(toggleAudioRecording)
        recordAudioNotesItem.target = self
        menu.addItem(recordAudioNotesItem)

        let audioNotesItem = NSMenuItem(
            title: "Audio Notes…",
            action: #selector(openAudioNotes),
            keyEquivalent: ""
        )
        audioNotesItem.target = self
        menu.addItem(audioNotesItem)

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

    @objc private func openPreferences() {
        onPreferencesRequested?()
    }

    @objc private func openHistory() {
        onHistoryRequested?()
    }

    @objc private func pasteLastTranscription() {
        onPasteLastTranscriptionRequested?()
    }

    @objc private func openAudioNotes() {
        onAudioNotesRequested?()
    }

    @objc private func toggleAudioRecording() {
        onToggleAudioRecordingRequested?()
    }

    // MARK: - Public Interface

    /// Reflects the Audio Notes pipeline state in the record menu item's title and enablement.
    func updateAudioNotesStatus(_ status: AudioNotesStatus) {
        switch status {
        case .idle, .error:
            recordAudioNotesItem.title = "Record System Audio"
            recordAudioNotesItem.isEnabled = true
        case .recording:
            recordAudioNotesItem.title = "Stop Recording"
            recordAudioNotesItem.isEnabled = true
        case .transcribing:
            recordAudioNotesItem.title = "Transcribing…"
            recordAudioNotesItem.isEnabled = false
        case .generatingNotes:
            recordAudioNotesItem.title = "Generating Notes…"
            recordAudioNotesItem.isEnabled = false
        }
    }

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
