import AppKit
import SwiftUI
import HotKey

final class PreferencesWindow {
    private var window: NSWindow?
    private let transcriptHistory: TranscriptHistory?
    private let licenseManager: LicenseManager
    var onHotkeyChanged: ((Key, NSEvent.ModifierFlags) -> Void)?
    var onModelQualityChanged: ((ModelQuality) -> Void)?

    init(transcriptHistory: TranscriptHistory? = nil, licenseManager: LicenseManager) {
        self.transcriptHistory = transcriptHistory
        self.licenseManager = licenseManager
    }

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var prefs = PreferencesView(
            transcriptHistory: transcriptHistory,
            licenseManager: licenseManager
        ) { [weak self] key, mods in
            self?.onHotkeyChanged?(key, mods)
        }
        prefs.onModelQualityChanged = { [weak self] quality in
            self?.onModelQualityChanged?(quality)
        }
        let hosting = NSHostingView(rootView: PreferencesTabView(general: prefs, licenseManager: licenseManager))

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Macstral Preferences"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - PreferencesTabView

/// Hosts the General settings and the License tab in a single tabbed window.
private struct PreferencesTabView: View {
    let general: PreferencesView
    let licenseManager: LicenseManager

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            LicenseView(licenseManager: licenseManager)
                .tabItem { Label("License", systemImage: "checkmark.seal") }
        }
        .frame(width: 420)
    }
}
