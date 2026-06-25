import XCTest
@testable import Macstral

@MainActor
final class AIWritingSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "AIWritingSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultProviderIsOpenAIOnline() {
        let config = AIWritingSettings.load(from: defaults)
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.openAIModel, AIWritingSettings.defaultOpenAIModel)
        XCTAssertTrue(config.fallbackToLocal)
    }

    func testSaveAndLoadRoundTrips() {
        let config = AIWritingConfiguration(
            provider: .openAICompatible,
            openAIModel: "gpt-test",
            compatibleBaseURL: "https://example.test/v1",
            compatibleModel: "custom-model",
            fallbackToLocal: false
        )
        AIWritingSettings.save(config, to: defaults)
        XCTAssertEqual(AIWritingSettings.load(from: defaults), config)
    }

    func testUnknownProviderFallsBackToOpenAI() {
        defaults.set("unknown", forKey: AIWritingSettings.providerKey)
        XCTAssertEqual(AIWritingSettings.load(from: defaults).provider, .openAI)
    }
}
