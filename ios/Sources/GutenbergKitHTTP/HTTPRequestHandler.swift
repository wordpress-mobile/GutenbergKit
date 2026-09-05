#if canImport(Network)

import Foundation

/// Serves requests for an ``HTTPServer``.
///
/// The closure form of
/// ``HTTPServer/start(name:port:listenOnAllInterfaces:requiresAuthentication:maxRequestBodySize:maxConnections:readTimeout:bodyReadTimeout:idleTimeout:startTimeout:cors:delegate:handler:)-(_,_,_,_,_,_,_,_,_,_,_,_,@escaping@Sendable(HTTPServer.Request)async->HTTPResponse)``
/// is the right tool for a handler that needs no state. Conform to this instead when
/// the handler has dependencies: they become stored properties, and the request
/// methods become ordinary instance methods rather than statics threading a context
/// parameter through every call.
///
/// ## Lifetimes
///
/// The server retains its handler for its lifetime, and the handler must not be the
/// object that owns the server: `owner → HTTPServer → handler → owner` is a cycle,
/// so the owner's `deinit` would never run and `stop()` would never be called.
///
/// This protocol is deliberately **not** `AnyObject`-constrained, because the
/// straightforward way to avoid that is a `struct` handler holding the dependencies
/// it needs. A value type cannot participate in a reference cycle at all, so the
/// question doesn't arise. A `final class` conformer is fine too — just keep it a
/// leaf, the same discipline ``HTTPServerDelegate`` documents.
public protocol HTTPRequestHandler: Sendable {
    /// The response for a request the server has parsed and authenticated.
    ///
    /// Called once per request, concurrently across connections — hence `Sendable`.
    /// Cancellation is cooperative: the server cancels this task when the client
    /// disconnects or the server stops, and discards whatever a cancelled task
    /// returns, so check `Task.isCancelled` before any side effect you can't undo.
    func handle(_ request: HTTPServer.Request) async -> HTTPResponse
}

#endif // canImport(Network)
