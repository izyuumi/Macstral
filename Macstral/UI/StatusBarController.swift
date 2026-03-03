import AppKit

final class StatusBarController {

    private var statusItem: NSStatusItem
    private var statusMenuItem: NSMenuItem
    var onPreferencesRequested: (() -> Void)?

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
