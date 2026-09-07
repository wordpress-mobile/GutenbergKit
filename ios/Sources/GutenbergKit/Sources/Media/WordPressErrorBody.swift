#if canImport(Network)

import Foundation
import GutenbergKitHTTP

extension HTTPErrorBody {

    /// A WordPress-REST-style `{code, message}` error.
    ///
    /// The editor normalizes every failure through the same middleware, so the
    /// local server's own errors — the relay's, the upload route's, and the
    /// refusals the HTTP library raises before either runs — reach JavaScript
    /// in the shape it already understands, surfacing `message` rather than a
    /// generic parse failure.
    ///
    /// The shape belongs to GutenbergKit rather than to `GutenbergKitHTTP`,
    /// which serves whatever body its consumer hands it and knows nothing about
    /// WordPress.
    static func wordPressError(code: String, message: String) -> HTTPErrorBody {
        let payload = ["code": code, "message": message]
        // A `[String: String]` is always serializable, so the fallback is
        // unreachable in practice; it is a fixed literal rather than an
        // interpolation so the fallback itself cannot produce invalid JSON.
        let data = (try? JSONSerialization.data(withJSONObject: payload))
            ?? Data(#"{"code":"unknown_error","message":"The request failed."}"#.utf8)
        return HTTPErrorBody(contentType: "application/json", data: data)
    }
}

extension HTTPResponse {

    /// A response carrying a WordPress-REST-style error, with any headers the
    /// route adds ahead of the body's `Content-Type`.
    static func wordPressError(
        status: Int,
        code: String,
        message: String,
        headers: [(String, String)] = []
    ) -> HTTPResponse {
        let body = HTTPErrorBody.wordPressError(code: code, message: message)
        return HTTPResponse(
            status: status,
            headers: headers + [("Content-Type", body.contentType)],
            body: body.data
        )
    }
}

#endif // canImport(Network)
