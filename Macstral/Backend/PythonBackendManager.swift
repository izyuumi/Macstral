import Foundation

// MARK: - PythonBackendManager

/// Preserves the existing backend manager interface, but the app now uses an in-process
/// transcription pipeline and no longer launches an external server.
@MainActor
final class PythonBackendManager {

    // MARK: - Public Callbacks

    /// Called whenever the backend status changes.
    var onStatusChange: ((BackendStatus) -> Void)?

    /// Called with backend lifecycle log messages.
    var onLog: ((String) -> Void)?

    // MARK: - Private State

    private var isActive = false

    // MARK: - Computed Properties

    /// `true` while the in-process transcription pipeline is marked active.
    var isRunning: Bool {
        isActive
    }

    // MARK: - Start

    /// Marks the in-app transcription engine as active.
    func start() {
        guard !isRunning else {
            log("[PythonBackendManager] start() called but the in-app engine is already active.")
            return
        }

        isActive = true
        notifyStatus(.starting)
        log("[PythonBackendManager] External backend disabled. Using the built-in speech engine.")
    }

    // MARK: - Stop

    /// Marks the in-app transcription engine as inactive.
    func stop() {
        guard isRunning else {
            log("[PythonBackendManager] stop() called but the in-app engine is already inactive.")
            return
        }

        isActive = false
        log("[PythonBackendManager] In-app speech engine stopped.")
        notifyStatus(.stopped)
    }

    // MARK: - Health Check

    /// Returns `true` while the in-app speech engine is active.
    func checkHealth() async -> Bool {
        return isRunning
    }

    // MARK: - Wait For Ready

    /// Publishes readiness immediately because there is no external service to wait for.
    func waitForReady() async {
        guard isRunning else {
            let message = "[PythonBackendManager] Cannot mark the in-app engine ready because it is not active."
            log(message)
            notifyStatus(.error(message))
            return
        }

        log("[PythonBackendManager] In-app speech engine is ready.")
        notifyStatus(.ready)
    }

    /// Forwards `status` to `onStatusChange` and logs the transition.
    private func notifyStatus(_ status: BackendStatus) {
        log("[PythonBackendManager] Status → \(status)")
        onStatusChange?(status)
    }

    /// Forwards a message to `onLog`.
    private func log(_ message: String) {
        onLog?(message)
    }
}
