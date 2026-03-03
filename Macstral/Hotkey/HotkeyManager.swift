import AppKit
import Carbon
import HotKey

// MARK: - HotkeySettings

struct HotkeySettings {
    /// Sentinel: fn key is represented as Key.function with empty modifiers.
    static let defaultKey: Key = .function
    static let defaultModifiers: NSEvent.ModifierFlags = []

    private static let keyCodeUD   = "hotkeyKeyCode"
    private static let modifiersUD = "hotkeyModifiers"

    // Special carbon key code used to persist "fn key" mode.
    // Key.function.carbonKeyCode == kVK_Function (0x3F).
    static var isFnKey: (Key, NSEvent.ModifierFlags) -> Bool = { key, mods in
        key == .function && mods.isEmpty
    }

    nonisolated static func load(from defaults: UserDefaults = .standard) -> (key: Key, modifiers: NSEvent.ModifierFlags) {
        if defaults.object(forKey: keyCodeUD) != nil,
           let key = Key(carbonKeyCode: UInt32(defaults.integer(forKey: keyCodeUD))) {
            let rawMods = UInt(bitPattern: defaults.integer(forKey: modifiersUD))
            return (key, NSEvent.ModifierFlags(rawValue: rawMods))
        }
        return (defaultKey, defaultModifiers)
    }

    nonisolated static func save(key: Key, modifiers: NSEvent.ModifierFlags, to defaults: UserDefaults = .standard) {
        defaults.set(Int(key.carbonKeyCode), forKey: keyCodeUD)
        defaults.set(Int(bitPattern: modifiers.rawValue), forKey: modifiersUD)
    }

    nonisolated static func reset(in defaults: UserDefaults = .standard) {
        save(key: defaultKey, modifiers: defaultModifiers, to: defaults)
    }

    /// Human-readable label, e.g. "fn", "⌥Space", "⌃⌘A"
    nonisolated static func displayString(key: Key, modifiers: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option)  { parts += "⌥" }
        if modifiers.contains(.shift)   { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += key.displayLabel
        return parts
    }
}

// MARK: - Key + displayLabel

extension Key {
    var displayLabel: String {
        switch self {
        case .function:      return "fn"
        case .space:         return "Space"
        case .return:        return "↩"
        case .tab:           return "⇥"
        case .delete:        return "⌫"
        case .forwardDelete: return "⌦"
        case .escape:        return "⎋"
        case .upArrow:       return "↑"
        case .downArrow:     return "↓"
        case .leftArrow:     return "←"
        case .rightArrow:    return "→"
        case .pageUp:        return "⇞"
        case .pageDown:      return "⇟"
        case .home:          return "↖"
        case .end:           return "↘"
        case .f1:            return "F1"
        case .f2:            return "F2"
        case .f3:            return "F3"
        case .f4:            return "F4"
        case .f5:            return "F5"
        case .f6:            return "F6"
        case .f7:            return "F7"
        case .f8:            return "F8"
        case .f9:            return "F9"
        case .f10:           return "F10"
        case .f11:           return "F11"
        case .f12:           return "F12"
        case .f13:           return "F13"
        case .f14:           return "F14"
        case .f15:           return "F15"
        case .f16:           return "F16"
        case .f17:           return "F17"
        case .f18:           return "F18"
        case .f19:           return "F19"
        case .f20:           return "F20"
        default:
            return carbonKeyLabel ?? "?"
        }
    }

    private var carbonKeyLabel: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layoutPtr  = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            layoutPtr,
            UInt16(carbonKeyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        return String(chars.prefix(length).map { Character(UnicodeScalar($0)!) }).uppercased()
    }
}

// MARK: - HotkeyManager

class HotkeyManager {
    private var hotKey: HotKey?
    private var flagsMonitor: Any?
    private var fnWasDown = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func setup() {
        let (key, mods) = HotkeySettings.load()
        configure(key: key, modifiers: mods)
    }

    func reconfigure(key: Key, modifiers: NSEvent.ModifierFlags) {
        HotkeySettings.save(key: key, modifiers: modifiers)
        configure(key: key, modifiers: modifiers)
    }

    func teardown() {
        hotKey = nil
        removeFlagsMonitor()
    }

    // MARK: - Private

    private func configure(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey = nil
        removeFlagsMonitor()

        if HotkeySettings.isFnKey(key, modifiers) {
            // fn generates flagsChanged events, not keyDown — monitor flags directly.
            fnWasDown = false
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return }
                let isFnDown = event.modifierFlags.contains(.function)
                if isFnDown && !self.fnWasDown {
                    self.fnWasDown = true
                    self.onKeyDown?()
                } else if !isFnDown && self.fnWasDown {
                    self.fnWasDown = false
                    self.onKeyUp?()
                }
            }
        } else {
            let hk = HotKey(key: key, modifiers: modifiers)
            hk.keyDownHandler = { [weak self] in self?.onKeyDown?() }
            hk.keyUpHandler   = { [weak self] in self?.onKeyUp?() }
            hotKey = hk
        }
    }

    private func removeFlagsMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        fnWasDown = false
    }
}
