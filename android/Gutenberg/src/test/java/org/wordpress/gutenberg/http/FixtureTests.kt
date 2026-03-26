package org.wordpress.gutenberg.http

import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import org.junit.Test
import java.io.File
import java.util.Base64

/**
 * Fixture-driven tests for the pure-Kotlin HTTP parser.
 *
 * Loads the shared JSON test fixtures (also used by the Swift test suite)
 * and validates the Kotlin implementation against them.
 */
class FixtureTests {

    // MARK: - Header Value Fixtures

    @Test
    fun `header value extraction - all fixture cases pass`() {
        val fixtures = loadFixture("header-value-parsing")
        val tests = fixtures.getAsJsonArray("tests")

        for (element in tests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val parameter = test.get("parameter").asString
            val headerValue = test.get("headerValue").asString
            val expected = if (test.get("expected").isJsonNull) null else test.get("expected").asString

            val result = HeaderValue.extractParameter(parameter, headerValue)
            assertEquals(expected, result, "$description: result mismatch")
        }
    }

    // MARK: - Request Parsing Fixtures

    @Test
    fun `request parsing - all basic cases pass`() {
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

            // Handle needsMoreData case
            if (expected.has("isComplete") && !expected.get("isComplete").asBoolean &&
                expected.has("hasHeaders") && !expected.get("hasHeaders").asBoolean
            ) {
                assertTrue(!parser.state.hasHeaders, "$description: should not have headers")
                assertNull(parser.parseRequest(), "$description: parseRequest should return null")
                continue
            }

            val request = parser.parseRequest()
            assertNotNull(request, "$description: parseRequest returned null")
            request!!

            if (expected.has("method")) {
                assertEquals(expected.get("method").asString, request.method, "$description: method")
            }
            if (expected.has("target")) {
                assertEquals(expected.get("target").asString, request.target, "$description: target")
            }
            if (expected.has("isComplete") && expected.get("isComplete").asBoolean) {
                assertTrue(parser.state.isComplete, "$description: isComplete")
            }
            if (expected.has("headers")) {
                val expectedHeaders = expected.getAsJsonObject("headers")
                for (entry in expectedHeaders.entrySet()) {
                    assertEquals(
                        entry.value.asString,
                        request.header(entry.key),
                        "$description: header ${entry.key}"
                    )
                }
            }

            // Body: check only if key is present in expected
            if (expected.has("body")) {
                if (expected.get("body").isJsonNull) {
                    assertNull(request.body, "$description: body should be null")
                } else {
                    val expectedBody = expected.get("body").asString
                    assertNotNull(request.body, "$description: body should not be null")
                    assertEquals(
                        expectedBody,
                        String(request.body!!.readBytes(), Charsets.UTF_8),
                        "$description: body content"
                    )
                }
            }
        }
    }

    @Test
    fun `request parsing - all error cases pass`() {
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
                fail("$description: expected error $expectedError but parsing succeeded")
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
    fun `request parsing - all incremental cases pass`() {
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

                // Check state after headers
                if (expected.has("afterHeaders")) {
                    val afterHeaders = expected.getAsJsonObject("afterHeaders")
                    if (afterHeaders.has("hasHeaders")) {
                        assertEquals(
                            afterHeaders.get("hasHeaders").asBoolean,
                            parser.state.hasHeaders,
                            "$description: hasHeaders after headers"
                        )
                    }
                    if (afterHeaders.has("isComplete")) {
                        assertEquals(
                            afterHeaders.get("isComplete").asBoolean,
                            parser.state.isComplete,
                            "$description: isComplete after headers"
                        )
                    }
                    if (afterHeaders.has("method") || afterHeaders.has("target")) {
                        val partialRequest = parser.parseRequest()
                        assertNotNull(partialRequest, "$description: partial request should not be null")
                        partialRequest!!
                        if (afterHeaders.has("method")) {
                            assertEquals(
                                afterHeaders.get("method").asString,
                                partialRequest.method,
                                "$description: partial method"
                            )
                        }
                        if (afterHeaders.has("target")) {
                            assertEquals(
                                afterHeaders.get("target").asString,
                                partialRequest.target,
                                "$description: partial target"
                            )
                        }
                    }
                }

                // Append body chunks
                if (test.has("bodyChunks")) {
                    for (chunkElement in test.getAsJsonArray("bodyChunks")) {
                        parser.append(chunkElement.asString.toByteArray(Charsets.UTF_8))
                    }
                }
            } else if (test.has("input")) {
                val input = test.get("input").asString
                parser.append(input.toByteArray(Charsets.UTF_8))
            }

            // Verify final expectations
            if (expected.has("isComplete") && !expected.get("isComplete").asBoolean &&
                expected.has("hasHeaders") && !expected.get("hasHeaders").asBoolean
            ) {
                assertTrue(!parser.state.hasHeaders, "$description: should not have headers")
                assertNull(parser.parseRequest(), "$description: parseRequest should return null")
                continue
            }

            val request = parser.parseRequest()
            assertNotNull(request, "$description: parseRequest returned null")
            request!!

            if (expected.has("method")) {
                assertEquals(expected.get("method").asString, request.method, "$description: method")
            }
            if (expected.has("target")) {
                assertEquals(expected.get("target").asString, request.target, "$description: target")
            }
            if (expected.has("isComplete") && expected.get("isComplete").asBoolean) {
                assertTrue(parser.state.isComplete, "$description: isComplete")
            }
            if (expected.has("body")) {
                if (expected.get("body").isJsonNull) {
                    assertNull(request.body, "$description: body should be null")
                } else {
                    val expectedBody = expected.get("body").asString
                    assertNotNull(request.body, "$description: body should not be null")
                    assertEquals(
                        expectedBody,
                        String(request.body!!.readBytes(), Charsets.UTF_8),
                        "$description: body content"
                    )
                }
            }
        }
    }

    // MARK: - Multipart Parsing Fixtures

    @Test
    fun `multipart parsing - all cases pass`() {
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
                    expected.get("contentType").asString,
                    request.header("Content-Type"),
                    "$description: Content-Type"
                )
            }

            val parts = request.multipartParts()
            val expectedParts = expected.getAsJsonArray("parts")
            assertEquals(expectedParts.size(), parts.size, "$description: part count")

            for (i in 0 until minOf(expectedParts.size(), parts.size)) {
                val exp = expectedParts[i].asJsonObject
                val part = parts[i]

                assertEquals(exp.get("name").asString, part.name, "$description: part[$i].name")

                if (exp.has("filename")) {
                    if (exp.get("filename").isJsonNull) {
                        assertNull(part.filename, "$description: part[$i].filename should be null")
                    } else {
                        assertEquals(
                            exp.get("filename").asString,
                            part.filename,
                            "$description: part[$i].filename"
                        )
                    }
                }
                if (exp.has("contentType")) {
                    assertEquals(
                        exp.get("contentType").asString,
                        part.contentType,
                        "$description: part[$i].contentType"
                    )
                }
                if (exp.has("body")) {
                    val expectedBody = exp.get("body").asString
                    assertEquals(
                        expectedBody,
                        String(part.body.readBytes(), Charsets.UTF_8),
                        "$description: part[$i].body"
                    )
                }
            }
        }
    }

    @Test
    fun `multipart parsing - all error cases pass`() {
        val fixtures = loadFixture("multipart-parsing")
        val errorTests = fixtures.getAsJsonArray("errorTests")

        for (element in errorTests) {
            val test = element.asJsonObject
            val description = test.get("description").asString
            val expected = test.getAsJsonObject("expected")
            val expectedError = expected.get("error").asString
            val contentType = test.get("contentType")?.asString ?: expected.get("contentType")?.asString

            val request: ParsedHTTPRequest

            if (test.has("rawBody") && test.has("boundary")) {
                val rawBody = test.get("rawBody").asString
                val boundary = test.get("boundary").asString
                request = buildRawMultipartRequest(rawBody, boundary)
            } else if (contentType != null && test.has("body")) {
                val body = test.get("body").asString
                val raw = "POST /wp/v2/posts HTTP/1.1\r\nHost: localhost\r\n" +
                    "Content-Type: $contentType\r\n" +
                    "Content-Length: ${body.toByteArray(Charsets.UTF_8).size}\r\n\r\n$body"
                val parser = HTTPRequestParser(raw)
                val parsed = parser.parseRequest()
                assertNotNull(parsed, "$description: parsing request failed")
                request = parsed!!
            } else if (contentType != null) {
                val raw = "GET /upload HTTP/1.1\r\nHost: localhost\r\n" +
                    "Content-Type: $contentType\r\n\r\n"
                val parser = HTTPRequestParser(raw)
                val parsed = parser.parseRequest()
                assertNotNull(parsed, "$description: parsing request failed")
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
        val fixturesDir = System.getProperty("test.fixtures.dir")
            ?: error("test.fixtures.dir system property not set")
        val file = File(fixturesDir, "$name.json")
        return Gson().fromJson(file.reader(), JsonObject::class.java)
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
        val request = parser.parseRequest()
        assertNotNull(request, "Failed to parse multipart request")
        return request!!
    }
}
