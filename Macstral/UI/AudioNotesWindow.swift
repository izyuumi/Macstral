import AppKit
import SwiftUI

final class AudioNotesWindow {
    private var window: NSWindow?
    private let store: AudioNotesStore
    private let appState: AppState
    private let onStartRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onRegenerate: (AudioNote) -> Void
    private let onExport: (AudioNote) -> Void

    init(
        store: AudioNotesStore,
        appState: AppState,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onRegenerate: @escaping (AudioNote) -> Void,
        onExport: @escaping (AudioNote) -> Void
    ) {
        self.store = store
        self.appState = appState
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onRegenerate = onRegenerate
        self.onExport = onExport
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: AudioNotesView(
            store: store,
            appState: appState,
            onStartRecording: onStartRecording,
            onStopRecording: onStopRecording,
            onRegenerate: onRegenerate,
            onExport: onExport
        ))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Audio Notes"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

// MARK: - AudioNotesView

private struct AudioNotesView: View {
    let store: AudioNotesStore
    let appState: AppState
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onRegenerate: (AudioNote) -> Void
    let onExport: (AudioNote) -> Void

    @State private var searchText = ""
    @State private var selectedNoteID: UUID?

    private var sortedNotes: [AudioNote] {
        store.notes
            .filter { store.matches($0, query: searchText) }
            .sorted { $0.date > $1.date }
    }

    private var selectedNote: AudioNote? {
        guard let id = selectedNoteID else { return nil }
        return store.notes.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            if let note = selectedNote {
                NoteDetailView(
                    note: note,
                    store: store,
                    onRegenerate: onRegenerate,
                    onExport: onExport
                )
            } else {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "waveform",
                    description: Text("Select a note from the list or record new audio.")
                )
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            recordingControls
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            micToggle
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            statusBanner
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            notesList
        }
        .searchable(text: $searchText, prompt: "Search audio notes")
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch appState.audioNotesStatus {
        case .idle:
            Button {
                onStartRecording()
            } label: {
                Label("Record System Audio", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

        case .recording:
            Button {
                onStopRecording()
            } label: {
                Label("Stop", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

        case .transcribing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .generatingNotes:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Generating notes…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .error:
            Button {
                onStartRecording()
            } label: {
                Label("Record System Audio", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    @ViewBuilder
    private var micToggle: some View {
        switch appState.audioNotesStatus {
        case .idle, .error:
            Toggle("Include microphone", isOn: Binding(
                get: { appState.audioNotesIncludeMicrophone },
                set: { appState.audioNotesIncludeMicrophone = $0 }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch appState.audioNotesStatus {
        case .idle:
            EmptyView()

        case .recording:
            let seconds = appState.audioNotesRecordingSeconds
            let mm = seconds / 60
            let ss = seconds % 60
            Text(String(format: "Recording: %02d:%02d", mm, ss))
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .transcribing:
            Text(appState.audioNotesProgressText.isEmpty ? "Transcribing audio…" : appState.audioNotesProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .generatingNotes:
            Text(appState.audioNotesProgressText.isEmpty ? "Generating AI notes…" : appState.audioNotesProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var notesList: some View {
        if sortedNotes.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Audio Notes Yet" : "No Matches",
                systemImage: "waveform",
                description: Text(searchText.isEmpty
                    ? "Record system audio to create your first note."
                    : "Try a different search.")
            )
        } else {
            List(sortedNotes, selection: $selectedNoteID) { note in
                NoteRowView(note: note)
                    .tag(note.id)
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - NoteRowView

private struct NoteRowView: View {
    let note: AudioNote

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(Self.relativeDateFormatter.localizedString(for: note.date, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.transcript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - NoteDetailView

private struct NoteDetailView: View {
    let note: AudioNote
    let store: AudioNotesStore
    let onRegenerate: (AudioNote) -> Void
    let onExport: (AudioNote) -> Void

    @State private var editableTitle: String
    @State private var isTranscriptExpanded = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(note: AudioNote, store: AudioNotesStore, onRegenerate: @escaping (AudioNote) -> Void, onExport: @escaping (AudioNote) -> Void) {
        self.note = note
        self.store = store
        self.onRegenerate = onRegenerate
        self.onExport = onExport
        self._editableTitle = State(initialValue: note.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                TextField("Title", text: $editableTitle)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .onSubmit {
                        var updated = note
                        updated.title = editableTitle
                        store.update(updated)
                    }

                // Date & duration
                HStack(spacing: 12) {
                    Text(Self.dateFormatter.string(from: note.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let mm = Int(note.durationSeconds) / 60
                    let ss = Int(note.durationSeconds) % 60
                    Text(String(format: "%02d:%02d", mm, ss))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // AI Notes section
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Notes")
                        .font(.headline)

                    if note.notes.isEmpty {
                        Text("No notes yet")
                            .foregroundStyle(.tertiary)
                            .italic()
                    } else {
                        Text(LocalizedStringKey(note.notes))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                // Transcript section
                DisclosureGroup(
                    isExpanded: $isTranscriptExpanded,
                    content: {
                        Text(note.transcript)
                            .textSelection(.enabled)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    },
                    label: {
                        Text("Transcript")
                            .font(.headline)
                    }
                )
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Regenerate Notes") {
                    onRegenerate(note)
                }

                Button("Export") {
                    onExport(note)
                }

                Button("Delete", role: .destructive) {
                    store.remove(note)
                }
                .foregroundStyle(.red)
            }
        }
        .onChange(of: note.id) { _, _ in
            editableTitle = note.title
        }
    }
}
