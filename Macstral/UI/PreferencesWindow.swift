import AppKit
import SwiftUI
import HotKey

final class PreferencesWindow {
    private var window: NSWindow?
    var onHotkeyChanged: ((Key, NSEvent.ModifierFlags) -> Void)?
    var onModelQualityChanged: ((ModelQuality) -> Void)?

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var view = PreferencesView { [weak self] key, mods in
            self?.onHotkeyChanged?(key, mods)
        }
        view.onModelQualityChanged = { [weak self] quality in
            self?.onModelQualityChanged?(quality)
        }
        let hosting = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
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
