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
}

public extension HTTPServerDelegate {
    func response(forRecoverableParseError error: HTTPRequestParseError) -> HTTPResponse {
        HTTPServer.defaultErrorResponse(for: error)
    }
}

#endif // canImport(Network)
