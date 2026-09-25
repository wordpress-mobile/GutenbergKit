package org.wordpress.gutenberg

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.net.HttpURLConnection
import java.net.Socket
import java.net.URL

class HttpServerAuthenticationTests {

    private lateinit var server: HttpServer

    @Before
    fun setUp() {
        server = HttpServer(
            name = "auth-test",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
    }

    @After
    fun tearDown() {
        server.stop()
    }

    @Test
    fun `request without token returns 407 with Content-Type and Proxy-Authenticate`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        try {
            assertEquals(407, conn.responseCode)
            assertEquals("text/plain", conn.getHeaderField("Content-Type"))
            assertEquals("Bearer", conn.getHeaderField("Proxy-Authenticate"))
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `request with wrong token returns 407`() {
        val response = send(server, listOf("Proxy-Authorization" to "Bearer wrong-token"))
        assertEquals(407, response.status)
        assertEquals("Bearer", response.headers["proxy-authenticate"])
    }

    @Test
    fun `request with valid token returns 200`() {
        assertEquals(200, send(server, listOf("Proxy-Authorization" to "Bearer ${server.token}")).status)
    }

    @Test
    fun `request with lowercase 'bearer' scheme returns 200`() {
        assertEquals(200, send(server, listOf("Proxy-Authorization" to "bearer ${server.token}")).status)
    }

    @Test
    fun `request with uppercase 'BEARER' scheme returns 200`() {
        assertEquals(200, send(server, listOf("Proxy-Authorization" to "BEARER ${server.token}")).status)
    }

    // Relay-Authorization (fetch()-compatible alternative)

    @Test
    fun `Relay-Authorization with valid token returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Relay-Authorization", "Bearer ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `Relay-Authorization with wrong token returns 407`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Relay-Authorization", "Bearer wrong-token")
        try {
            assertEquals(407, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `Relay-Authorization with lowercase 'bearer' scheme returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Relay-Authorization", "bearer ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `Authorization header passes through to handler alongside Relay-Authorization`() {
        server.stop()

        var receivedAuth: String? = null
        val authServer = HttpServer(
            name = "auth-test-relay-passthrough",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { request ->
                receivedAuth = request.header("Authorization")
                HttpResponse(body = "OK\n".toByteArray())
            }
        )
        authServer.start()
        try {
            val conn = URL("http://127.0.0.1:${authServer.port}/test").openConnection() as HttpURLConnection
            conn.setRequestProperty("Relay-Authorization", "Bearer ${authServer.token}")
            conn.setRequestProperty("Authorization", "Basic dXNlcjpwYXNz")
            try {
                assertEquals(200, conn.responseCode)
                assertEquals("Basic dXNlcjpwYXNz", receivedAuth)
            } finally {
                conn.disconnect()
            }
        } finally {
            authServer.stop()
        }
    }

    @Test
    fun `Proxy-Authorization takes precedence over Relay-Authorization`() {
        val response = send(
            server,
            listOf(
                "Proxy-Authorization" to "Bearer ${server.token}",
                "Relay-Authorization" to "Bearer wrong"
            )
        )
        assertEquals(200, response.status)
    }

    // Authorization Passthrough

    @Test
    fun `Authorization header passes through to handler alongside Proxy-Authorization`() {
        var receivedAuth: String? = null

        server.stop()
        val authServer = HttpServer(
            name = "auth-test-passthrough",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { request ->
                receivedAuth = request.header("Authorization")
                HttpResponse(body = "OK\n".toByteArray())
            }
        )
        authServer.start()
        try {
            val response = send(
                authServer,
                listOf(
                    "Proxy-Authorization" to "Bearer ${authServer.token}",
                    "Authorization" to "Basic dXNlcjpwYXNz"
                )
            )
            assertEquals(200, response.status)
            assertEquals("Basic dXNlcjpwYXNz", receivedAuth)
        } finally {
            authServer.stop()
        }
    }

    // CORS Preflight (OPTIONS) Auth Exemption

    @Test
    fun `OPTIONS without token returns 200 (CORS preflight exempt from auth)`() {
        assertEquals(200, send(server, emptyList(), method = "OPTIONS").status)
    }

    @Test
    fun `GET without token still returns 407 (only OPTIONS is exempt)`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        try {
            assertEquals(407, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    // Content-Length Requirement

    @Test
    fun `POST without Content-Length returns 411`() {
        val response = send(
            server,
            listOf("Proxy-Authorization" to "Bearer ${server.token}"),
            method = "POST"
        )
        assertEquals(411, response.status)
    }

    @Test
    fun `GET without Content-Length returns 200`() {
        assertEquals(200, send(server, listOf("Proxy-Authorization" to "Bearer ${server.token}")).status)
    }

    @Test
    fun `POST with Content-Length returns 200`() {
        val response = send(
            server,
            listOf("Proxy-Authorization" to "Bearer ${server.token}"),
            method = "POST",
            body = "hello".toByteArray()
        )
        assertEquals(200, response.status)
    }

    // Oversized Payloads (auth precedes drain)

    @Test
    fun `oversized request without token returns 407, not 413`() {
        val smallServer = oversizedTestServer()
        try {
            // Auth is checked on headers alone, before the oversized body is
            // drained or the handler runs — so the request is rejected with
            // 407, not answered with the library's 413. An unauthenticated
            // client must not be able to make the server read (and discard)
            // an arbitrarily large body. The body is declared but never sent,
            // so a server that read it before checking auth would never answer.
            val response = send(
                smallServer,
                emptyList(),
                method = "POST",
                contentLength = OVERSIZED_BODY_SIZE
            )
            assertEquals(407, response.status)
        } finally {
            smallServer.stop()
        }
    }

    @Test
    fun `oversized request with valid token is answered 413 by the library, bypassing the handler`() {
        val smallServer = oversizedTestServer()
        try {
            // The library answers a recoverable parse error itself; the handler
            // (which would return 200 "OK") is never invoked for a rejected
            // request.
            val response = send(
                smallServer,
                listOf("Proxy-Authorization" to "Bearer ${smallServer.token}"),
                method = "POST",
                body = ByteArray(OVERSIZED_BODY_SIZE)
            )
            assertEquals(413, response.status)
        } finally {
            smallServer.stop()
        }
    }

    /**
     * Sends a request to [target] over a raw socket. `HttpURLConnection` can't
     * send `Proxy-Authorization`: since JDK-8384708 it strips that header from
     * non-proxied connections.
     *
     * Sends `Content-Length` only when [contentLength] is set, which defaults to
     * [body]'s size. Headers are flushed before the body so the server can act on
     * them before the body arrives, as it would with a real client.
     */
    private fun send(
        target: HttpServer,
        headers: List<Pair<String, String>>,
        method: String = "GET",
        body: ByteArray? = null,
        contentLength: Int? = body?.size
    ): RawResponse {
        Socket("127.0.0.1", target.port).use { sock ->
            sock.soTimeout = SOCKET_TIMEOUT_MS
            val head = buildString {
                append("$method /test HTTP/1.1\r\nHost: 127.0.0.1\r\n")
                headers.forEach { (name, value) -> append("$name: $value\r\n") }
                if (contentLength != null) append("Content-Length: $contentLength\r\n")
                append("\r\n")
            }
            val output = sock.getOutputStream()
            output.write(head.toByteArray())
            output.flush()
            body?.let {
                output.write(it)
                output.flush()
            }

            val reader = sock.getInputStream().bufferedReader()
            val status = reader.readLine().split(" ")[1].toInt()
            val responseHeaders = generateSequence { reader.readLine() }
                .takeWhile { it.isNotEmpty() }
                .associate { line ->
                    val (name, value) = line.split(":", limit = 2)
                    name.trim().lowercase() to value.trim()
                }
            return RawResponse(status, responseHeaders)
        }
    }

    /** A response's status code and headers, keyed by lowercase name. */
    private class RawResponse(val status: Int, val headers: Map<String, String>)

    /** A server whose 1 KB body limit lets a 2 KB POST exercise the drain path. Its
     *  handler only ever answers valid requests — a rejected (oversized) request is
     *  answered by the library, not here. */
    private fun oversizedTestServer(): HttpServer {
        val smallServer = HttpServer(
            name = "auth-drain-test",
            externallyAccessible = false,
            requiresAuthentication = true,
            maxBodySize = 1024L,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        smallServer.start()
        return smallServer
    }

    // Auth Disabled

    @Test
    fun `authentication disabled passes through without token`() {
        server.stop()

        val noAuthServer = HttpServer(
            name = "auth-test-no-auth",
            externallyAccessible = false,
            requiresAuthentication = false,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        noAuthServer.start()
        try {
            val conn = URL("http://127.0.0.1:${noAuthServer.port}/test").openConnection() as HttpURLConnection
            try {
                assertEquals(200, conn.responseCode)
            } finally {
                conn.disconnect()
            }
        } finally {
            noAuthServer.stop()
        }
    }

    companion object {
        /** Twice the oversized test server's 1 KB `maxBodySize`. */
        private const val OVERSIZED_BODY_SIZE = 2048

        /** Fails a test that gets no response rather than hanging it. */
        private const val SOCKET_TIMEOUT_MS = 5000
    }
}
