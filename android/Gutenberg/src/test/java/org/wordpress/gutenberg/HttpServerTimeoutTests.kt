package org.wordpress.gutenberg

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import org.wordpress.gutenberg.http.HTTPRequestParseError

/**
 * Covers the split read-timeout model: the pre-body phase (headers + drain) is
 * bounded by `readTimeoutMs`, while an accepted body is bounded by the generous
 * `bodyReadTimeoutMs` plus the per-read idle timeout. Also covers rejecting an
 * auth-exempt OPTIONS request that carries a body.
 */
class HttpServerTimeoutTests {

    @Test
    fun `body that streams steadily past readTimeout still succeeds`() {
        // Pre-body cap is short; the body ceiling and idle timeout are generous.
        // A body streamed over a span longer than readTimeoutMs (but with no gap
        // longer than idleTimeoutMs) must complete — the pre-body cap must not
        // bound the accepted body.
        val server = HttpServer(
            name = "timeout-steady-body",
            externallyAccessible = false,
            requiresAuthentication = true,
            readTimeoutMs = 500,
            bodyReadTimeoutMs = 20_000,
            idleTimeoutMs = 5_000,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                val out = sock.getOutputStream()
                // Five 4-byte chunks, 200 ms apart → ~1s of body transfer, well past
                // the 500 ms pre-body cap, with each gap far under the 5s idle timeout.
                val chunks = List(5) { "data".toByteArray() }
                val contentLength = chunks.sumOf { it.size }
                val header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\n" +
                    "Proxy-Authorization: Bearer ${server.token}\r\n" +
                    "Content-Length: $contentLength\r\n\r\n"
                out.write(header.toByteArray())
                out.flush()
                for (chunk in chunks) {
                    Thread.sleep(200)
                    out.write(chunk)
                    out.flush()
                }
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertEquals("HTTP/1.1 200 OK", statusLine)
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun `body stalled beyond idleTimeout returns 408 even with a generous ceiling`() {
        // readTimeoutMs and bodyReadTimeoutMs are long, so only the idle timeout can
        // end this connection. A body that stops mid-transfer must still be reaped
        // promptly with a 408 — the idle guard is intact.
        val server = HttpServer(
            name = "timeout-stalled-body",
            externallyAccessible = false,
            requiresAuthentication = true,
            readTimeoutMs = 10_000,
            bodyReadTimeoutMs = 10_000,
            idleTimeoutMs = 500,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                val out = sock.getOutputStream()
                // Declare 100 bytes but send only 10, then stop. The server waits one
                // idle interval for more body bytes, gets none, and returns 408.
                val header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\n" +
                    "Proxy-Authorization: Bearer ${server.token}\r\n" +
                    "Content-Length: 100\r\n\r\n"
                out.write(header.toByteArray())
                out.write(ByteArray(10))
                out.flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertTrue("expected 408, got: $statusLine", statusLine!!.startsWith("HTTP/1.1 408"))
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun `auth-exempt OPTIONS carrying a body is rejected with 400`() {
        val server = HttpServer(
            name = "options-with-body",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                // A real CORS preflight is bodyless; an OPTIONS with a body must not
                // be read/drained on the auth-exempt path.
                val raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\n\r\nhello"
                sock.getOutputStream().write(raw.toByteArray())
                sock.getOutputStream().flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertTrue("expected 400, got: $statusLine", statusLine!!.startsWith("HTTP/1.1 400"))
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun `auth-exempt OPTIONS with an oversized body is rejected with 400, not drained`() {
        val server = HttpServer(
            name = "options-oversized-body",
            externallyAccessible = false,
            requiresAuthentication = true,
            maxBodySize = 16L,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                // Content-Length exceeds the max body size, so the parser would
                // otherwise enter the drain path — the OPTIONS-with-body guard must
                // reject it first.
                val raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 1000\r\n\r\n"
                sock.getOutputStream().write(raw.toByteArray())
                sock.getOutputStream().flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertTrue("expected 400, got: $statusLine", statusLine!!.startsWith("HTTP/1.1 400"))
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun `a recoverable parse error is answered by the library and never reaches the handler`() {
        val handlerCalled = AtomicBoolean(false)
        val server = HttpServer(
            name = "recoverable-default",
            externallyAccessible = false,
            requiresAuthentication = false,
            maxBodySize = 16L,
            handler = {
                handlerCalled.set(true)
                HttpResponse(body = "OK\n".toByteArray())
            }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                // A 100-byte body far exceeds the 16-byte limit → payloadTooLarge, a
                // recoverable error. With no delegate, the library answers 413.
                val header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n"
                sock.getOutputStream().write(header.toByteArray())
                sock.getOutputStream().write(ByteArray(100) { 0x61 })
                sock.getOutputStream().flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertTrue("expected 413, got: $statusLine", statusLine!!.startsWith("HTTP/1.1 413"))
            }
            assertFalse("a rejected request must never reach the handler", handlerCalled.get())
        } finally {
            server.stop()
        }
    }

    @Test
    fun `a delegate customizes the recoverable-error response`() {
        val delegate = object : HttpServerDelegate {
            override fun responseForRecoverableParseError(error: HTTPRequestParseError): HttpResponse =
                HttpResponse(status = error.httpStatus, body = "custom-error-body".toByteArray())
        }
        val server = HttpServer(
            name = "recoverable-delegate",
            externallyAccessible = false,
            requiresAuthentication = false,
            maxBodySize = 16L,
            delegate = delegate,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                val header = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n"
                sock.getOutputStream().write(header.toByteArray())
                sock.getOutputStream().write(ByteArray(100) { 0x61 })
                sock.getOutputStream().flush()
                val response = sock.getInputStream().bufferedReader().readText()
                assertTrue("expected 413, got: $response", response.startsWith("HTTP/1.1 413"))
                assertTrue("expected the delegate's body, got: $response", response.contains("custom-error-body"))
            }
        } finally {
            server.stop()
        }
    }

    @Test
    fun `bodyless OPTIONS preflight still succeeds`() {
        val server = HttpServer(
            name = "options-bodyless",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                val raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
                sock.getOutputStream().write(raw.toByteArray())
                sock.getOutputStream().flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertEquals("HTTP/1.1 200 OK", statusLine)
            }
        } finally {
            server.stop()
        }
    }
}
