import Foundation

// MARK: - API result types

/// Outcome of a `/licenses/activate` call.
struct LicenseActivationResult: Equatable {
    let activated: Bool
    let valid: Bool
    let instanceID: String?
    let errorMessage: String?
}

/// Outcome of a `/licenses/validate` call.
struct LicenseValidationResult: Equatable {
    let valid: Bool
    let errorMessage: String?
}

// MARK: - LicenseAPIClient

/// Abstraction over the Lemon Squeezy license endpoints so `LicenseManager` can be tested
/// with a mock returning canned JSON instead of hitting the network.
protocol LicenseAPIClient: Sendable {
    func activate(key: String, instanceName: String) async throws -> LicenseActivationResult
    func validate(key: String, instanceID: String) async throws -> LicenseValidationResult
    func deactivate(key: String, instanceID: String) async throws -> Bool
}

// MARK: - LicenseAPIError

enum LicenseAPIError: LocalizedError {
    case transport(Error)
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .transport(let error): return error.localizedDescription
        case .badResponse:          return "Unexpected response from the license server."
        case .server(let message):  return message
        }
    }

    /// Whether this error represents a network-reachability failure (vs. a definitive
    /// server rejection). Drives the offline-grace decision in `LicenseManager`.
    var isNetworkFailure: Bool {
        if case .transport = self { return true }
        return false
    }
}

// MARK: - LemonSqueezyAPIClient

/// Production `LicenseAPIClient` backed by `URLSession`, talking to the Lemon Squeezy
/// license API. These endpoints take the license key directly, so no secret API key is
/// embedded in the app.
final class LemonSqueezyAPIClient: LicenseAPIClient {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func activate(key: String, instanceName: String) async throws -> LicenseActivationResult {
        let json = try await post(
            url: LemonSqueezyConfig.activateURL,
            fields: ["license_key": key, "instance_name": instanceName]
        )
        let activated = (json["activated"] as? Bool) ?? false
        let valid = (json["valid"] as? Bool) ?? activated
        let instance = json["instance"] as? [String: Any]
        let instanceID = (instance?["id"] as? String) ?? (instance?["id"]).map { "\($0)" }
        let errorMessage = json["error"] as? String
        return LicenseActivationResult(
            activated: activated,
            valid: valid,
            instanceID: instanceID,
            errorMessage: errorMessage
        )
    }

    func validate(key: String, instanceID: String) async throws -> LicenseValidationResult {
        let json = try await post(
            url: LemonSqueezyConfig.validateURL,
            fields: ["license_key": key, "instance_id": instanceID]
        )
        let valid = (json["valid"] as? Bool) ?? false
        let errorMessage = json["error"] as? String
        return LicenseValidationResult(valid: valid, errorMessage: errorMessage)
    }

    func deactivate(key: String, instanceID: String) async throws -> Bool {
        let json = try await post(
            url: LemonSqueezyConfig.deactivateURL,
            fields: ["license_key": key, "instance_id": instanceID]
        )
        return (json["deactivated"] as? Bool) ?? false
    }

    // MARK: - Transport

    /// POSTs form-encoded `fields` and returns the parsed JSON object. Maps URLSession
    /// failures to `.transport` (network) and non-2xx/unparseable bodies to `.badResponse`.
    /// Lemon Squeezy returns HTTP 400 with a JSON `error` for invalid keys, which we surface
    /// as a parsed object rather than throwing, so callers can read `error`.
    private func post(url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncode(fields).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseAPIError.badResponse
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 5xx or HTML error page with no JSON body — treat as a transient transport-like
            // failure so a flaky server doesn't instantly revoke Pro.
            if (500...599).contains(http.statusCode) {
                throw LicenseAPIError.transport(URLError(.badServerResponse))
            }
            throw LicenseAPIError.badResponse
        }
        return object
    }

    private func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
