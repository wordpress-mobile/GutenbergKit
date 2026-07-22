package org.wordpress.gutenberg

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.net.HttpURLConnection
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
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "Bearer wrong-token")
        try {
            assertEquals(407, conn.responseCode)
            assertEquals("Bearer", conn.getHeaderField("Proxy-Authenticate"))
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `request with valid token returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "Bearer ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `request with lowercase 'bearer' scheme returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "bearer ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `request with uppercase 'BEARER' scheme returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "BEARER ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
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
        java.net.Socket("127.0.0.1", server.port).use { sock ->
            val raw = "GET /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer ${server.token}\r\nRelay-Authorization: Bearer wrong\r\n\r\n"
            sock.getOutputStream().write(raw.toByteArray())
            sock.getOutputStream().flush()
            val statusLine = sock.getInputStream().bufferedReader().readLine()
            assertEquals("HTTP/1.1 200 OK", statusLine)
        }
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
            val conn = URL("http://127.0.0.1:${authServer.port}/test").openConnection() as HttpURLConnection
            conn.setRequestProperty("Proxy-Authorization", "Bearer ${authServer.token}")
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

    // CORS Preflight (OPTIONS) Auth Exemption

    @Test
    fun `OPTIONS without token returns 200 (CORS preflight exempt from auth)`() {
        java.net.Socket("127.0.0.1", server.port).use { sock ->
            val raw = "OPTIONS /test HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            sock.getOutputStream().write(raw.toByteArray())
            sock.getOutputStream().flush()
            val statusLine = sock.getInputStream().bufferedReader().readLine()
            assertEquals("HTTP/1.1 200 OK", statusLine)
        }
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
        // HttpURLConnection always adds Content-Length, so use a raw socket.
        java.net.Socket("127.0.0.1", server.port).use { sock ->
            val raw = "POST /test HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Authorization: Bearer ${server.token}\r\n\r\n"
            sock.getOutputStream().write(raw.toByteArray())
            sock.getOutputStream().flush()
            val statusLine = sock.getInputStream().bufferedReader().readLine()
            assertEquals("HTTP/1.1 411 Length Required", statusLine)
        }
    }

    @Test
    fun `GET without Content-Length returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "Bearer ${server.token}")
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    @Test
    fun `POST with Content-Length returns 200`() {
        val conn = URL("http://127.0.0.1:${server.port}/test").openConnection() as HttpURLConnection
        conn.setRequestProperty("Proxy-Authorization", "Bearer ${server.token}")
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.outputStream.write("hello".toByteArray())
        conn.outputStream.flush()
        try {
            assertEquals(200, conn.responseCode)
        } finally {
            conn.disconnect()
        }
    }

    // Oversized Payloads (auth precedes drain)

    @Test
    fun `oversized request without token returns 407, not 413`() {
        val smallServer = oversizedTestServer()
        try {
            val conn = oversizedPost(smallServer)
            try {
                // Auth is checked on headers alone, before the oversized body is
                // drained or the handler runs — so the request is rejected with
                // 407, not answered with the handler's 413. An unauthenticated
                // client must not be able to make the server read (and discard)
                // an arbitrarily large body.
                assertEquals(407, conn.responseCode)
            } finally {
                conn.disconnect()
            }
        } finally {
            smallServer.stop()
        }
    }

    @Test
    fun `oversized request with valid token reaches handler as serverError 413`() {
        val smallServer = oversizedTestServer()
        try {
            val conn = oversizedPost(smallServer) {
                it.setRequestProperty("Proxy-Authorization", "Bearer ${smallServer.token}")
            }
            try {
                assertEquals(413, conn.responseCode)
            } finally {
                conn.disconnect()
            }
        } finally {
            smallServer.stop()
        }
    }

    /** A server whose 1 KB body limit lets a 2 KB POST exercise the drain path. */
    private fun oversizedTestServer(): HttpServer {
        val smallServer = HttpServer(
            name = "auth-drain-test",
            externallyAccessible = false,
            requiresAuthentication = true,
            maxBodySize = 1024L,
            handler = { request ->
                request.serverError?.let { error ->
                    HttpResponse(status = error.httpStatus, body = "too large".toByteArray())
                } ?: HttpResponse(body = "OK\n".toByteArray())
            }
        )
        smallServer.start()
        return smallServer
    }

    /** Sends a 2 KB POST to [smallServer], applying [configure] before writing the body. */
    private fun oversizedPost(
        smallServer: HttpServer,
        configure: (HttpURLConnection) -> Unit = {}
    ): HttpURLConnection {
        val conn = URL("http://127.0.0.1:${smallServer.port}/test").openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        configure(conn)
        conn.doOutput = true
        conn.setFixedLengthStreamingMode(OVERSIZED_BODY_SIZE)
        conn.outputStream.use { it.write(ByteArray(OVERSIZED_BODY_SIZE)) }
        return conn
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
    }
}
