import Foundation

/// Parses raw HTTP/1.1 request data into a structured `ParsedHTTPRequest`.
///
/// This parser handles incremental data — call `append(_:)` as bytes arrive,
/// then check `state` to determine whether buffering is complete.
///
/// The parser buffers incoming data to a temporary file on disk rather than
/// accumulating it in memory, making it suitable for large request bodies.
/// If the temp file cannot be created (e.g. disk full), the parser falls back
/// to in-memory buffering automatically.
///
/// State tracking is lightweight — `append(_:)` scans for the header separator
/// (`\r\n\r\n`) and extracts `Content-Length`. Full parsing and RFC validation
/// are deferred until ``parseRequest()`` is called.
///
/// ```swift
/// let parser = HTTPRequestParser("GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n")
/// let request = try parser.parseRequest()
/// print(request?.method, request?.target)
/// ```
public final class HTTPRequestParser: @unchecked Sendable {

    /// The current buffering state of the parser.
    public enum State: Sendable {
        /// More data is needed before headers are complete.
        case needsMoreData
        /// Headers have been fully received but the body is still incomplete.
        case headersComplete
        /// The request body exceeds the maximum allowed size and is being
        /// drained (read and discarded) so the server can send a clean 413
        /// response. No body bytes are buffered in this state.
        case draining
        /// All data has been received (headers and body).
        case complete
    }

    /// The default maximum request body size (4 GB).
    public static let defaultMaxBodySize: Int64 = Int64(4) * 1024 * 1024 * 1024

    /// The default threshold below which bodies are kept in memory (512 KB).
    public static let defaultInMemoryBodyThreshold: Int = 512 * 1024

    /// The maximum number of bytes to buffer before the header terminator is found (64 KB).
    /// This matches the `readFromBuffer` scan cap and prevents unbounded disk writes
    /// from clients that never send `\r\n\r\n`.
    static let maxHeaderSize: Int = 65536

    private let lock = NSLock()
    private var buffer: Buffer
    private let maxBodySize: Int64
    private let inMemoryBodyThreshold: Int
    private var bytesWritten: Int64 = 0
    private var _state: State = .needsMoreData

    // Lightweight scan results (populated by append)
    private var headerEndOffset: Int?
    private var expectedContentLength: Int64 = 0

    // Lazy parsing cache (populated by parseRequest)
    private var _parsedHeaders: HTTPRequestSerializer.ParsedHeaders?
    private var _parseError: HTTPRequestParseError?
    private var _cachedBody: RequestBody?
    private var _bodyExtracted: Bool = false

    /// Creates a new parser.
    ///
    /// - Parameters:
    ///   - maxBodySize: The maximum allowed request body size in bytes.
    ///     Requests with a `Content-Length` exceeding this will be rejected.
    ///     Defaults to ``defaultMaxBodySize`` (4 GB).
    ///   - inMemoryBodyThreshold: Bodies smaller than this are kept in memory;
    ///     larger bodies are streamed to a temporary file. Defaults to
    ///     ``defaultInMemoryBodyThreshold`` (512 KB).
    ///   - tempDirectory: Directory for temporary files. Defaults to the system
    ///     temp directory. When used via ``HTTPServer``, this is a server-specific
    ///     subdirectory scoped by the server's `name`.
    public init(
        maxBodySize: Int64 = HTTPRequestParser.defaultMaxBodySize,
        inMemoryBodyThreshold: Int = HTTPRequestParser.defaultInMemoryBodyThreshold,
        tempDirectory: URL? = nil
    ) {
        // Cap in-memory buffers at headers + inMemoryBodyThreshold to prevent
        // unbounded memory growth when temp file creation fails.
        self.buffer = Buffer(maxSize: Self.maxHeaderSize + inMemoryBodyThreshold, directory: tempDirectory)
        self.maxBodySize = maxBodySize
        self.inMemoryBodyThreshold = inMemoryBodyThreshold
    }

    /// Creates a parser and immediately parses the given raw HTTP string.
    ///
    /// This is a convenience for one-shot parsing when all data is available upfront.
    public convenience init(_ string: String) {
        self.init(Data(string.utf8))
    }

    /// Creates a parser and immediately parses the given raw HTTP data.
    ///
    /// This is a convenience for one-shot parsing when all data is available upfront.
    public convenience init(_ data: Data) {
        self.init()
        append(data)
    }

    /// The current buffering state.
    public var state: State {
        lock.withLock { _state }
    }

    /// The parse error detected during buffering, if any.
    ///
    /// Non-fatal errors like ``HTTPRequestParseError/payloadTooLarge`` are
    /// exposed here instead of being thrown by ``parseRequest()``, allowing
    /// the caller to still access the parsed headers.
    public var parseError: HTTPRequestParseError? {
        lock.withLock { _parseError }
    }

    /// The expected body length from `Content-Length`, available once headers have been received.
    public var expectedBodyLength: Int64? {
        lock.withLock {
            guard _state.hasHeaders else { return nil }
            return expectedContentLength
        }
    }

    /// Parses the buffered data into a structured HTTP request.
    ///
    /// This triggers full parsing via ``HTTPRequestSerializer`` on the first call.
    /// The parsed headers are cached for subsequent calls. When the state is
    /// `.complete` and a body is present, the body is extracted to a temporary
    /// file on the first access.
    ///
    /// - Returns: The parsed request, or `nil` if the state is `.needsMoreData`.
    /// - Throws: ``HTTPRequestParseError`` if the request is malformed.
    public func parseRequest() throws -> ParsedHTTPRequest? {
        try lock.withLock {
            guard _state.hasHeaders else { return nil }

            // Payload-too-large means "valid headers, rejected body" — let
            // the caller access the parsed headers so the handler can build
            // a response (e.g., with CORS headers). Other parse errors
            // indicate genuinely malformed requests and are still thrown.
            if let error = _parseError, error != .payloadTooLarge {
                throw error
            }

            if _parsedHeaders == nil {
                let headerData = try buffer.read(from: 0, maxLength: Int(min(bytesWritten, Int64(Self.maxHeaderSize))))
                switch HTTPRequestSerializer.parseHeaders(from: headerData) {
                case .parsed(let headers):
                    _parsedHeaders = headers
                case .invalid(let error):
                    _parseError = error
                    throw error
                case .needsMoreData:
                    return nil
                }
            }

            guard let headers = _parsedHeaders else { return nil }

            // Return partial (headers only) when the body was rejected or
            // hasn't fully arrived yet. The payloadTooLarge case goes through
            // drain mode which discards body bytes without buffering them, so
            // there is no body to extract even though the state is .complete.
            guard _state.isComplete, _parseError == nil else {
                return .partial(
                    method: headers.method,
                    target: headers.target,
                    httpVersion: headers.httpVersion,
                    headers: headers.headers
                )
            }

            if headers.contentLength > 0 && !_bodyExtracted {
                _cachedBody = try extractBody(
                    offset: headers.bodyOffset,
                    length: headers.contentLength
                )
                _bodyExtracted = true
            }

            return .complete(
                method: headers.method,
                target: headers.target,
                httpVersion: headers.httpVersion,
                headers: headers.headers,
                body: _cachedBody
            )
        }
    }

    /// Appends received data to the buffer and updates the buffering state.
    ///
    /// This method performs lightweight scanning — it looks for the `\r\n\r\n`
    /// header separator and extracts the `Content-Length` value. Full parsing
    /// and RFC validation are deferred until ``parseRequest()`` is called.
    public func append(_ data: Data) {
        lock.withLock {
            guard !_state.isComplete else { return }

            // In drain mode, discard bytes without buffering and check
            // whether the full Content-Length has been consumed.
            if case .draining = _state {
                bytesWritten += Int64(data.count)
                if let offset = headerEndOffset,
                   bytesWritten - Int64(offset) >= expectedContentLength {
                    _state = .complete
                }
                return
            }

            let accepted: Bool
            do {
                accepted = try buffer.append(data)
            } catch {
                _parseError = .bufferIOError
                _state = .complete
                return
            }
            guard accepted else {
                _parseError = .payloadTooLarge
                _state = .complete
                return
            }
            bytesWritten += Int64(data.count)

            if headerEndOffset == nil {
                let buffered: Data
                do {
                    buffered = try buffer.read(from: 0, maxLength: Int(min(bytesWritten, Int64(Self.maxHeaderSize))))
                } catch {
                    _parseError = .bufferIOError
                    _state = .complete
                    return
                }
                let separator = Data("\r\n\r\n".utf8)

                // RFC 7230 §3.5: Skip leading CRLFs for robustness.
                var scanStart = 0
                while scanStart + 1 < buffered.count,
                      buffered[scanStart] == 0x0D,
                      buffered[scanStart + 1] == 0x0A {
                    scanStart += 2
                }
                let effectiveData = buffered[scanStart...]

                guard let separatorRange = effectiveData.range(of: separator) else {
                    if bytesWritten > Int64(Self.maxHeaderSize) {
                        _parseError = .headersTooLarge
                        _state = .complete
                    } else {
                        _state = .needsMoreData
                    }
                    return
                }

                headerEndOffset = buffered.distance(from: buffered.startIndex, to: separatorRange.upperBound)
                let headerBytes = effectiveData[effectiveData.startIndex..<separatorRange.lowerBound]
                do throws(HTTPRequestParseError) {
                    expectedContentLength = try Self.scanContentLength(in: Data(headerBytes))
                } catch {
                    _parseError = error
                    _state = .complete
                    return
                }

                if expectedContentLength > maxBodySize {
                    _parseError = .payloadTooLarge
                    _state = .draining
                    return
                }
            }

            guard let offset = headerEndOffset else { return }
            let bodyBytesAvailable = bytesWritten - Int64(offset)

            if bodyBytesAvailable >= expectedContentLength {
                _state = .complete
            } else {
                _state = .headersComplete
            }
        }
    }

    // MARK: - Content-Length Scanning

    /// Extracts and validates the `Content-Length` value from header bytes without full parsing.
    ///
    /// This reuses ``HTTPRequestSerializer/validateContentLength(_:existing:)`` so that
    /// the scan and the later full parse apply identical validation rules. Conflicting
    /// or malformed values are rejected immediately — before any body bytes are buffered.
    ///
    /// Returns 0 if no `Content-Length` header is present.
    private static func scanContentLength(in headerBytes: Data) throws(HTTPRequestParseError) -> Int64 {
        guard let string = String(data: headerBytes, encoding: .utf8) else { return 0 }
        let lines = string.components(separatedBy: "\r\n")

        var contentLength: Int64?
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let rawKey = line[line.startIndex..<colonIndex]
            if rawKey.lowercased() == "content-length" {
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                contentLength = try HTTPRequestSerializer.validateContentLength(value, existing: contentLength)
            }
        }

        return contentLength ?? 0
    }

    // MARK: - Body Extraction

    /// Extracts the request body from the buffer.
    ///
    /// Bodies smaller than ``inMemoryBodyThreshold`` are read into memory.
    /// Larger bodies reference the buffer's backing file directly as a slice,
    /// avoiding a redundant copy.
    private func extractBody(offset: Int, length: Int64) throws -> RequestBody? {
        if length <= inMemoryBodyThreshold {
            return RequestBody(data: try buffer.read(from: offset, maxLength: Int(length)))
        }

        // Reference the body range directly in the buffer's file.
        if let (fileURL, owner) = buffer.transferFileOwnership() {
            return RequestBody(
                fileURL: fileURL,
                offset: UInt64(offset),
                length: Int(length),
                owner: owner
            )
        }

        // Memory-backed buffer — read into a Data.
        return RequestBody(data: try buffer.read(from: offset, maxLength: Int(length)))
    }
}

// MARK: - Buffer

/// Abstraction over the parser's backing store.
///
/// Tries to use a temp file on disk (suitable for large bodies). If the file
/// cannot be created, falls back to an in-memory `Data` buffer automatically.
/// When memory-backed, the buffer is capped at `maxSize` to prevent unbounded growth.
private final class Buffer {
    private let fileURL: URL?
    private let fileHandle: FileHandle?
    private var memoryBuffer: Data?
    private var fileOwnershipTransferred = false
    private let maxSize: Int

    /// Whether the buffer is backed by memory rather than a file.
    var isMemoryBacked: Bool { fileHandle == nil }

    init(maxSize: Int, directory: URL? = nil) {
        self.maxSize = maxSize

        let dir = directory ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("GutenbergKitHTTP-\(UUID().uuidString)")

        if FileManager.default.createFile(atPath: url.path, contents: nil),
           let handle = FileHandle(forUpdatingAtPath: url.path) {
            self.fileURL = url
            self.fileHandle = handle
            self.memoryBuffer = nil
        } else {
            // Temp file unavailable — buffer in memory instead.
            self.fileURL = nil
            self.fileHandle = nil
            self.memoryBuffer = Data()
        }
    }

    deinit {
        if let fileHandle {
            // Writable handle, but the file is a temp buffer deleted immediately below —
            // an EIO on close cannot cause data loss here.
            try? fileHandle.close()
        }
        if let fileURL, !fileOwnershipTransferred {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Transfers ownership of the backing file to a `TempFileOwner`.
    ///
    /// After this call, the buffer will no longer delete the file on deinit.
    /// Returns `nil` if the buffer is memory-backed or ownership was already transferred.
    func transferFileOwnership() -> (URL, TempFileOwner)? {
        guard let fileURL, !fileOwnershipTransferred else { return nil }
        fileOwnershipTransferred = true
        return (fileURL, TempFileOwner(url: fileURL))
    }

    /// Appends data to the buffer.
    ///
    /// - Returns: `true` if the data was accepted, `false` if the in-memory
    ///   buffer would exceed its size limit.
    /// - Throws: If the file-backed write fails (e.g. disk full).
    @discardableResult
    func append(_ data: Data) throws -> Bool {
        if let fileHandle {
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
            return true
        } else {
            if memoryBuffer!.count + data.count > maxSize {
                return false
            }
            memoryBuffer!.append(data)
            return true
        }
    }

    func read(from offset: Int, maxLength: Int) throws -> Data {
        precondition(offset >= 0, "offset must be non-negative, was \(offset)")
        precondition(maxLength >= 0, "maxLength must be non-negative, was \(maxLength)")
        if maxLength == 0 { return Data() }
        if let fileHandle {
            try fileHandle.seek(toOffset: UInt64(offset))
            return try fileHandle.read(upToCount: maxLength) ?? Data()
        } else {
            let start = memoryBuffer!.startIndex + offset
            let end = min(start + maxLength, memoryBuffer!.endIndex)
            return Data(memoryBuffer![start..<end])
        }
    }
}

// MARK: - State Convenience Properties

extension HTTPRequestParser.State {

    /// Whether all data has been received (headers and body).
    public var isComplete: Bool {
        switch self {
        case .complete: return true
        case .needsMoreData, .headersComplete, .draining: return false
        }
    }

    /// Whether headers have been fully received (true for `.headersComplete`, `.draining`, and `.complete`).
    public var hasHeaders: Bool {
        switch self {
        case .headersComplete, .draining, .complete: return true
        case .needsMoreData: return false
        }
    }
}
