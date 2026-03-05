import AppKit
import SwiftUI
import HotKey

// MARK: - KeyRecorderView (NSViewRepresentable)

/// A field that records a new hotkey when clicked.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var key: Key
    @Binding var modifiers: NSEvent.ModifierFlags

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecorded = { newKey, newMods in
            key = newKey
            modifiers = newMods
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.currentKey = key
        nsView.currentModifiers = modifiers
        nsView.refresh()
    }
}

final class KeyRecorderNSView: NSView {
    var currentKey: Key = HotkeySettings.defaultKey
    var currentModifiers: NSEvent.ModifierFlags = HotkeySettings.defaultModifiers
    var onRecorded: ((Key, NSEvent.ModifierFlags) -> Void)?

    private var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateAppearance()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
        refresh()
    }

    func refresh() {
        if isRecording {
            label.stringValue = "Press hotkey…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = HotkeySettings.displayString(key: currentKey, modifiers: currentModifiers)
            label.textColor = .labelColor
        }
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.borderColor = isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.backgroundColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            : NSColor.controlBackgroundColor.cgColor
    }

    // MARK: - Click to start recording

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        refresh()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.handleFlagsEvent(event)
            } else {
                self.handleKeyEvent(event)
            }
            return nil // consume
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        refresh()
    }

    private func handleFlagsEvent(_ event: NSEvent) {
        // Capture fn key: it appears as a flagsChanged event with .function set,
        // with no other standard modifier flags and no associated key code for regular keys.
        let standardMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let hasFn = event.modifierFlags.contains(.function)
        let hasStandard = !event.modifierFlags.intersection(standardMods).isEmpty

        if hasFn && !hasStandard {
            currentKey = .function
            currentModifiers = []
            onRecorded?(.function, [])
            stopRecording()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = Key(carbonKeyCode: UInt32(event.keyCode)) else {
            stopRecording()
            return
        }
        // Escape cancels recording without changing the hotkey
        if key == .escape && modifiers.isEmpty {
            stopRecording()
            return
        }
        currentKey = key
        currentModifiers = modifiers
        onRecorded?(key, modifiers)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @State private var key: Key
    @State private var modifiers: NSEvent.ModifierFlags
    @State private var dictationMode: DictationMode
    @State private var language: TranscriptionLanguage
    @State private var modelQuality: ModelQuality
    @State private var pendingModelQuality: ModelQuality?
    @State private var showModelDownloadAlert: Bool = false
    var onHotkeyChanged: (Key, NSEvent.ModifierFlags) -> Void
    var onModelQualityChanged: ((ModelQuality) -> Void)?

    init(onHotkeyChanged: @escaping (Key, NSEvent.ModifierFlags) -> Void) {
        let (k, m) = HotkeySettings.load()
        _key = State(initialValue: k)
        _modifiers = State(initialValue: m)
        _dictationMode = State(initialValue: DictationMode(rawValue: UserDefaults.standard.string(forKey: "dictationMode") ?? "") ?? .normal)
        _language = State(initialValue: LanguageSettings.current)
        _modelQuality = State(initialValue: ModelQualitySettings.current)
        self.onHotkeyChanged = onHotkeyChanged
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Dictation Mode") {
                    Picker("", selection: $dictationMode) {
                        Text("Normal").tag(DictationMode.normal)
                        Text("Streaming").tag(DictationMode.streaming)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                LabeledContent("Hotkey") {
                    KeyRecorderView(key: $key, modifiers: $modifiers)
                        .frame(width: 120, height: 28)
                }
            } footer: {
                Text("Click the field and press a key combination to set a new hotkey.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                LabeledContent("Language") {
                    Picker("", selection: $language) {
                        ForEach(TranscriptionLanguage.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 260)
                }
            } footer: {
                if language.isBeta {
                    Text("\(language.displayName) is in beta — accuracy may vary. Auto-detect is recommended for most users.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Sets the transcription language. Auto-detect works well for single-language use; pick a specific language if you speak with an accent or mix languages.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                LabeledContent("Model quality") {
                    Picker("", selection: $modelQuality) {
                        ForEach(ModelQuality.allCases) { tier in
                            Text("\(tier.displayName) (\(tier.sizeLabel))").tag(tier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            } footer: {
                if modelQuality.requiresDownload {
                    Text("Requires a \(modelQuality.sizeLabel) download. Change takes effect after Macstral restarts the transcription engine.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Fast is the default — no extra download required. Higher quality tiers use more memory and take longer to load.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: dictationMode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: "dictationMode")
        }
        .onChange(of: language) { _, newLang in
            LanguageSettings.current = newLang
        }
        .onChange(of: modelQuality) { oldQuality, newQuality in
            if newQuality.requiresDownload {
                // Revert picker to old value; show confirmation alert first.
                pendingModelQuality = newQuality
                modelQuality = oldQuality
                showModelDownloadAlert = true
            } else {
                ModelQualitySettings.current = newQuality
                onModelQualityChanged?(newQuality)
            }
        }
        .alert("Download model?", isPresented: $showModelDownloadAlert, presenting: pendingModelQuality) { pending in
            Button("Download \(pending.sizeLabel) and Switch") {
                ModelQualitySettings.current = pending
                modelQuality = pending
                onModelQualityChanged?(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.downloadConfirmationMessage)
        }
        .onChange(of: key) { _, newKey in
            onHotkeyChanged(newKey, modifiers)
        }
        .onChange(of: modifiers.rawValue) { _, _ in
            onHotkeyChanged(key, modifiers)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Reset to Default") {
                    key = HotkeySettings.defaultKey
                    modifiers = HotkeySettings.defaultModifiers
                    onHotkeyChanged(key, modifiers)
                }
                .foregroundStyle(.red)
            }
        }
        .frame(width: 360)
        .padding(.vertical, 8)
    }
}
