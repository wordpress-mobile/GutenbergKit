import Foundation

/// An HTTP response containing body data and headers.
///
/// This struct encapsulates the response from an HTTP request, storing both the
/// response body and headers. It's used throughout the editor for caching API
/// responses and building preload data.
///
/// The `description` property formats the response as JSON suitable for injection
/// into the editor's preload system.
public struct EditorURLResponse: Sendable, Equatable, Codable, Hashable {

    /// The response body data.
    let data: Data

    /// The HTTP response headers.
    let responseHeaders: EditorHTTPHeaders

    /// Creates a response from raw data and an `HTTPURLResponse`.
    ///
    /// - Parameters:
    ///   - data: The response body data.
    ///   - httpUrlResponse: The URL response containing headers.
    init(data: Data, httpUrlResponse: HTTPURLResponse) {
        self.data = data
        self.responseHeaders = EditorHTTPHeaders(httpUrlResponse.allHeaderFields)
    }

    /// Creates a response from raw data and headers.
    ///
    /// - Parameters:
    ///   - data: The response body data.
    ///   - responseHeaders: The HTTP headers.
    init(data: Data, responseHeaders: EditorHTTPHeaders) {
        self.data = data
        self.responseHeaders = responseHeaders
    }

    /// Creates a response from a string body and headers.
    ///
    /// The string is encoded as UTF-8 data.
    ///
    /// - Parameters:
    ///   - string: The response body as a string.
    ///   - responseHeaders: The HTTP headers.
    init(string: String, responseHeaders: EditorHTTPHeaders) {
        self.data = Data(string.utf8)
        self.responseHeaders = responseHeaders
    }

    /// Creates a response from a tuple of data and `HTTPURLResponse`.
    ///
    /// Convenience initializer for working with `URLSession` results.
    ///
    /// - Parameter rawResponse: A tuple containing the response data and URL response.
    init(_ rawResponse: (Data, HTTPURLResponse)) {
        self = EditorURLResponse(data: rawResponse.0, httpUrlResponse: rawResponse.1)
    }

    func toJSON() throws -> JSON {
        .object([
            "body": try JSON(self.data),
            "headers": try responseHeaders.toJSON()
        ])
    }

    /// An empty response with an empty JSON object body and no headers.
    static let empty: EditorURLResponse = EditorURLResponse(string: "{}", responseHeaders: [:])
}
