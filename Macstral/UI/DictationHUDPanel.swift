import AppKit
import SwiftUI

final class DictationHUDPanel: NSPanel {

    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState

        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .hudWindow]
        super.init(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        configure()
        setupContentView()
        positionAtTopCenter()
    }

    // MARK: - Configuration

    private func configure() {
        level = .floating
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        alphaValue = 0.0
    }

    private func setupContentView() {
        let hudView = DictationHUDView(appState: appState)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        let frameSize = NSSize(width: 300, height: 80)
        hostingView.frame = NSRect(origin: .zero, size: frameSize)

        contentView = hostingView
        setContentSize(frameSize)
    }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 80
        let topMargin: CGFloat = 20

        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - panelHeight - topMargin

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSPanel Overrides

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Show / Hide

    func show() {
        positionAtTopCenter()
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 1.0
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0.0
        } completionHandler: {
            self.orderOut(nil)
        }
    }
}
