#if canImport(Network)

import Foundation

/// Customization points for an ``HTTPServer``, beyond its main request handler.
///
/// Every method has a default implementation, so a conformer implements only the
/// behavior it wants to change. A server started without a delegate — or whose
/// delegate leaves a method defaulted — uses the library's built-in behavior.
/// New customization points are added here as new defaulted methods, so
/// ``HTTPServer/start(name:port:listenOnAllInterfaces:requiresAuthentication:maxRequestBodySize:maxConnections:readTimeout:bodyReadTimeout:idleTimeout:startTimeout:cors:delegate:handler:)``
/// never grows another parameter for them.
///
/// The server **retains** its delegate for its lifetime. Because the delegate is
/// injected at `start(...)` rather than assigned as a back-reference, this does
/// not create a reference cycle unless the delegate itself strongly holds the
/// server — keep the delegate a leaf, or break the cycle yourself.
public protocol HTTPServerDelegate: AnyObject, Sendable {
    /// The response to send for a *recoverable* parse error — one where the
    /// request line and headers are well-formed but the request can't be accepted
    /// in full (today only an over-limit body, HTTP 413). The body was drained and
    /// is unavailable, and the main request handler is intentionally **not**
    /// invoked, so a handler can never mistake a rejected request for a normal one.
    ///
    /// The default returns a generic status + reason-phrase response
    /// (``HTTPServer/defaultErrorResponse(for:)``). Override to supply a
    /// consumer-specific body — e.g. a JSON error the client can parse. The server
    /// still stamps CORS headers on whatever you return.
    ///
    /// Fatal parse errors (malformed framing, header smuggling, etc.) are always
    /// answered by the library and never routed here.
    func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse

    /// Runs `body`, which serves one connection: reading the request, running the
    /// handler, and writing the response. The server's own responses (407, 408, 413,
    /// and so on) are written inside it too.
    ///
    /// `body` returns once the response has been handed to the network stack, so
    /// anything wrapped around it covers the whole exchange with the client. That's
    /// what makes it the place to keep the process alive for a connection, e.g. with
    /// a background-task assertion. Wrapping only the handler would miss both ends:
    /// the client sending the request body before the handler runs, and the server
    /// writing the response after it returns.
    ///
    /// The default runs `body` and nothing else.
    func withConnectionActivity(_ body: () async -> Void) async
}

public extension HTTPServerDelegate {
    func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse {
        HTTPServer.defaultErrorResponse(for: error)
    }

    func withConnectionActivity(_ body: () async -> Void) async {
        await body()
    }
}

#endif // canImport(Network)
