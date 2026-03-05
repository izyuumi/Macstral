import Foundation

// MARK: - SessionTimer

/// Pure-value timer model.
///
/// Tracks elapsed seconds and formats them as M:SS (or H:MM:SS when hours are reached).
/// The actual `Timer` is managed externally (e.g. AppDelegate) so this struct
/// contains no side-effects and is trivially unit-testable.
struct SessionTimer: Equatable {

    // MARK: State

    var elapsedSeconds: Int = 0

    // MARK: Formatted output

    /// Human-readable elapsed time.
    ///
    /// Format: `M:SS` for < 1 hour (e.g. `0:00`, `1:05`, `59:59`)
    ///         `H:MM:SS` for ≥ 1 hour (e.g. `1:00:00`, `2:03:47`)
    var formattedTime: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    // MARK: Mutations

    /// Advance the timer by one second.
    mutating func tick() {
        elapsedSeconds += 1
    }

    /// Reset to zero.
    mutating func reset() {
        elapsedSeconds = 0
    }
}
