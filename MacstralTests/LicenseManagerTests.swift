import XCTest
@testable import Macstral

// MARK: - Mock API client

/// Controllable `LicenseAPIClient` returning canned results / injected errors.
final class MockLicenseAPIClient: LicenseAPIClient, @unchecked Sendable {
    var activateResult: Result<LicenseActivationResult, Error> =
        .success(LicenseActivationResult(activated: true, valid: true, instanceID: "inst-1", errorMessage: nil))
    var validateResult: Result<LicenseValidationResult, Error> =
        .success(LicenseValidationResult(valid: true, errorMessage: nil))
    var deactivateResult: Result<Bool, Error> = .success(true)

    private(set) var activateCallCount = 0
    private(set) var validateCallCount = 0
    private(set) var deactivateCallCount = 0
    private(set) var lastInstanceName: String?

    func activate(key: String, instanceName: String) async throws -> LicenseActivationResult {
        activateCallCount += 1
        lastInstanceName = instanceName
        return try activateResult.get()
    }

    func validate(key: String, instanceID: String) async throws -> LicenseValidationResult {
        validateCallCount += 1
        return try validateResult.get()
    }

    func deactivate(key: String, instanceID: String) async throws -> Bool {
        deactivateCallCount += 1
        return try deactivateResult.get()
    }
}

// MARK: - LicenseManagerTests

@MainActor
final class LicenseManagerTests: XCTestCase {

    private var api: MockLicenseAPIClient!
    private var store: InMemoryLicenseStore!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        api = MockLicenseAPIClient()
        store = InMemoryLicenseStore()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDown() {
        api = nil
        store = nil
        clock = nil
        super.tearDown()
    }

    private func makeManager() -> LicenseManager {
        LicenseManager(api: api, store: store, now: { [unowned self] in self.clock })
    }

    private func validRecord(daysAgo: Double) -> LicenseRecord {
        LicenseRecord(
            key: "TEST-KEY-1234-ABCD",
            instanceID: "inst-1",
            instanceName: "TestMac",
            lastValidated: clock.addingTimeInterval(-daysAgo * 24 * 60 * 60)
        )
    }

    // MARK: 1. activate success

    func testActivateSuccessBecomesProAndPersists() async throws {
        let manager = makeManager()
        XCTAssertFalse(manager.isPro)

        try await manager.activate(key: "TEST-KEY-1234-ABCD")

        XCTAssertTrue(manager.isPro, "Successful activation must flip isPro to true")
        XCTAssertEqual(manager.state, .pro)
        XCTAssertNotNil(store.load(), "Credentials must be persisted on success")
        XCTAssertEqual(store.load()?.instanceID, "inst-1")
        XCTAssertEqual(store.load()?.lastValidated, clock, "lastValidated should be stamped at activation time")
    }

    func testActivateRegistersMachineNameAsInstanceName() async throws {
        let manager = makeManager()
        try await manager.activate(key: "TEST-KEY-1234-ABCD")
        XCTAssertFalse(api.lastInstanceName?.isEmpty ?? true, "An instance name should be sent to Lemon Squeezy")
    }

    // MARK: 2. activate invalid key

    func testActivateInvalidKeyThrowsAndStoresNothing() async {
        api.activateResult = .success(
            LicenseActivationResult(activated: false, valid: false, instanceID: nil, errorMessage: "license_key not found.")
        )
        let manager = makeManager()

        do {
            try await manager.activate(key: "BOGUS")
            XCTFail("Activation with an invalid key should throw")
        } catch {
            // expected
        }

        XCTAssertFalse(manager.isPro, "Invalid key must not grant Pro")
        XCTAssertEqual(manager.state, .free)
        XCTAssertNil(store.load(), "Nothing should be persisted on a failed activation")
        XCTAssertNotNil(manager.lastError)
    }

    func testActivateEmptyKeyThrows() async {
        let manager = makeManager()
        do {
            try await manager.activate(key: "   ")
            XCTFail("Empty key should throw")
        } catch {
            XCTAssertEqual(api.activateCallCount, 0, "Empty key should not hit the network")
        }
    }

    func testActivateOverLimitThrowsActivationLimitError() async {
        api.activateResult = .success(
            LicenseActivationResult(activated: false, valid: false, instanceID: nil, errorMessage: "License key has reached its activation limit.")
        )
        let manager = makeManager()
        do {
            try await manager.activate(key: "TEST-KEY")
            XCTFail("Over-limit activation should throw")
        } catch let error as LicenseError {
            XCTAssertEqual(error, .alreadyActivatedElsewhere)
        } catch {
            XCTFail("Expected LicenseError.alreadyActivatedElsewhere, got \(error)")
        }
    }

    // MARK: 3. validate success refreshes lastValidated

    func testValidateSuccessRefreshesLastValidated() async {
        try? store.save(validRecord(daysAgo: 5))
        let manager = makeManager()

        await manager.validate()

        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.state, .pro)
        XCTAssertEqual(store.load()?.lastValidated, clock, "Successful validation refreshes the timestamp to now")
    }

    func testValidateServerSaysInvalidDropsToFreeAndClears() async {
        try? store.save(validRecord(daysAgo: 1))
        api.validateResult = .success(LicenseValidationResult(valid: false, errorMessage: "License has been refunded."))
        let manager = makeManager()

        await manager.validate()

        XCTAssertFalse(manager.isPro, "A definitively invalid license drops to Free")
        XCTAssertEqual(manager.state, .free)
        XCTAssertNil(store.load(), "Revoked credentials should be cleared")
    }

    // MARK: 4. network failure within grace → stays Pro

    func testValidateNetworkFailureWithinGraceStaysPro() async {
        try? store.save(validRecord(daysAgo: 5))
        api.validateResult = .failure(LicenseAPIError.transport(URLError(.notConnectedToInternet)))
        let manager = makeManager()

        await manager.validate()

        XCTAssertTrue(manager.isPro, "Within the 14-day grace window, network failure must not revoke Pro")
        XCTAssertEqual(manager.state, .proOfflineGrace)
        XCTAssertNotNil(store.load(), "Credentials are retained during grace")
    }

    // MARK: 5. network failure past grace → drops to Free

    func testValidateNetworkFailurePastGraceDropsToFree() async {
        try? store.save(validRecord(daysAgo: 20))
        api.validateResult = .failure(LicenseAPIError.transport(URLError(.notConnectedToInternet)))
        let manager = makeManager()

        await manager.validate()

        XCTAssertFalse(manager.isPro, "Past the grace window with no network, Pro lapses")
        XCTAssertEqual(manager.state, .free)
        XCTAssertNotNil(store.load(), "Credentials are kept so a later online validation can restore Pro")
        XCTAssertNotNil(manager.lastError)
    }

    func testValidateBoundaryExactlyAtGraceStaysPro() async {
        try? store.save(validRecord(daysAgo: 14))
        api.validateResult = .failure(LicenseAPIError.transport(URLError(.timedOut)))
        let manager = makeManager()

        await manager.validate()

        XCTAssertTrue(manager.isPro, "Exactly at the grace boundary should still be Pro (<=)")
        XCTAssertEqual(manager.state, .proOfflineGrace)
    }

    // MARK: 6. cold start with stored valid creds → Pro before network

    func testColdStartWithValidStoredCredsIsProImmediately() {
        try? store.save(validRecord(daysAgo: 3))
        let manager = makeManager()

        XCTAssertTrue(manager.isPro, "Stored credentials within grace make the app Pro before any network call")
        XCTAssertEqual(manager.state, .pro)
        XCTAssertEqual(api.validateCallCount, 0, "Cold start must not require a network round-trip")
    }

    func testColdStartWithStaleStoredCredsIsFreeUntilValidation() {
        try? store.save(validRecord(daysAgo: 30))
        let manager = makeManager()

        XCTAssertFalse(manager.isPro, "Stored creds older than grace start Free until re-validated")
        XCTAssertEqual(manager.state, .free)
    }

    func testColdStartWithNoCredsIsFree() {
        let manager = makeManager()
        XCTAssertFalse(manager.isPro)
        XCTAssertEqual(manager.state, .free)
        XCTAssertNil(manager.maskedKey)
    }

    // MARK: 7. deactivate clears store

    func testDeactivateClearsStoreAndDropsToFree() async {
        try? store.save(validRecord(daysAgo: 1))
        let manager = makeManager()
        XCTAssertTrue(manager.isPro)

        await manager.deactivate()

        XCTAssertFalse(manager.isPro, "Deactivation drops to Free")
        XCTAssertEqual(manager.state, .free)
        XCTAssertNil(store.load(), "Deactivation clears stored credentials")
        XCTAssertEqual(api.deactivateCallCount, 1, "Deactivation should free the remote instance slot")
        XCTAssertNil(manager.maskedKey)
    }

    func testDeactivateClearsLocallyEvenIfNetworkFails() async {
        try? store.save(validRecord(daysAgo: 1))
        api.deactivateResult = .failure(LicenseAPIError.transport(URLError(.notConnectedToInternet)))
        let manager = makeManager()

        await manager.deactivate()

        XCTAssertFalse(manager.isPro, "Local deactivation must succeed even if the network call fails")
        XCTAssertNil(store.load())
    }

    // MARK: Masked key display

    func testMaskedKeyShowsOnlyLastFourCharacters() async throws {
        let manager = makeManager()
        try await manager.activate(key: "ABCD-EFGH-IJKL-WXYZ")
        XCTAssertEqual(manager.maskedKey?.hasSuffix("WXYZ"), true)
        XCTAssertEqual(manager.maskedKey?.contains("IJKL"), false, "Masked key must not reveal the middle of the key")
    }
}
