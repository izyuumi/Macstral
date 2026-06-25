import XCTest
@testable import Macstral

final class AIWritingCloudResponseParserTests: XCTestCase {

    func testParsesOpenAIResponsesOutputText() {
        let data = Data(#"{"output_text":"Hi Bob, Friday works for me."}"#.utf8)
        XCTAssertEqual(
            AIWritingCloudResponseParser.parseOpenAIResponses(data),
            "Hi Bob, Friday works for me."
        )
    }

    func testParsesOpenAIResponsesNestedOutputText() {
        let data = Data("""
        {
          "output": [
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": "Nested result." }
              ]
            }
          ]
        }
        """.utf8)
        XCTAssertEqual(AIWritingCloudResponseParser.parseOpenAIResponses(data), "Nested result.")
    }

    func testParsesChatCompletionsContent() {
        let data = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "Chat result."
              }
            }
          ]
        }
        """.utf8)
        XCTAssertEqual(AIWritingCloudResponseParser.parseChatCompletions(data), "Chat result.")
    }

    func testMalformedResponsesReturnNil() {
        XCTAssertNil(AIWritingCloudResponseParser.parseOpenAIResponses(Data("not json".utf8)))
        XCTAssertNil(AIWritingCloudResponseParser.parseChatCompletions(Data("{}".utf8)))
    }
}
