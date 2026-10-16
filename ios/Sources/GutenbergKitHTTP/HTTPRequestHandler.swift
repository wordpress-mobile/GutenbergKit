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
/// The server retains its handler for its lifetime, so a handler must not strongly
/// hold the object that owns the server, directly or transitively:
/// `owner → HTTPServer → handler → owner` is a cycle, the owner's `deinit` never runs,
/// and `stop()` is never called — a silently stranded listener, not a crash.
///
/// A value type is **not** protection. A `struct` handler storing the owner closes the
/// same ring: the server captures the struct into a heap node, and its stored properties
/// are strong edges out of it. This protocol is deliberately **not** `AnyObject`-constrained
/// so a handler *can* be a `struct` holding only what it needs — not because a `struct` is
/// safe by construction. Either shape works; both must stay leaves, the same discipline
/// ``HTTPServerDelegate`` documents.
///
/// The usual trap is the object that starts the server also serving it — a view controller
/// starting it in `viewDidLoad` and stopping it in `deinit` is the shape that bites, because
/// the cycle disables the very teardown meant to break it. Conform a separate leaf type, or
/// call `stop()` from a hook that does run.
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
