import AppKit
import SwiftUI

final class HistoryWindow {
    private var window: NSWindow?
    private let history: TranscriptHistory

    init(history: TranscriptHistory) {
        self.history = history
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: HistoryView(history: history))
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
    let history: TranscriptHistory

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
        listContent
            .frame(minWidth: 520, minHeight: 360)
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
