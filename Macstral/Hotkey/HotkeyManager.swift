import AppKit
import HotKey

class HotkeyManager {
    private var hotKey: HotKey?

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func setup() {
        let hk = HotKey(key: .space, modifiers: [.option])
        hk.keyDownHandler = { [weak self] in
            self?.onKeyDown?()
        }
        hk.keyUpHandler = { [weak self] in
            self?.onKeyUp?()
        }
        hotKey = hk
    }

    func teardown() {
        hotKey = nil
    }
}
