import XCTest
import HotKey
@testable import Macstral

final class HotkeySettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "com.macstral.tests.HotkeySettings"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsWhenNothingSaved() {
        let (key, mods) = HotkeySettings.load(from: defaults)
        XCTAssertEqual(key, HotkeySettings.defaultKey)
        XCTAssertEqual(mods, HotkeySettings.defaultModifiers)
    }

    func testRoundTripOptionSpace() {
        HotkeySettings.save(key: .space, modifiers: [.option], to: defaults)
        let (key, mods) = HotkeySettings.load(from: defaults)
        XCTAssertEqual(key, .space)
        XCTAssertEqual(mods, [.option])
    }

    func testRoundTripCommandShiftA() {
        HotkeySettings.save(key: .a, modifiers: [.command, .shift], to: defaults)
        let (key, mods) = HotkeySettings.load(from: defaults)
        XCTAssertEqual(key, .a)
        XCTAssertEqual(mods, [.command, .shift])
    }

    func testResetRestoresDefaults() {
        HotkeySettings.save(key: .a, modifiers: [.command], to: defaults)
        HotkeySettings.reset(in: defaults)
        let (key, mods) = HotkeySettings.load(from: defaults)
        XCTAssertEqual(key, HotkeySettings.defaultKey)
        XCTAssertEqual(mods, HotkeySettings.defaultModifiers)
    }

    func testSaveOverwritesPreviousValue() {
        HotkeySettings.save(key: .space, modifiers: [.option], to: defaults)
        HotkeySettings.save(key: .f5, modifiers: [.control], to: defaults)
        let (key, mods) = HotkeySettings.load(from: defaults)
        XCTAssertEqual(key, .f5)
        XCTAssertEqual(mods, [.control])
    }
}
