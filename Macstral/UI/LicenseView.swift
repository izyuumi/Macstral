import SwiftUI

// MARK: - LicenseView

/// The Preferences → License tab. Shows Free vs Pro status, the upgrade path, a key-entry
/// field, and (when Pro) the masked key plus a "Deactivate this Mac" action.
struct LicenseView: View {
    @Bindable var licenseManager: LicenseManager

    @State private var keyInput: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: licenseManager.isPro ? "checkmark.seal.fill" : "lock.circle")
                        .foregroundStyle(licenseManager.isPro ? Color.green : Color.secondary)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(licenseManager.isPro ? "Macstral Pro" : "Macstral Free")
                            .font(.headline)
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if licenseManager.isPro {
                proSection
            } else {
                freeSection
            }

            aboutSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Pro

    @ViewBuilder
    private var proSection: some View {
        Section {
            LabeledContent("License key", value: licenseManager.maskedKey ?? "••••")
            Button("Deactivate this Mac", role: .destructive) {
                runTask { await licenseManager.deactivate() }
            }
            .disabled(isWorking)
        } footer: {
            Text("Deactivating frees one of your \(LemonSqueezyConfig.activationInstanceLimit) activations so you can use Pro on another Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Free

    @ViewBuilder
    private var freeSection: some View {
        Section {
            ForEach(ProFeature.all) { feature in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: feature.symbol)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                        Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Unlock with Pro")
        }

        Section {
            Button("Upgrade — \(LemonSqueezyConfig.proPriceDisplay)") {
                openURL(LemonSqueezyConfig.checkoutURL)
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("One-time purchase via Lemon Squeezy. No subscription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button(isWorking ? "Activating…" : "Activate License") {
                activate()
            }
            .disabled(isWorking || keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Already bought?")
        } footer: {
            Text("Paste the key from your purchase confirmation email or the checkout success page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: About

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            Link("End User License Agreement", destination: Self.eulaURL)
            Link("Third-party licenses & acknowledgements", destination: Self.acknowledgementsURL)
        } footer: {
            Text("© Yumi Izumi. Macstral is proprietary software, provided under the EULA.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    private static let eulaURL = URL(string: "https://github.com/izyuumi/Macstral/blob/main/EULA.md")!
    private static let acknowledgementsURL = URL(string: "https://github.com/izyuumi/Macstral/blob/main/THIRD_PARTY_LICENSES.md")!

    // MARK: Actions

    private var statusDetail: String {
        switch licenseManager.state {
        case .pro:             return "Cloud processing unlocked. Thank you!"
        case .proOfflineGrace: return "Pro active (offline — will re-verify when back online)."
        case .free:            return "Full on-device app — every language, model, and history. Pro adds optional cloud speed."
        }
    }

    private func activate() {
        errorMessage = nil
        let key = keyInput
        runTask {
            do {
                try await licenseManager.activate(key: key)
                keyInput = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runTask(_ operation: @escaping () async -> Void) {
        isWorking = true
        Task {
            await operation()
            isWorking = false
        }
    }
}
