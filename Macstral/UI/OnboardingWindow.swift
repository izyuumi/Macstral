import AppKit
import SwiftUI

final class OnboardingWindow: NSWindow {

    private var appState: AppState
    private var onPermissionStateChangedCallback: (() -> Void)?
    private var onCompleteCallback: (() -> Void)?

    init(
        appState: AppState,
        onPermissionStateChanged: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.onPermissionStateChangedCallback = onPermissionStateChanged
        self.onCompleteCallback = onComplete

        let windowSize = NSSize(width: 450, height: 470)
        let styleMask: NSWindow.StyleMask = [.titled]

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
            onPermissionStateChanged: { [weak self] in
                self?.onPermissionStateChangedCallback?()
            },
            onComplete: { [weak self] in
                self?.onCompleteCallback?()
                self?.close()
            }
        )
        let hostingController = NSHostingController(rootView: onboardingView)
        contentViewController = hostingController
        setContentSize(NSSize(width: 450, height: 470))
    }

    // MARK: - Public Interface

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
