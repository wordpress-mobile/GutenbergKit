import Foundation
import Testing

@testable import GutenbergKit

@Suite
struct GutenbergJSExceptionTests {

    private func baseException(
        debugImages: [[String: Any]]? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "TypeError",
            "message": "boom",
            "stacktrace": [
                ["function": "fn", "filename": "~/assets/editor-abc.js", "lineno": 22, "colno": 247]
            ],
            "context": [:],
            "tags": [:],
            "isHandled": false,
            "handledBy": "window.error"
        ]
        if let debugImages {
            dict["debug_images"] = debugImages
        }
        return dict
    }

    @Test("Decodes debug images when present")
    func decodesDebugImages() throws {
        let dict = baseException(debugImages: [
            ["code_file": "~/assets/editor-abc.js", "debug_id": "11111111-1111-1111-1111-111111111111"]
        ])

        let exception = try #require(GutenbergJSException(from: dict))

        #expect(exception.debugImages.count == 1)
        #expect(exception.debugImages.first?.codeFile == "~/assets/editor-abc.js")
        #expect(exception.debugImages.first?.debugID == "11111111-1111-1111-1111-111111111111")
    }

    @Test("Defaults to no debug images when the field is absent")
    func defaultsToEmptyWhenAbsent() throws {
        let exception = try #require(GutenbergJSException(from: baseException()))
        #expect(exception.debugImages.isEmpty)
    }

    @Test("Skips malformed debug images")
    func skipsMalformedDebugImages() throws {
        let dict = baseException(debugImages: [
            ["code_file": "~/assets/editor-abc.js"], // missing debug_id
            ["code_file": "~/assets/index-def.js", "debug_id": "22222222-2222-2222-2222-222222222222"]
        ])

        let exception = try #require(GutenbergJSException(from: dict))

        #expect(exception.debugImages.count == 1)
        #expect(exception.debugImages.first?.debugID == "22222222-2222-2222-2222-222222222222")
    }
}
