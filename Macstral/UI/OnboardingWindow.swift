import AppKit
import SwiftUI

final class OnboardingWindow: NSWindow {

    private var appState: AppState
    private var onCompleteCallback: (() -> Void)?

    init(appState: AppState, onComplete: (() -> Void)? = nil) {
        self.appState = appState
        self.onCompleteCallback = onComplete

        let windowSize = NSSize(width: 450, height: 350)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        configure()
        setupContentView()
        center()
    }

    // MARK: - Configuration

    private func configure() {
        title = "Welcome to Macstral"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
    }

    private func setupContentView() {
        let onboardingView = OnboardingView(
            appState: appState,
            onComplete: { [weak self] in
                self?.onCompleteCallback?()
                self?.close()
            }
        )
        let hostingController = NSHostingController(rootView: onboardingView)
        contentViewController = hostingController
        setContentSize(NSSize(width: 450, height: 350))
    }

    // MARK: - Public Interface

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
