import AppKit
import SwiftUI

final class HistoryWindow {
    private var window: NSWindow?
    private let history: TranscriptHistory
    private let licenseManager: LicenseManager

    init(history: TranscriptHistory, licenseManager: LicenseManager) {
        self.history = history
        self.licenseManager = licenseManager
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: HistoryView(history: history, licenseManager: licenseManager))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Macstral History"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

private struct HistoryView: View {
    @State private var searchText = ""
    @State private var showUpsell = false
    let history: TranscriptHistory
    let licenseManager: LicenseManager

    private var isUnlocked: Bool { FeatureGate.isHistoryUnlocked(isPro: licenseManager.isPro) }

    private static let entryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var filteredEntries: [TranscriptEntry] {
        history.entries
            .filter { history.matches($0, query: searchText) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            listContent
                .blur(radius: isUnlocked ? 0 : 8)
                .disabled(!isUnlocked)
                .allowsHitTesting(isUnlocked)
            if !isUnlocked {
                upsellOverlay
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .sheet(isPresented: $showUpsell) {
            UpsellSheet(licenseManager: licenseManager, highlight: "Transcript history")
        }
    }

    @ViewBuilder
    private var upsellOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Transcript history is a Pro feature")
                .font(.headline)
            Text("Your dictations are still saved on this Mac — upgrade to Pro to search, browse, and export your full history.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Upgrade to Pro — \(LemonSqueezyConfig.proPriceDisplay)") {
                showUpsell = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }

    private var listContent: some View {
        VStack(spacing: 12) {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No History Yet" : "No Matches",
                    systemImage: "text.page",
                    description: Text(searchText.isEmpty ? "Completed dictations will appear here. Stored locally only." : "Try a different search.")
                )
            } else {
                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Self.entryDateFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.appBundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Text(entry.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(12)
        .searchable(text: $searchText, prompt: "Search dictations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History", role: .destructive) {
                    history.clear()
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
