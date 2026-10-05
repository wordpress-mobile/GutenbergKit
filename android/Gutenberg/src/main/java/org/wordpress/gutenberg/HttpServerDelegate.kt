package org.wordpress.gutenberg

import org.wordpress.gutenberg.http.HTTPRequestParseError

/**
 * Customization points for an [HttpServer], beyond its main request handler.
 *
 * Every method has a default implementation, so a conformer overrides only the
 * behavior it wants to change. A server started without a delegate — or whose
 * delegate leaves a method defaulted — uses the library's built-in behavior. New
 * customization points are added here as new defaulted methods, so the
 * [HttpServer] constructor never grows another parameter for them.
 */
interface HttpServerDelegate {
    /**
     * The response to send for a *recoverable* parse error — one where the request
     * line and headers are well-formed but the request can't be accepted in full
     * (today only an over-limit body, HTTP 413). The body was drained and is
     * unavailable, and the main request handler is intentionally **not** invoked,
     * so a handler can never mistake a rejected request for a normal one.
     *
     * The default returns a generic status + reason-phrase response
     * ([HttpServer.defaultErrorResponse]). Override to supply a consumer-specific
     * body — e.g. a JSON error the client can parse. The server still stamps CORS
     * headers on whatever you return.
     *
     * Fatal parse errors (malformed framing, header smuggling, etc.) are always
     * answered by the library and never routed here.
     */
    fun responseForRecoverableParseError(error: HTTPRequestParseError): HttpResponse =
        HttpServer.defaultErrorResponse(error)
}
