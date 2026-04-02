package org.wordpress.gutenberg.http

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.gson.Gson
import com.google.gson.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Base64

/**
 * Instrumented fixture tests for the pure-Kotlin HTTP parser.
 *
 * Runs the same shared JSON test fixtures as the JVM unit tests,
 * but executes on an actual Android device/emulator to validate
 * the parser under the Android runtime (ART).
 */
@RunWith(AndroidJUnit4::class)
class InstrumentedFixtureTests {

    // MARK: - Header Value Fixtures

    @Test
    fun headerValueExtraction() {
        val fixtures = loadFixture("header-value-parsing")
        val tests = fixtures.getAsJsonArray("tests")

        for (element in tests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val parameter = test.get("parameter").asString
            val headerValue = test.get("headerValue").asString
            val expected = if (test.get("expected").isJsonNull) null else test.get("expected").asString

            val result = HeaderValue.extractParameter(parameter, headerValue)
            assertEquals("$description: result mismatch", expected, result)
        }
    }

    // MARK: - Request Parsing Fixtures

    @Test
    fun requestParsingBasicCases() {
        val fixtures = loadFixture("request-parsing")
        val tests = fixtures.getAsJsonArray("tests")

        for (element in tests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val input = test.get("input").asString
            val expected = test.getAsJsonObject("expected")

            val parser: HTTPRequestParser
            if (test.has("maxBodySize")) {
                val maxBodySize = test.get("maxBodySize").asLong
                parser = HTTPRequestParser(maxBodySize)
                parser.append(input.toByteArray(Charsets.UTF_8))
            } else {
                parser = HTTPRequestParser(input)
            }

            if (test.has("appendAfterComplete")) {
                val extra = test.get("appendAfterComplete").asString
                parser.append(extra.toByteArray(Charsets.UTF_8))
            }

            if (expected.has("isComplete") && !expected.get("isComplete").asBoolean &&
                expected.has("hasHeaders") && !expected.get("hasHeaders").asBoolean
            ) {
                assertTrue("$description: should not have headers", !parser.state.hasHeaders)
                assertNull("$description: parseRequest should return null", parser.parseRequest())
                continue
            }

            val request = parser.parseRequest()
            assertNotNull("$description: parseRequest returned null", request)
            request!!

            if (expected.has("method")) {
                assertEquals("$description: method", expected.get("method").asString, request.method)
            }
            if (expected.has("target")) {
                assertEquals("$description: target", expected.get("target").asString, request.target)
            }
            if (expected.has("isComplete") && expected.get("isComplete").asBoolean) {
                assertTrue("$description: isComplete", parser.state.isComplete)
            }
            if (expected.has("headers")) {
                val expectedHeaders = expected.getAsJsonObject("headers")
                for (entry in expectedHeaders.entrySet()) {
                    assertEquals(
                        "$description: header ${entry.key}",
                        entry.value.asString,
                        request.header(entry.key)
                    )
                }
            }
            if (expected.has("body")) {
                if (expected.get("body").isJsonNull) {
                    assertNull("$description: body should be null", request.body)
                } else {
                    val expectedBody = expected.get("body").asString
                    assertNotNull("$description: body should not be null", request.body)
                    assertEquals(
                        "$description: body content",
                        expectedBody,
                        String(request.body!!.readBytes(), Charsets.UTF_8)
                    )
                }
            }
        }
    }

    @Test
    fun requestParsingErrorCases() {
        val fixtures = loadFixture("request-parsing")
        val errorTests = fixtures.getAsJsonArray("errorTests")

        for (element in errorTests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val expected = test.getAsJsonObject("expected")
            val expectedError = expected.get("error").asString

            val parser: HTTPRequestParser

            if (test.has("inputBase64")) {
                val base64 = test.get("inputBase64").asString
                val data = Base64.getDecoder().decode(base64)
                parser = if (test.has("maxBodySize")) {
                    HTTPRequestParser(test.get("maxBodySize").asLong)
                } else {
                    HTTPRequestParser()
                }
                parser.append(data)
            } else {
                val input = test.get("input").asString
                if (test.has("maxBodySize")) {
                    parser = HTTPRequestParser(test.get("maxBodySize").asLong)
                    parser.append(input.toByteArray(Charsets.UTF_8))
                } else {
                    parser = HTTPRequestParser(input)
                }
            }

            try {
                parser.parseRequest()
                // Non-fatal errors (e.g., payloadTooLarge) are exposed via
                // pendingParseError instead of being thrown.
                val pendingError = parser.pendingParseError
                if (pendingError != null) {
                    assertEquals(
                        expectedError,
                        pendingError.errorId,
                        "$description: expected $expectedError but got ${pendingError.errorId}"
                    )
                } else {
                    fail("$description: expected error $expectedError but parsing succeeded")
                }
            } catch (e: HTTPRequestParseException) {
                assertEquals(
                    expectedError,
                    e.error.errorId,
                    "$description: expected $expectedError but got ${e.error.errorId}"
                )
            }
        }
    }

    @Test
    fun requestParsingIncrementalCases() {
        val fixtures = loadFixture("request-parsing")
        val incrementalTests = fixtures.getAsJsonArray("incrementalTests")

        for (element in incrementalTests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val expected = test.getAsJsonObject("expected")

            val parser = HTTPRequestParser()

            if (test.has("input") && test.has("chunkSize")) {
                val input = test.get("input").asString
                val chunkSize = test.get("chunkSize").asInt
                val data = input.toByteArray(Charsets.UTF_8)
                var i = 0
                while (i < data.size) {
                    val end = minOf(i + chunkSize, data.size)
                    parser.append(data.copyOfRange(i, end))
                    i = end
                }
            } else if (test.has("headers")) {
                val headers = test.get("headers").asString
                parser.append(headers.toByteArray(Charsets.UTF_8))

                if (expected.has("afterHeaders")) {
                    val afterHeaders = expected.getAsJsonObject("afterHeaders")
                    if (afterHeaders.has("hasHeaders")) {
                        assertEquals(
                            "$description: hasHeaders after headers",
                            afterHeaders.get("hasHeaders").asBoolean,
                            parser.state.hasHeaders
                        )
                    }
                    if (afterHeaders.has("isComplete")) {
                        assertEquals(
                            "$description: isComplete after headers",
                            afterHeaders.get("isComplete").asBoolean,
                            parser.state.isComplete
                        )
                    }
                    if (afterHeaders.has("method") || afterHeaders.has("target")) {
                        val partialRequest = parser.parseRequest()
                        assertNotNull("$description: partial request should not be null", partialRequest)
                        partialRequest!!
                        if (afterHeaders.has("method")) {
                            assertEquals(afterHeaders.get("method").asString, partialRequest.method)
                        }
                        if (afterHeaders.has("target")) {
                            assertEquals(afterHeaders.get("target").asString, partialRequest.target)
                        }
                    }
                }

                if (test.has("bodyChunks")) {
                    for (chunkElement in test.getAsJsonArray("bodyChunks")) {
                        parser.append(chunkElement.asString.toByteArray(Charsets.UTF_8))
                    }
                }
            } else if (test.has("input")) {
                parser.append(test.get("input").asString.toByteArray(Charsets.UTF_8))
            }

            if (expected.has("isComplete") && !expected.get("isComplete").asBoolean &&
                expected.has("hasHeaders") && !expected.get("hasHeaders").asBoolean
            ) {
                assertTrue("$description: should not have headers", !parser.state.hasHeaders)
                assertNull("$description: parseRequest should return null", parser.parseRequest())
                continue
            }

            val request = parser.parseRequest()
            assertNotNull("$description: parseRequest returned null", request)
            request!!

            if (expected.has("method")) {
                assertEquals("$description: method", expected.get("method").asString, request.method)
            }
            if (expected.has("target")) {
                assertEquals("$description: target", expected.get("target").asString, request.target)
            }
            if (expected.has("isComplete") && expected.get("isComplete").asBoolean) {
                assertTrue("$description: isComplete", parser.state.isComplete)
            }
            if (expected.has("body")) {
                if (expected.get("body").isJsonNull) {
                    assertNull("$description: body should be null", request.body)
                } else {
                    val expectedBody = expected.get("body").asString
                    assertNotNull("$description: body should not be null", request.body)
                    assertEquals(
                        "$description: body content",
                        expectedBody,
                        String(request.body!!.readBytes(), Charsets.UTF_8)
                    )
                }
            }
        }
    }

    // MARK: - Multipart Parsing Fixtures

    @Test
    fun multipartParsingCases() {
        val fixtures = loadFixture("multipart-parsing")
        val tests = fixtures.getAsJsonArray("tests")

        for (element in tests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val boundary = test.get("boundary").asString
            val quotedBoundary = test.has("quotedBoundary") && test.get("quotedBoundary").asBoolean
            val rawBody = test.get("rawBody").asString

            val request = buildRawMultipartRequest(rawBody, boundary, quotedBoundary)

            val expected = test.getAsJsonObject("expected")
            if (expected.has("contentType")) {
                assertEquals(
                    "$description: Content-Type",
                    expected.get("contentType").asString,
                    request.header("Content-Type")
                )
            }

            val parts = request.multipartParts()
            val expectedParts = expected.getAsJsonArray("parts")
            assertEquals("$description: part count", expectedParts.size(), parts.size)

            for (i in 0 until minOf(expectedParts.size(), parts.size)) {
                val exp = expectedParts[i].asJsonObject
                val part = parts[i]
                assertPart(description, i, exp, part)
            }
        }
    }

    @Test
    fun multipartParsingErrorCases() {
        val fixtures = loadFixture("multipart-parsing")
        val errorTests = fixtures.getAsJsonArray("errorTests")

        for (element in errorTests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val expected = test.getAsJsonObject("expected")
            val expectedError = expected?.get("error")?.asString ?: test.get("expectedError").asString
            val contentType = test.get("contentType")?.asString ?: expected?.get("contentType")?.asString

            val request: ParsedHTTPRequest

            if (test.has("rawBody") && test.has("boundary")) {
                request = buildRawMultipartRequest(
                    test.get("rawBody").asString,
                    test.get("boundary").asString
                )
            } else if (contentType != null && test.has("body")) {
                val body = test.get("body").asString
                val raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n" +
                    "Content-Type: $contentType\r\n" +
                    "Content-Length: ${body.toByteArray(Charsets.UTF_8).size}\r\n\r\n$body"
                val parser = HTTPRequestParser(raw)
                val parsed = parser.parseRequest()
                assertNotNull("$description: parsing request failed", parsed)
                request = parsed!!
            } else if (contentType != null) {
                val raw = "GET /upload HTTP/1.1\r\nHost: localhost\r\n" +
                    "Content-Type: $contentType\r\n\r\n"
                val parser = HTTPRequestParser(raw)
                val parsed = parser.parseRequest()
                assertNotNull("$description: parsing request failed", parsed)
                request = parsed!!
            } else {
                fail("$description: invalid error test case")
                return
            }

            try {
                request.multipartParts()
                fail("$description: expected error $expectedError but succeeded")
            } catch (e: MultipartParseException) {
                assertEquals(
                    expectedError,
                    e.error.errorId,
                    "$description: expected $expectedError but got ${e.error.errorId}"
                )
            }
        }
    }

    // MARK: - Helpers

    private fun loadFixture(name: String): JsonObject {
        val context = InstrumentationRegistry.getInstrumentation().context
        val json = context.assets.open("http/$name.json").bufferedReader().readText()
        return Gson().fromJson(json, JsonObject::class.java)
    }

    private fun assertPart(description: String, i: Int, exp: JsonObject, part: MultipartPart) {
        assertEquals("$description: part[$i].name", exp.get("name").asString, part.name)
        if (exp.has("filename")) {
            if (exp.get("filename").isJsonNull) {
                assertNull("$description: part[$i].filename should be null", part.filename)
            } else {
                assertEquals("$description: part[$i].filename", exp.get("filename").asString, part.filename)
            }
        }
        if (exp.has("contentType")) {
            assertEquals("$description: part[$i].contentType", exp.get("contentType").asString, part.contentType)
        }
        if (exp.has("body")) {
            assertEquals(
                "$description: part[$i].body",
                exp.get("body").asString,
                String(part.body.readBytes(), Charsets.UTF_8)
            )
        }
    }

    private fun buildRawMultipartRequest(
        body: String,
        boundary: String,
        quotedBoundary: Boolean = false
    ): ParsedHTTPRequest {
        val boundaryParam = if (quotedBoundary) "\"$boundary\"" else boundary
        val raw = "POST /wp/v2/media HTTP/1.1\r\nHost: localhost\r\n" +
            "Content-Type: multipart/form-data; boundary=$boundaryParam\r\n" +
            "Content-Length: ${body.toByteArray(Charsets.UTF_8).size}\r\n\r\n$body"
        val parser = HTTPRequestParser(raw)
        return parser.parseRequest()!!
    }
}
