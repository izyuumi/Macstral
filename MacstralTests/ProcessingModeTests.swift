import XCTest
@testable import Macstral

// MARK: - ProcessingModeTests

final class ProcessingModeTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "ProcessingModeTests"

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

    // MARK: Settings persistence

    func testDefaultModeIsOnDevice() {
        XCTAssertEqual(ProcessingModeSettings.load(from: defaults), .onDevice)
    }

    func testSaveAndLoadRoundTrips() {
        ProcessingModeSettings.save(.cloud, to: defaults)
        XCTAssertEqual(ProcessingModeSettings.load(from: defaults), .cloud)
    }

    func testUnknownRawValueFallsBackToDefault() {
        defaults.set("bogus", forKey: ProcessingModeSettings.key)
        XCTAssertEqual(ProcessingModeSettings.load(from: defaults), .onDevice)
    }

    // MARK: Endpoint resolution

    func testFreeUserAlwaysResolvesOnDevice() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: false, mode: .cloud, cloudConfigured: true, authToken: "key", localPort: 1234
        )
        XCTAssertEqual(endpoint, .onDevice(port: 1234))
    }

    func testProUserOnDeviceModeResolvesOnDevice() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: true, mode: .onDevice, cloudConfigured: true, authToken: "key", localPort: 1234
        )
        XCTAssertEqual(endpoint, .onDevice(port: 1234))
    }

    func testProUserCloudModeResolvesCloud() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: true, mode: .cloud, cloudConfigured: true, authToken: "key", localPort: 1234
        )
        XCTAssertEqual(endpoint, .cloud(authToken: "key"))
    }

    func testCloudUnconfiguredFallsBackToOnDevice() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: true, mode: .cloud, cloudConfigured: false, authToken: "key", localPort: 1234
        )
        XCTAssertEqual(endpoint, .onDevice(port: 1234))
    }

    func testCloudWithoutTokenFallsBackToOnDevice() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: true, mode: .cloud, cloudConfigured: true, authToken: nil, localPort: 1234
        )
        XCTAssertEqual(endpoint, .onDevice(port: 1234))
    }

    func testNoEndpointWhenNothingAvailable() {
        let endpoint = ProcessingEndpoint.resolve(
            isPro: true, mode: .cloud, cloudConfigured: false, authToken: nil, localPort: nil
        )
        XCTAssertNil(endpoint)
    }
}
