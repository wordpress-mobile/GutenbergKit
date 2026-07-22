package org.wordpress.gutenberg

import android.util.Log
import org.wordpress.gutenberg.http.HTTPRequestParser
import org.wordpress.gutenberg.http.HTTPRequestParseException
import org.wordpress.gutenberg.http.TempFileOwner
import java.io.BufferedInputStream
import java.io.File
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Semaphore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * A received HTTP request.
 *
 * @property method The HTTP method (e.g., "GET", "POST").
 * @property target The request target (e.g., "/path?query=1").
 * @property headers The request headers as an ordered map.
 * @property body The request body, or null if there is no body.
 * @property parseDurationMs Time spent receiving and parsing the request, in milliseconds.
 */
data class HttpRequest(
    val method: String,
    val target: String,
    val headers: Map<String, String>,
    val body: org.wordpress.gutenberg.http.RequestBody? = null,
    val parseDurationMs: Double = 0.0,
    /** A server-detected error that occurred after headers were parsed
     *  (e.g., payload too large). When set, the handler is responsible
     *  for building an appropriate error response. */
    val serverError: org.wordpress.gutenberg.http.HTTPRequestParseError? = null
) {
    /**
     * The path portion of [target], without the query component
     * (e.g., "/wp/v2/posts" for "/wp/v2/posts?per_page=10").
     *
     * Use this for routing — matching against [target] fails as soon as a
     * client appends a query string.
     */
    val path: String
        get() = target.substringBefore('?')

    /**
     * The query component of [target], including the leading "?"
     * (e.g., "?per_page=10"), or an empty string when there is no query.
     */
    val query: String
        get() = target.substringAfter('?', "").let { if (it.isEmpty()) "" else "?$it" }

    /**
     * Returns the value of the first header matching the given name (case-insensitive).
     */
    fun header(name: String): String? {
        val lowered = name.lowercase()
        return headers.entries.firstOrNull { it.key.lowercase() == lowered }?.value
    }
}

/**
 * An HTTP response to send back to a client.
 *
 * @property status The HTTP status code (e.g., 200, 404).
 * @property headers Additional response headers.
 * @property body The response body. The entire body is held in memory. This is
 *   fine for the current use case (Gutenberg REST API payloads — JSON, HTML,
 *   CSS, JS) which are small. If large responses (e.g., media downloads) need
 *   to be proxied in the future, this could be replaced with a streaming
 *   abstraction similar to [RequestBody][org.wordpress.gutenberg.http.RequestBody].
 */
data class HttpResponse(
    val status: Int = 200,
    val headers: Map<String, String> = mapOf("Content-Type" to "text/plain"),
    val body: ByteArray = ByteArray(0)
)

/** CORS behavior for an [HttpServer]. */
enum class CorsPolicy {
    /** No CORS headers are added (the default). */
    None,

    /**
     * Permissive CORS for a loopback-only server serving a WebView: allows any
     * origin and the methods/headers this library's clients use. The server
     * answers OPTIONS preflight requests itself and stamps these headers on every
     * response — including ones it generates internally (timeouts, parse errors)
     * that never reach the handler.
     */
    Permissive;

    /** Headers added to every response under this policy. */
    val responseHeaders: Map<String, String>
        get() = when (this) {
            None -> emptyMap()
            Permissive -> mapOf(
                "Access-Control-Allow-Origin" to "*",
                "Access-Control-Allow-Methods" to "GET, POST, PUT, DELETE, OPTIONS",
                "Access-Control-Allow-Headers" to "Authorization, Relay-Authorization, Content-Type",
                "Access-Control-Max-Age" to "86400"
            )
        }
}

/**
 * Returns a copy with [newHeaders] added, skipping any whose name
 * (case-insensitive) is already present.
 */
private fun HttpResponse.addingHeadersIfAbsent(newHeaders: Map<String, String>): HttpResponse {
    if (newHeaders.isEmpty()) return this
    val existing = headers.keys.map { it.lowercase() }.toSet()
    val toAdd = newHeaders.filterKeys { it.lowercase() !in existing }
    if (toAdd.isEmpty()) return this
    return copy(headers = headers + toAdd)
}

/**
 * A lightweight local HTTP/1.1 server.
 *
 * Listens on a system-assigned port and dispatches each incoming request
 * to a caller-provided [handler]. Uses the pure-Kotlin HTTP parser for
 * request parsing. Includes connection limits, read timeouts, bearer token
 * authentication, and request size limits to prevent resource exhaustion.
 *
 * ## Security
 *
 * The server itself is a generic request dispatcher — it does not forward
 * requests or act as a proxy. SSRF protection is intentionally left to the
 * [handler] implementation, since the server cannot know which upstream hosts
 * are legitimate. The server provides two layers of defence by default:
 *
 * 1. Binds to loopback (localhost only) unless [externallyAccessible] is set.
 * 2. Requires a randomly-generated bearer token on every request (when
 *    [requiresAuthentication] is enabled). Accepts the token in either
 *    `Proxy-Authorization` (RFC 9110 §11.7.1, for native clients) or
 *    `Relay-Authorization` (for browser `fetch()`, where `Proxy-*` headers
 *    are forbidden). Both keep `Authorization` free for upstream credentials.
 *
 * ## CORS
 *
 * When [requiresAuthentication] is enabled, `OPTIONS` requests are exempt
 * from authentication because CORS preflight requests never include
 * credentials (Fetch spec §3.3.5). However, the server does not generate
 * CORS response headers — this is the handler's responsibility.
 *
 * When proxying to a remote server, the upstream response will typically
 * include the correct CORS headers already — pass it through unaltered.
 * When serving local content, the handler must return appropriate headers
 * for `OPTIONS` requests, typically:
 *
 *     Access-Control-Allow-Origin: <origin>
 *     Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
 *     Access-Control-Allow-Headers: Authorization, Relay-Authorization, Content-Type
 *     Access-Control-Max-Age: 86400
 *
 * Without these headers, browsers will reject the preflight and block
 * the actual request. A handler that returns 404 for unrecognized methods
 * will silently break CORS for browser clients.
 *
 * ## Connection Model
 *
 * Each connection handles exactly one request (`Connection: close`). HTTP
 * keep-alive / pipelining is intentionally unsupported. This simplifies body
 * framing — in particular, GET/DELETE requests with unexpected body data are
 * safe because leftover bytes are discarded when the connection closes. If
 * keep-alive were ever added, body framing for all methods would need to be
 * enforced to prevent request smuggling.
 *
 * @property name A stable identifier for this server instance. Must be consistent across
 *   runs of the same logical server. Used to namespace temporary files so that multiple
 *   server instances don't interfere with each other's orphan cleanup. Each distinct server
 *   should have a unique name. It is the caller's responsibility to choose a descriptive,
 *   collision-free identifier (e.g. `"media-proxy"`, `"editor-assets"`).
 *
 * ```kotlin
 * val server = HttpServer(
 *     name = "media-proxy",
 *     externallyAccessible = true,
 *     handler = { request ->
 *         println("${request.method} ${request.target} (${"%.2f".format(request.parseDurationMs)}ms)")
 *         HttpResponse(body = "OK\n".toByteArray())
 *     }
 * )
 * server.start()
 * println("Listening on port ${server.port}, token: ${server.token}")
 * // ...
 * server.stop()
 * ```
 */
@Suppress("LongParameterList")
class HttpServer(
    val name: String,
    private val requestedPort: Int = 0,
    private val externallyAccessible: Boolean,
    private val requiresAuthentication: Boolean = true,
    private val maxConnections: Int = DEFAULT_MAX_CONNECTIONS,
    private val maxBodySize: Long = DEFAULT_MAX_BODY_SIZE,
    private val readTimeoutMs: Int = DEFAULT_READ_TIMEOUT_MS,
    private val idleTimeoutMs: Int = DEFAULT_IDLE_TIMEOUT_MS,
    private val cacheDir: File? = null,
    private val cors: CorsPolicy = CorsPolicy.None,
    private val handler: suspend (HttpRequest) -> HttpResponse
) {
    @Volatile
    private var serverSocket: ServerSocket? = null
    private var scope: CoroutineScope? = null
    private val connectionSemaphore = Semaphore(maxConnections)
    private val stateLock = Any()
    private val TAG = "GutenbergKit.HTTP"
    private val tempSubdir = "gutenberg-http-${sanitizeName(name)}"

    @Volatile
    private var running = false

    /**
     * A bearer token required in the `Proxy-Authorization` header of every
     * request.  Uses `Proxy-Authorization` (RFC 9110 §11.7.1) rather than
     * `Authorization` so that the client's own `Authorization` header
     * (e.g. HTTP Basic credentials for the upstream server) passes through
     * to the handler untouched.  Generated randomly on each server instance creation.
     */
    val token: String = generateToken()

    /** The port the server is listening on, or 0 if not started. */
    val port: Int get() = serverSocket?.localPort ?: 0

    /** Starts the server. If already running, this is a no-op. */
    fun start() {
        synchronized(stateLock) {
            if (running) return

            // Clean up temp files left behind by previous runs (e.g., crash or process kill).
            cacheDir?.let { TempFileOwner.cleanOrphans(it, tempSubdir) }

            val bindAddress = if (externallyAccessible) {
                InetAddress.getByName("0.0.0.0")
            } else {
                InetAddress.getLoopbackAddress()
            }
            serverSocket = ServerSocket(requestedPort, maxConnections, bindAddress)
            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            running = true
            Log.i(TAG, "HTTP server started on port ${serverSocket!!.localPort}")

            scope!!.launch(Dispatchers.IO) {
                while (running) {
                    try {
                        val socket = serverSocket?.accept() ?: break
                        if (!connectionSemaphore.tryAcquire()) {
                            socket.close()
                            continue
                        }
                        launch {
                            try {
                                handleConnection(socket)
                            } finally {
                                connectionSemaphore.release()
                            }
                        }
                    } catch (_: SocketException) {
                        // Expected when stop() closes the server socket.
                        break
                    } catch (e: Exception) {
                        Log.e(TAG, "Accept loop terminated unexpectedly", e)
                        running = false
                        break
                    }
                }
            }
        }
    }

    /** Stops the server and releases resources. */
    fun stop() {
        synchronized(stateLock) {
            running = false
            try {
                serverSocket?.close()
            } catch (_: Exception) {
                // ignore
            }
            serverSocket = null
            // Cancelling the scope cancels both the accept loop and all
            // in-flight connection handlers. The blocking accept() call
            // is unblocked by closing the server socket above.
            scope?.cancel()
            scope = null
            Log.i(TAG, "HTTP server stopped")
        }
    }

    private suspend fun handleConnection(socket: Socket) {
        socket.use { sock ->
            try {
                sock.soTimeout = idleTimeoutMs
                handleRequest(sock)
            } catch (_: SocketTimeoutException) {
                // RFC 9110 §15.5.9: send 408 before closing on read timeout.
                try {
                    sendResponse(sock, HttpResponse(
                        status = 408,
                        body = "Request Timeout".toByteArray()
                    ))
                } catch (_: Exception) {
                    // Best-effort — socket may already be broken.
                }
            } catch (e: Exception) {
                Log.w(TAG, "Connection error", e)
            }
        }
    }

    private suspend fun handleRequest(socket: Socket) {
        val input = BufferedInputStream(socket.getInputStream())

        val parser = HTTPRequestParser(maxBodySize = maxBodySize, cacheDir = cacheDir, tempSubdir = tempSubdir)
        parser.use {
            val parseStart = System.nanoTime()
            // Note: the deadline is checked between reads, not during a blocking
            // read. Since each read can block for up to idleTimeoutMs (soTimeout),
            // the effective maximum time is readTimeoutMs + idleTimeoutMs. This is
            // a bounded imprecision — slow-loris protection is still effective
            // because the attacker must send data to keep the connection alive,
            // and each time data arrives the loop iterates and checks the deadline.
            val deadlineNanos = parseStart + readTimeoutMs * 1_000_000L
            val buffer = ByteArray(READ_CHUNK_SIZE)

            // Phase 1: receive headers only.
            readUntil(parser, input, buffer, deadlineNanos) { it.hasHeaders }

            // Validate headers (triggers full RFC validation).
            val partial = try {
                parser.parseRequest()
            } catch (e: HTTPRequestParseException) {
                val statusText = STATUS_TEXT[e.error.httpStatus] ?: "Bad Request"
                sendResponse(socket, HttpResponse(
                    status = e.error.httpStatus,
                    body = statusText.toByteArray()
                ))
                return
            } catch (_: java.io.IOException) {
                sendResponse(socket, HttpResponse(
                    status = 500,
                    body = "Internal Server Error".toByteArray()
                ))
                return
            }

            if (partial == null) {
                sendResponse(socket, HttpResponse(
                    status = 400,
                    body = "Bad Request".toByteArray()
                ))
                return
            }

            // Check auth on headers alone, before draining or consuming any
            // body bytes — an unauthenticated client must not be able to make
            // the server read (and discard) an arbitrarily large body, and the
            // handler must never see an unauthenticated request.
            // OPTIONS is exempt because CORS preflight requests
            // never include credentials (Fetch spec §3.3.5).
            if (requiresAuthentication && partial.method.uppercase() != "OPTIONS") {
                val proxyAuth = partial.header("Proxy-Authorization")
                    ?: partial.header("Relay-Authorization")
                if (!authenticate(proxyAuth, token)) {
                    sendResponse(socket, HttpResponse(
                        status = 407,
                        headers = mapOf("Content-Type" to "text/plain", "Proxy-Authenticate" to "Bearer")
                    ))
                    return
                }
            }

            // Drain the oversized body before responding so the (authenticated)
            // client receives the 413 instead of a connection reset
            // (RFC 9110 §15.5.14).
            if (parser.state == HTTPRequestParser.State.DRAINING) {
                readUntil(parser, input, buffer, deadlineNanos) { it.isComplete }
            }

            // If the parser detected a non-fatal error (e.g., payload too
            // large after drain), let the handler build the response.
            parser.pendingParseError?.let { error ->
                val parseDurationMs = (System.nanoTime() - parseStart) / 1_000_000.0
                val request = HttpRequest(
                    method = partial.method,
                    target = partial.target,
                    headers = partial.headers,
                    parseDurationMs = parseDurationMs,
                    serverError = error
                )
                val response = try {
                    handler(request)
                } catch (e: Exception) {
                    Log.e(TAG, "Handler threw", e)
                    HttpResponse(
                        status = error.httpStatus,
                        body = (STATUS_TEXT[error.httpStatus] ?: "Error").toByteArray()
                    )
                }
                sendResponse(socket, response)
                Log.d(TAG, "${partial.method} ${partial.target} → ${response.status} (${"%.1f".format(parseDurationMs)}ms)")
                return
            }

            // Reject body-bearing methods without Content-Length.
            // We don't support Transfer-Encoding: chunked, so
            // Content-Length is the only way to determine body size.
            val upperMethod = partial.method.uppercase()
            if (upperMethod in listOf("POST", "PUT", "PATCH") && partial.header("Content-Length") == null) {
                sendResponse(socket, HttpResponse(
                    status = 411,
                    body = "Length Required".toByteArray()
                ))
                return
            }

            // Phase 2: receive body (skipped if already complete).
            readUntil(parser, input, buffer, deadlineNanos) { it.isComplete }

            // Final parse with body.
            val parsed = try {
                parser.parseRequest()
            } catch (e: HTTPRequestParseException) {
                val statusText = STATUS_TEXT[e.error.httpStatus] ?: "Bad Request"
                sendResponse(socket, HttpResponse(
                    status = e.error.httpStatus,
                    body = statusText.toByteArray()
                ))
                return
            } catch (_: java.io.IOException) {
                sendResponse(socket, HttpResponse(
                    status = 500,
                    body = "Internal Server Error".toByteArray()
                ))
                return
            }
            val parseDurationMs = (System.nanoTime() - parseStart) / 1_000_000.0

            // Connection closed before request was complete — send 400.
            if (parsed == null || !parsed.isComplete) {
                parsed?.body?.fileOwner?.close()
                sendResponse(socket, HttpResponse(
                    status = 400,
                    body = "Bad Request".toByteArray()
                ))
                return
            }

            // Clean up the temp file backing the request body on all exit
            // paths. The body (and any multipart parts derived from it) share
            // a single TempFileOwner — .use{} guarantees it is closed whether
            // we return normally, return early, or throw.
            parsed.body?.fileOwner.use {
                val request = HttpRequest(
                    method = parsed.method,
                    target = parsed.target,
                    headers = parsed.headers,
                    body = parsed.body,
                    parseDurationMs = parseDurationMs
                )
                val response = resolveResponse(request)
                sendResponse(socket, response)
                Log.d(TAG, "${parsed.method} ${parsed.target} → ${response.status} (${"%.1f".format(parseDurationMs)}ms)")
            }
        }
    }

    /** Reads data into the parser until [condition] is satisfied or the connection closes. */
    private fun readUntil(
        parser: HTTPRequestParser,
        input: BufferedInputStream,
        buffer: ByteArray,
        deadlineNanos: Long,
        condition: (HTTPRequestParser.State) -> Boolean
    ) {
        while (!condition(parser.state)) {
            if (System.nanoTime() > deadlineNanos) {
                throw SocketTimeoutException("Read deadline exceeded")
            }
            val bytesRead = input.read(buffer)
            if (bytesRead == -1) break
            parser.append(buffer.copyOfRange(0, bytesRead))
        }
    }

    /**
     * Resolves the response for a request: the CORS preflight (under a permissive
     * policy) or the handler's response. Kept separate from [handleRequest] so
     * that already-complex function doesn't grow.
     */
    private suspend fun resolveResponse(request: HttpRequest): HttpResponse {
        if (cors == CorsPolicy.Permissive && request.method.uppercase() == "OPTIONS") {
            return HttpResponse(status = 204, body = ByteArray(0))
        }
        return try {
            handler(request)
        } catch (e: Exception) {
            Log.e(TAG, "Handler threw", e)
            HttpResponse(status = 500, body = "Internal Server Error".toByteArray())
        }
    }

    private fun sendResponse(socket: Socket, response: HttpResponse) {
        val decorated = response.addingHeadersIfAbsent(cors.responseHeaders)
        val output = socket.getOutputStream()
        output.write(serializeResponse(decorated))
        output.flush()
    }

    companion object {
        /** Default maximum number of concurrent connections. */
        const val DEFAULT_MAX_CONNECTIONS: Int = 5

        /** Default maximum request body size (4 GB). */
        const val DEFAULT_MAX_BODY_SIZE: Long = 4L * 1024 * 1024 * 1024

        /** Default read timeout in milliseconds (30 seconds). */
        const val DEFAULT_READ_TIMEOUT_MS: Int = 30_000

        /**
         * Default idle timeout in milliseconds (5 seconds).
         * If no data arrives within this interval on a single read,
         * the connection is closed with a 408 response. Prevents slow-loris
         * attacks where an attacker drip-feeds bytes to hold a connection slot.
         */
        const val DEFAULT_IDLE_TIMEOUT_MS: Int = 5_000

        /** Chunk size for reading request data. */
        private const val READ_CHUNK_SIZE: Int = 65536

        /** Standard English reason phrases per RFC 9110 / RFC 9112 §4. */
        private val STATUS_TEXT = mapOf(
            // 1xx Informational
            100 to "Continue",
            101 to "Switching Protocols",
            102 to "Processing",
            103 to "Early Hints",
            // 2xx Success
            200 to "OK",
            201 to "Created",
            202 to "Accepted",
            203 to "Non-Authoritative Information",
            204 to "No Content",
            205 to "Reset Content",
            206 to "Partial Content",
            207 to "Multi-Status",
            208 to "Already Reported",
            226 to "IM Used",
            // 3xx Redirection
            300 to "Multiple Choices",
            301 to "Moved Permanently",
            302 to "Found",
            303 to "See Other",
            304 to "Not Modified",
            307 to "Temporary Redirect",
            308 to "Permanent Redirect",
            // 4xx Client Error
            400 to "Bad Request",
            401 to "Unauthorized",
            402 to "Payment Required",
            403 to "Forbidden",
            404 to "Not Found",
            405 to "Method Not Allowed",
            406 to "Not Acceptable",
            407 to "Proxy Authentication Required",
            408 to "Request Timeout",
            409 to "Conflict",
            410 to "Gone",
            411 to "Length Required",
            412 to "Precondition Failed",
            413 to "Content Too Large",
            414 to "URI Too Long",
            415 to "Unsupported Media Type",
            416 to "Range Not Satisfiable",
            417 to "Expectation Failed",
            421 to "Misdirected Request",
            422 to "Unprocessable Content",
            423 to "Locked",
            424 to "Failed Dependency",
            425 to "Too Early",
            426 to "Upgrade Required",
            428 to "Precondition Required",
            429 to "Too Many Requests",
            431 to "Request Header Fields Too Large",
            451 to "Unavailable For Legal Reasons",
            // 5xx Server Error
            500 to "Internal Server Error",
            501 to "Not Implemented",
            502 to "Bad Gateway",
            503 to "Service Unavailable",
            504 to "Gateway Timeout",
            505 to "HTTP Version Not Supported",
            506 to "Variant Also Negotiates",
            507 to "Insufficient Storage",
            508 to "Loop Detected",
            510 to "Not Extended",
            511 to "Network Authentication Required"
        )

        /**
         * Serializes an HTTP response to raw bytes per RFC 9112 §4.
         */
        // Headers excluded during serialization: hop-by-hop headers (RFC 9110 §7.6.1)
        // plus headers that are always recalculated (Content-Length, Date, Server).
        private val RESPONSE_HOP_BY_HOP = setOf(
            "connection", "transfer-encoding", "keep-alive",
            "proxy-connection", "te", "upgrade", "trailer",
            "date", "server"
        )

        internal fun serializeResponse(response: HttpResponse): ByteArray {
            val statusText = STATUS_TEXT[response.status] ?: "Unknown"
            val sb = StringBuilder()
            val clampedStatus = response.status.coerceIn(0, 999)
            sb.append("HTTP/1.1 %03d %s\r\n".format(clampedStatus, statusText))

            for ((key, value) in response.headers) {
                val lower = key.lowercase()
                // Skip Content-Length (always recalculated) and hop-by-hop headers.
                if (lower == "content-length") continue
                if (lower in RESPONSE_HOP_BY_HOP) continue
                val cleanKey = sanitizeHeaderString(key)
                val cleanValue = sanitizeHeaderString(value)
                if (cleanKey.isNotEmpty()) {
                    sb.append("$cleanKey: $cleanValue\r\n")
                }
            }

            sb.append("Content-Length: ${response.body.size}\r\n")
            sb.append("Connection: close\r\n")
            sb.append("Date: ${httpDate()}\r\n")
            sb.append("Server: GutenbergKit\r\n")

            sb.append("\r\n")
            return sb.toString().toByteArray(Charsets.UTF_8) + response.body
        }

        /**
         * Strips control characters per RFC 9110 §5.5. Preserves HTAB (0x09)
         * and obs-text (0x80+), which the RFC explicitly allows in field values.
         */
        private fun sanitizeHeaderString(value: String): String {
            return buildString(value.length) {
                for (c in value) {
                    val code = c.code
                    if (code == 0x09 || code in 0x20..0x7E || code >= 0x80) {
                        append(c)
                    }
                }
            }
        }

        /**
         * Validates the proxy bearer token from the request.
         *
         * Accepts the token in either:
         * - `Proxy-Authorization` — the standard HTTP header for proxy credentials
         *   (RFC 9110 §11.7.1), usable from native HTTP clients.
         * - `Relay-Authorization` — a non-forbidden alternative usable from
         *   browser `fetch()`, where `Proxy-*` headers are silently stripped
         *   (Fetch spec §2.2.2).
         *
         * Both headers keep the client's `Authorization` header available for
         * upstream credentials.
         *
         * Uses constant-time comparison to prevent timing attacks.
         */
        private fun authenticate(proxyAuth: String?, expectedToken: String): Boolean {
            if (proxyAuth == null) return false
            val prefix = "Bearer "
            if (!proxyAuth.startsWith(prefix, ignoreCase = true)) return false
            val provided = proxyAuth.substring(prefix.length)
            return constantTimeEqual(provided, expectedToken)
        }

        /**
         * Compares two strings in constant time to prevent timing attacks.
         *
         * Always iterates over the expected token ([b]) regardless of the input
         * length, so timing reveals neither whether lengths match nor how many
         * bytes are correct. When lengths differ, [b] is compared against itself
         * to keep the work constant.
         *
         * **Do not replace this with `MessageDigest.isEqual()`.**
         * On Android API 24–32 (our minSdk through Android 12),
         * `isEqual()` returns early when array lengths differ — leaking
         * the expected token length via timing.  The fully constant-time
         * fix (JDK-8295919) only shipped in Android 13 (API 33).  The
         * constant-time property is also only an `@implNote`, not a spec
         * guarantee, so other runtimes are not obligated to honour it.
         *
         * **Do not "simplify" this to an early-return on length mismatch.**
         * An early return would let an attacker measure response time to discover
         * the expected token length, even though the token length is currently
         * fixed at 64 hex characters. This implementation is intentionally
         * branch-free in the hot path to avoid leaking any information.
         */
        private fun constantTimeEqual(a: String, b: String): Boolean {
            val aBytes = a.toByteArray(Charsets.UTF_8)
            val bBytes = b.toByteArray(Charsets.UTF_8)
            val comparand = if (aBytes.size == bBytes.size) aBytes else bBytes
            var result: Int = if (aBytes.size == bBytes.size) 0 else 1
            for (i in bBytes.indices) {
                result = result or (comparand[i].toInt() xor bBytes[i].toInt())
            }
            return result == 0
        }

        /** Formats the current time as an HTTP-date per RFC 9110 §5.6.7. */
        private fun httpDate(): String {
            val fmt = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("GMT")
            return fmt.format(Date())
        }

        /**
         * Strips characters from [name] that are not letters, digits, `.`, `-`, or `_`.
         *
         * The server name is embedded in filesystem paths (temp directory).
         * Allowing arbitrary characters (e.g. `../`) would enable path traversal.
         */
        private fun sanitizeName(name: String): String {
            val sanitized = name.filter { it.isLetterOrDigit() || it in ".-_" }
            require(sanitized.isNotEmpty()) {
                "Server name must contain at least one alphanumeric character, dot, hyphen, or underscore"
            }
            return sanitized
        }

        /** Generates a cryptographically random 64-character hex token. */
        private fun generateToken(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }

        /** Returns the device's local IPv4 address on the network, or null. */
        @JvmStatic
        fun getLocalIpAddress(): String? {
            return try {
                NetworkInterface.getNetworkInterfaces()?.toList()
                    ?.flatMap { it.inetAddresses.toList() }
                    ?.firstOrNull { !it.isLoopbackAddress && it is Inet4Address }
                    ?.hostAddress
            } catch (_: Exception) {
                null
            }
        }
    }
}

/** A logged HTTP request with timestamp. */
data class RequestLogEntry(
    val timestamp: Date,
    val method: String,
    val target: String,
    val requestBodySize: Int = 0,
    val parseDurationMs: Double = 0.0
)
