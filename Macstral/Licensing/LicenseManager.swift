import Foundation
import Observation

// MARK: - LicenseState

/// The Pro entitlement state surfaced to the UI.
enum LicenseState: Equatable {
    /// No valid license — free tier.
    case free
    /// Valid license, validated online recently.
    case pro
    /// Valid license, but the last online validation failed; still Pro within the grace window.
    case proOfflineGrace
}

// MARK: - LicenseError

enum LicenseError: LocalizedError, Equatable {
    case invalidKey(String)
    case alreadyActivatedElsewhere
    case noActiveLicense

    var errorDescription: String? {
        switch self {
        case .invalidKey(let message):     return message
        case .alreadyActivatedElsewhere:   return "This license key has reached its activation limit. Deactivate another Mac first."
        case .noActiveLicense:             return "No active license on this Mac."
        }
    }
}

// MARK: - LicenseManager

/// Single source of truth for Pro entitlement. The UI observes `isPro`; gate enforcement
/// reads it via `FeatureGate`.
///
/// Persistence lives in Keychain (`LicenseStore`); network calls go through `LicenseAPIClient`.
/// Both, plus the clock, are injected so the offline-grace logic is testable without sleeping
/// or hitting the network.
@MainActor
@Observable
final class LicenseManager {

    // MARK: Shared instance (production wiring)

    static let shared = LicenseManager(
        api: LemonSqueezyAPIClient(),
        store: KeychainLicenseStore(),
        now: { Date() }
    )

    // MARK: Observable state

    private(set) var isPro: Bool = false
    private(set) var state: LicenseState = .free
    /// Masked form of the active key for display, e.g. "XXXX-…-7F3A". Nil when free.
    private(set) var maskedKey: String?
    /// Last user-facing error from activate/validate, for the License tab to show.
    private(set) var lastError: String?

    // MARK: Configuration

    /// Offline grace window: stay Pro this long after the last successful validation even if
    /// the network is unreachable. (PLAN.md §4.1 — 14 days.)
    static let gracePeriod: TimeInterval = 14 * 24 * 60 * 60

    // MARK: Dependencies

    private let api: LicenseAPIClient
    private let store: LicenseStore
    private let now: () -> Date

    // MARK: Init

    init(api: LicenseAPIClient, store: LicenseStore, now: @escaping () -> Date) {
        self.api = api
        self.store = store
        self.now = now
        loadFromStore()
    }

    /// Cold-start: if stored credentials exist and are within the grace window, become Pro
    /// immediately — before any network round-trip (PLAN.md test case 6).
    private func loadFromStore() {
        guard let record = store.load() else {
            applyFree()
            return
        }
        maskedKey = Self.mask(record.key)
        if now().timeIntervalSince(record.lastValidated) <= Self.gracePeriod {
            isPro = true
            state = .pro
        } else {
            // Stored but stale beyond grace: drop to free until a fresh online validation.
            isPro = false
            state = .free
        }
    }

    // MARK: Activation

    /// Activate a license key on this Mac. On success, persists credentials and flips to Pro.
    /// On a definitive rejection, throws and stores nothing (PLAN.md test cases 1 & 2).
    func activate(key: String) async throws {
        lastError = nil
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw LicenseError.invalidKey("Enter a license key.")
        }

        let instanceName = Self.machineName()
        let result: LicenseActivationResult
        do {
            result = try await api.activate(key: trimmedKey, instanceName: instanceName)
        } catch let error as LicenseAPIError {
            lastError = error.errorDescription
            throw error
        }

        guard result.activated, result.valid, let instanceID = result.instanceID else {
            let message = result.errorMessage ?? "That license key could not be activated."
            lastError = message
            // Lemon Squeezy reports activation-limit overflow in the error text.
            if message.lowercased().contains("activation limit") {
                throw LicenseError.alreadyActivatedElsewhere
            }
            throw LicenseError.invalidKey(message)
        }

        let record = LicenseRecord(
            key: trimmedKey,
            instanceID: instanceID,
            instanceName: instanceName,
            lastValidated: now()
        )
        try store.save(record)
        maskedKey = Self.mask(trimmedKey)
        isPro = true
        state = .pro
    }

    // MARK: Validation

    /// Re-validate the stored license. Called on launch and periodically.
    /// - Online success → refresh `lastValidated`, stay/become Pro.
    /// - Online definitive "invalid" → drop to Free and clear credentials.
    /// - Network failure within grace → stay Pro (`.proOfflineGrace`).
    /// - Network failure past grace → drop to Free (warn, do not delete creds — a later
    ///   successful validation can restore Pro).
    func validate() async {
        guard var record = store.load() else {
            applyFree()
            return
        }

        let result: LicenseValidationResult
        do {
            result = try await api.validate(key: record.key, instanceID: record.instanceID)
        } catch let error as LicenseAPIError where error.isNetworkFailure {
            applyOfflineGrace(record: record)
            return
        } catch {
            applyOfflineGrace(record: record)
            return
        }

        if result.valid {
            record.lastValidated = now()
            try? store.save(record)
            maskedKey = Self.mask(record.key)
            isPro = true
            state = .pro
            lastError = nil
        } else {
            // Server says the key is no longer valid (refunded, revoked, deactivated remotely).
            try? store.clear()
            applyFree()
            lastError = result.errorMessage ?? "This license is no longer valid."
        }
    }

    // MARK: Deactivation

    /// Free this Mac's activation slot and drop to Free. Best-effort network call; local
    /// credentials are cleared regardless so the user is never stuck Pro-locked locally.
    func deactivate() async {
        guard let record = store.load() else {
            applyFree()
            return
        }
        _ = try? await api.deactivate(key: record.key, instanceID: record.instanceID)
        try? store.clear()
        applyFree()
    }

    // MARK: - Helpers

    private func applyFree() {
        isPro = false
        state = .free
        maskedKey = nil
    }

    private func applyOfflineGrace(record: LicenseRecord) {
        maskedKey = Self.mask(record.key)
        if now().timeIntervalSince(record.lastValidated) <= Self.gracePeriod {
            isPro = true
            state = .proOfflineGrace
            lastError = nil
        } else {
            isPro = false
            state = .free
            lastError = "Could not reach the license server and the offline grace period has expired."
        }
    }

    private static func mask(_ key: String) -> String {
        let tail = String(key.suffix(4))
        return "••••-••••-\(tail.isEmpty ? "????" : tail)"
    }

    private static func machineName() -> String {
        let host = ProcessInfo.processInfo.hostName
        return host.isEmpty ? "Mac" : host
    }
}
