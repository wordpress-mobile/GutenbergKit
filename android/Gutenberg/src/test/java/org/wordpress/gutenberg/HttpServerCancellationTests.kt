package org.wordpress.gutenberg

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Covers the "connection close cancels the in-flight handler" behaviour. Once a
 * request has been fully read, no bytes flow on the connection until the
 * response is sent, so a handler awaiting slow outbound work (the media-upload
 * relay awaiting `POST /wp/v2/media`) leaves the connection idle. If the peer
 * closes it during that window — what the editor WebView does when it aborts an
 * upload — the handler's coroutine must be cancelled so the outbound work is torn
 * down instead of running to completion and orphaning an attachment.
 */
class HttpServerCancellationTests {

    @Test
    fun `peer closing the connection cancels an in-flight handler`() {
        val handlerStarted = CountDownLatch(1)
        val cancelled = AtomicBoolean(false)
        val finishedNormally = AtomicBoolean(false)

        val server = HttpServer(
            name = "cancel-on-close",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = {
                handlerStarted.countDown()
                try {
                    // Stands in for slow outbound work. A cancelled coroutine
                    // throws here promptly, well before the delay would elapse.
                    delay(10_000)
                    finishedNormally.set(true)
                    HttpResponse(body = "OK\n".toByteArray())
                } catch (e: CancellationException) {
                    cancelled.set(true)
                    throw e
                }
            }
        )
        server.start()
        try {
            val sock = Socket("127.0.0.1", server.port)
            sock.soTimeout = 30_000
            val request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\n" +
                "Proxy-Authorization: Bearer ${server.token}\r\n" +
                "Content-Length: 0\r\n\r\n"
            sock.getOutputStream().write(request.toByteArray())
            sock.getOutputStream().flush()

            // Once the handler is running, abort by closing the client side of the
            // connection — exactly what an aborted fetch does.
            assertTrue("handler never started", handlerStarted.await(5, TimeUnit.SECONDS))
            sock.close()

            // The handler must observe cancellation promptly, not run its 10s delay.
            val deadline = System.currentTimeMillis() + 3_000
            while (System.currentTimeMillis() < deadline && !cancelled.get()) {
                Thread.sleep(20)
            }
            assertTrue("handler should have been cancelled", cancelled.get())
            assertFalse("handler should not have completed normally", finishedNormally.get())
        } finally {
            server.stop()
        }
    }

    @Test
    fun `handler that finishes first still sends its response despite the watcher`() {
        // The close watcher must not interfere with the normal path: a handler
        // that completes before any close still produces a response on the live
        // connection.
        val server = HttpServer(
            name = "no-close-normal-response",
            externallyAccessible = false,
            requiresAuthentication = true,
            handler = { HttpResponse(body = "OK\n".toByteArray()) }
        )
        server.start()
        try {
            Socket("127.0.0.1", server.port).use { sock ->
                sock.soTimeout = 30_000
                val request = "POST /upload HTTP/1.1\r\nHost: 127.0.0.1\r\n" +
                    "Proxy-Authorization: Bearer ${server.token}\r\n" +
                    "Content-Length: 0\r\n\r\n"
                sock.getOutputStream().write(request.toByteArray())
                sock.getOutputStream().flush()
                val statusLine = sock.getInputStream().bufferedReader().readLine()
                assertEquals("HTTP/1.1 200 OK", statusLine)
            }
        } finally {
            server.stop()
        }
    }
}
