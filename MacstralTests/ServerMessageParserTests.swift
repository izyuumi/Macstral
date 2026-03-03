import XCTest
@testable import Macstral

final class ServerMessageParserTests: XCTestCase {

    // MARK: - delta

    func testDeltaNonIncremental() throws {
        let json = #"{"type":"delta","text":"hello","is_incremental":false}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .delta(text, isIncremental, _, _) = result else {
            XCTFail("Expected .delta, got \(result)"); return
        }
        XCTAssertEqual(text, "hello")
        XCTAssertFalse(isIncremental)
    }

    func testDeltaIncremental() throws {
        let json = #"{"type":"delta","text":"hello world","is_incremental":true}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .delta(text, isIncremental, _, _) = result else {
            XCTFail("Expected .delta, got \(result)"); return
        }
        XCTAssertEqual(text, "hello world")
        XCTAssertTrue(isIncremental)
    }

    func testDeltaDefaultsIsIncrementalToFalseWhenAbsent() throws {
        let json = #"{"type":"delta","text":"hi"}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .delta(_, isIncremental, _, _) = result else {
            XCTFail("Expected .delta, got \(result)"); return
        }
        XCTAssertFalse(isIncremental)
    }

    func testDeltaWithTimingFields() throws {
        let json = #"{"type":"delta","text":"hi","is_incremental":false,"first_chunk_to_first_delta_ms":42.5,"feed_audio_ms":10.1}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .delta(_, _, firstChunk, feedAudio) = result else {
            XCTFail("Expected .delta, got \(result)"); return
        }
        XCTAssertEqual(firstChunk, 42.5, accuracy: 0.001)
        XCTAssertEqual(feedAudio, 10.1, accuracy: 0.001)
    }

    func testDeltaMissingTimingFieldsAreNil() throws {
        let json = #"{"type":"delta","text":"hi","is_incremental":false}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .delta(_, _, firstChunk, feedAudio) = result else {
            XCTFail("Expected .delta, got \(result)"); return
        }
        XCTAssertNil(firstChunk)
        XCTAssertNil(feedAudio)
    }

    // MARK: - done

    func testDone() throws {
        let json = #"{"type":"done","text":"final transcript","finalize_ms":150.0}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .done(text, finalizeMs) = result else {
            XCTFail("Expected .done, got \(result)"); return
        }
        XCTAssertEqual(text, "final transcript")
        XCTAssertEqual(finalizeMs, 150.0, accuracy: 0.001)
    }

    func testDoneMissingFinalizeMs() throws {
        let json = #"{"type":"done","text":"done"}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .done(_, finalizeMs) = result else {
            XCTFail("Expected .done, got \(result)"); return
        }
        XCTAssertNil(finalizeMs)
    }

    // MARK: - error

    func testError() throws {
        let json = #"{"type":"error","text":"something went wrong"}"#
        let result = try XCTUnwrap(parseServerMessage(json))
        guard case let .error(message) = result else {
            XCTFail("Expected .error, got \(result)"); return
        }
        XCTAssertEqual(message, "something went wrong")
    }

    // MARK: - malformed input

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(parseServerMessage("not json at all"))
    }

    func testMissingTypeFieldReturnsNil() {
        XCTAssertNil(parseServerMessage(#"{"text":"hello"}"#))
    }

    func testMissingTextField() {
        XCTAssertNil(parseServerMessage(#"{"type":"delta"}"#))
    }

    func testUnknownTypeReturnsNil() {
        XCTAssertNil(parseServerMessage(#"{"type":"ping","text":"hello"}"#))
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(parseServerMessage(""))
    }
}
