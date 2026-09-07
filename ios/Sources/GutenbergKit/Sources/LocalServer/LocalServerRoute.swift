#if canImport(Network)

import GutenbergKitHTTP

/// One route on the editor's local HTTP server.
///
/// The server hands each request to the first registered route whose
/// ``handles(_:)`` accepts it, in registration order, so a route decides only
/// whether a request is its own and how to answer it. The server owns
/// everything shared across routes: the listener, the bearer token, the origin
/// check, CORS, and the body limits.
protocol LocalServerRoute: Sendable {
    /// Whether this route answers `request`.
    func handles(_ request: ParsedHTTPRequest) -> Bool

    /// Answers a request that ``handles(_:)`` accepted.
    func handle(_ request: HTTPServer.Request) async -> HTTPResponse
}

#endif // canImport(Network)
