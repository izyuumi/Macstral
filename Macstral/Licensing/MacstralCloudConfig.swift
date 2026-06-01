import Foundation

// MARK: - MacstralCloudConfig

/// Endpoints for the optional **Macstral-hosted online processing proxy** — the one capability
/// that Pro unlocks. The proxy speaks the same WebSocket JSON protocol as the local Voxtral
/// server (`start_session` / binary audio / `commit` → `delta`/`done`, and `generate_notes` →
/// `notes_done`), so the app's existing clients only need a different URL and an auth header.
///
/// Authentication uses the user's **own license key** as a bearer token; the proxy validates it
/// against Lemon Squeezy and forwards to the upstream vendor. No vendor API keys are ever shipped
/// in the app.
///
/// `baseURL` is a placeholder until the proxy is deployed — mirroring the `REPLACE_*` convention
/// in `LemonSqueezyConfig`. The cloud processing toggle is harmless until then because it is
/// Pro-gated and falls back to on-device on any connection error.
enum MacstralCloudConfig {

    /// Whether a real proxy host has been configured. The cloud option stays hidden/disabled
    /// until this is true so users are never offered a dead endpoint.
    static var isConfigured: Bool { !baseURL.absoluteString.contains("REPLACE_") }

    /// Base URL of the Macstral proxy. Replace once the proxy is deployed.
    static let baseURL = URL(string: "https://REPLACE_PROXY_HOST")!

    /// WebSocket path that mirrors the local server protocol (streaming ASR + notes generation).
    static let streamPath = "/v1/stream"

    /// The `wss://` URL for the streaming endpoint.
    static var streamURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = (components.scheme == "http") ? "ws" : "wss"
        components.path = streamPath
        return components.url!
    }

    /// Builds a WebSocket `URLRequest` carrying the license key as a bearer token.
    static func streamRequest(authToken: String) -> URLRequest {
        var request = URLRequest(url: streamURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
