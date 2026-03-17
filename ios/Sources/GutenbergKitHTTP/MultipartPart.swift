import Foundation

/// A single part from a `multipart/form-data` body, per RFC 7578.
///
/// Each part represents one form field or file upload, with its own
/// Content-Disposition parameters and optional Content-Type.
///
/// Part bodies are represented as lightweight references (byte ranges)
/// back to the original request body. No part data is copied during parsing;
/// bytes are only read when ``body`` is accessed via ``RequestBody/makeInputStream()``.
///
/// ```swift
/// let request = try parser.parseRequest()
/// for part in try request?.multipartParts() ?? [] {
///     print(part.name, part.filename, part.contentType)
/// }
/// ```
public struct MultipartPart: Sendable, Equatable {
    /// The field name from the `Content-Disposition: form-data; name="..."` parameter.
    public let name: String
    /// The filename, if present, from the `Content-Disposition: form-data; filename="..."` parameter.
    public let filename: String?
    /// The `Content-Type` of this part, or `"text/plain"` if not specified (RFC 7578 §4.4).
    public let contentType: String
    /// The part's body content, backed by a reference to the original request body.
    public let body: RequestBody
}

/// Errors thrown when parsing a multipart/form-data body fails.
public enum MultipartParseError: Error, Sendable, Equatable, LocalizedError {
    /// The Content-Type is not `multipart/form-data` or is missing the `boundary` parameter.
    case notMultipartFormData
    /// The body is missing or the request is incomplete.
    case missingBody
    /// A part is missing the required `Content-Disposition: form-data` header.
    case missingContentDisposition
    /// A part's `Content-Disposition` header is missing the required `name` parameter.
    case missingNameParameter
    /// The multipart body structure is malformed (e.g., missing closing boundary).
    case malformedBody
    /// The multipart body contains more than 100 parts.
    case tooManyParts

    public var errorDescription: String? {
        switch self {
        case .notMultipartFormData:
            return "The Content-Type is not multipart/form-data or is missing the boundary parameter."
        case .missingBody:
            return "The request body is missing or the request is incomplete."
        case .missingContentDisposition:
            return "A multipart part is missing the required Content-Disposition header."
        case .missingNameParameter:
            return "A multipart part's Content-Disposition header is missing the required name parameter."
        case .malformedBody:
            return "The multipart body is malformed."
        case .tooManyParts:
            return "The multipart body contains more than 100 parts."
        }
    }
}

// MARK: - Parsing

extension MultipartPart {

    private static let scanChunkSize = 65_536

    /// Parses an in-memory `multipart/form-data` body into its constituent parts.
    ///
    /// Scans the body data to locate part boundaries and extract headers, but does
    /// not copy part body bytes. Each part's ``body`` is a lightweight reference
    /// (offset + length) back to the source `RequestBody`.
    ///
    /// - Parameters:
    ///   - source: The original request body to reference for part content.
    ///   - bodyData: The raw body bytes (read once for scanning, then released by the caller).
    ///   - bodyFileOffset: The byte offset of `bodyData` within `source`'s backing file
    ///     (0 for data-backed bodies).
    ///   - boundary: The boundary string from the Content-Type header.
    /// - Returns: An array of parsed parts with lazy body references.
    /// - Throws: ``MultipartParseError`` if the body is malformed.
    static func parse(
        source: RequestBody,
        bodyData: Data,
        bodyFileOffset: UInt64,
        boundary: String
    ) throws -> [MultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        let closeDelimiter = Data("--\(boundary)--".utf8)
        let crlf = Data("\r\n".utf8)
        let crlfcrlf = Data("\r\n\r\n".utf8)

        guard let firstRange = bodyData.range(of: delimiter) else {
            throw MultipartParseError.malformedBody
        }

        var parts: [MultipartPart] = []
        var searchStart = firstRange.upperBound

        while searchStart < bodyData.endIndex {
            // RFC 2046 §5.1.1: skip optional transport padding (LWSP) after the boundary.
            // delimiter = CRLF "--" boundary *(SP / HTAB) CRLF
            while searchStart < bodyData.endIndex &&
                  (bodyData[searchStart] == UInt8(ascii: " ") || bodyData[searchStart] == UInt8(ascii: "\t")) {
                searchStart = bodyData.index(after: searchStart)
            }

            // Skip the CRLF after the delimiter line
            if bodyData[searchStart...].starts(with: crlf) {
                searchStart = bodyData.index(searchStart, offsetBy: crlf.count)
            }

            let remaining = bodyData[searchStart...]
            if remaining.isEmpty {
                break
            }

            // Find the header/body separator within this part
            guard let headerEnd = bodyData[searchStart...].range(of: crlfcrlf) else {
                throw MultipartParseError.malformedBody
            }

            let headerData = bodyData[searchStart..<headerEnd.lowerBound]
            let partBodyStart = headerEnd.upperBound

            // Find the next delimiter to determine where this part's body ends
            guard let nextDelimiter = bodyData[partBodyStart...].range(of: delimiter) else {
                throw MultipartParseError.malformedBody
            }

            // The body ends at the CRLF before the next delimiter
            var partBodyEnd = nextDelimiter.lowerBound
            let minBodyEnd = bodyData.index(partBodyStart, offsetBy: crlf.count, limitedBy: bodyData.endIndex) ?? bodyData.endIndex
            if partBodyEnd >= minBodyEnd {
                let beforeDelimiter = bodyData[bodyData.index(partBodyEnd, offsetBy: -crlf.count)..<partBodyEnd]
                if beforeDelimiter == crlf {
                    partBodyEnd = bodyData.index(partBodyEnd, offsetBy: -crlf.count)
                }
            }

            // Build a lightweight body reference instead of copying bytes
            let partBodyLength = bodyData.distance(from: partBodyStart, to: partBodyEnd)
            let partOffset = bodyData.distance(from: bodyData.startIndex, to: partBodyStart)
            let partBody = makePartBody(
                source: source,
                bodyData: bodyData,
                partOffset: partOffset,
                partLength: partBodyLength,
                bodyFileOffset: bodyFileOffset
            )

            let part = try parsePartHeaders(headerData: headerData, body: partBody)
            parts.append(part)

            if parts.count > 100 {
                throw MultipartParseError.tooManyParts
            }

            // Check if the next delimiter is the closing one
            if bodyData[nextDelimiter.lowerBound...].starts(with: closeDelimiter) {
                break
            }

            searchStart = nextDelimiter.upperBound
        }

        return parts
    }

    /// Parses a file-backed `multipart/form-data` body using chunked scanning.
    ///
    /// Reads the file in fixed-size chunks to find boundary offsets, keeping memory
    /// usage at O(chunk_size) regardless of body size. Part bodies are file-slice
    /// references, not copies.
    ///
    /// - Parameters:
    ///   - source: The file-backed request body.
    ///   - boundary: The boundary string from the Content-Type header.
    /// - Returns: An array of parsed parts with lazy body references.
    /// - Throws: ``MultipartParseError`` if the body is malformed.
    static func parseChunked(
        source: RequestBody,
        boundary: String
    ) throws -> [MultipartPart] {
        guard let fileURL = source.fileURL else {
            throw MultipartParseError.malformedBody
        }

        let delimiter = Data("--\(boundary)".utf8)
        let crlfcrlf = Data("\r\n\r\n".utf8)

        let bodyStart = source.fileOffset
        let bodyLength = UInt64(source.count)
        let bodyEnd = bodyStart + bodyLength

        return try FileHandle.withReadHandle(forUrl: fileURL) { fileHandle in
            // Phase 1: Scan for all boundary delimiter offsets using chunked reads.
            // An overlap region (delimiter.count - 1 bytes) is carried between chunks
            // so boundaries split across chunk boundaries are still found.
            let overlapSize = delimiter.count - 1
            var delimiterOffsets: [UInt64] = []
            var position = bodyStart
            var carryOver = Data()

            while position < bodyEnd {
                let readSize = min(UInt64(scanChunkSize), bodyEnd - position)
                try fileHandle.seek(toOffset: position)
                guard let chunk = try fileHandle.read(upToCount: Int(readSize)),
                      !chunk.isEmpty else {
                    break
                }

                let searchBuffer = carryOver.isEmpty ? chunk : carryOver + chunk

                var searchOffset = searchBuffer.startIndex
                while let range = searchBuffer.range(of: delimiter, in: searchOffset..<searchBuffer.endIndex) {
                    let bufferRelativeOffset = searchBuffer.distance(from: searchBuffer.startIndex, to: range.lowerBound)
                    let absoluteOffset = position - UInt64(carryOver.count) + UInt64(bufferRelativeOffset)
                    if absoluteOffset >= bodyStart && absoluteOffset + UInt64(delimiter.count) <= bodyEnd {
                        delimiterOffsets.append(absoluteOffset)
                    }
                    searchOffset = searchBuffer.index(after: range.lowerBound)
                }

                if chunk.count > overlapSize {
                    carryOver = chunk.suffix(overlapSize)
                } else {
                    carryOver = chunk
                }
                position += UInt64(chunk.count)
            }

            guard !delimiterOffsets.isEmpty else {
                throw MultipartParseError.malformedBody
            }

            // Phase 2: Extract parts from consecutive delimiter pairs.
            var parts: [MultipartPart] = []
            let maxPartHeaderSize: UInt64 = 8192

            for i in 0..<delimiterOffsets.count {
                let delimStart = delimiterOffsets[i]
                let afterDelim = delimStart + UInt64(delimiter.count)

                // Check if this is the close delimiter ("--boundary--").
                if afterDelim + 2 <= bodyEnd {
                    try fileHandle.seek(toOffset: afterDelim)
                    if let peek = try fileHandle.read(upToCount: 2),
                       peek.count == 2,
                       peek[peek.startIndex] == UInt8(ascii: "-"),
                       peek[peek.startIndex + 1] == UInt8(ascii: "-") {
                        break
                    }
                } else {
                    break
                }

                guard i + 1 < delimiterOffsets.count else {
                    throw MultipartParseError.malformedBody
                }
                let nextDelimStart = delimiterOffsets[i + 1]

                // Read the region between this delimiter and the next to extract headers.
                let regionLength = min(maxPartHeaderSize, nextDelimStart - afterDelim)
                try fileHandle.seek(toOffset: afterDelim)
                guard let headerRegion = try fileHandle.read(upToCount: Int(regionLength)),
                      !headerRegion.isEmpty else {
                    throw MultipartParseError.malformedBody
                }

                // Skip optional transport padding (LWSP) after boundary.
                var scanPos = 0
                while scanPos < headerRegion.count &&
                      (headerRegion[scanPos] == UInt8(ascii: " ") || headerRegion[scanPos] == UInt8(ascii: "\t")) {
                    scanPos += 1
                }

                // Skip CRLF after the delimiter line.
                if scanPos + 1 < headerRegion.count &&
                   headerRegion[scanPos] == 0x0D && headerRegion[scanPos + 1] == 0x0A {
                    scanPos += 2
                }

                // Find the \r\n\r\n header/body separator.
                let headerSlice = headerRegion[scanPos...]
                guard let headerEnd = headerSlice.range(of: crlfcrlf) else {
                    throw MultipartParseError.malformedBody
                }

                let headerData = Data(headerSlice[headerSlice.startIndex..<headerEnd.lowerBound])
                let partBodyStart = afterDelim + UInt64(headerEnd.upperBound)

                // Body ends at the CRLF before the next delimiter.
                var partBodyEnd = nextDelimStart
                if partBodyEnd >= partBodyStart + 2 {
                    try fileHandle.seek(toOffset: nextDelimStart - 2)
                    if let peek = try fileHandle.read(upToCount: 2),
                       peek.count == 2,
                       peek[peek.startIndex] == 0x0D && peek[peek.startIndex + 1] == 0x0A {
                        partBodyEnd = nextDelimStart - 2
                    }
                }

                let partBodyLength = Int(partBodyEnd - partBodyStart)
                let partBody = RequestBody(
                    fileURL: fileURL,
                    offset: partBodyStart,
                    length: max(0, partBodyLength),
                    owner: source.fileOwner
                )

                let part = try parsePartHeaders(headerData: headerData, body: partBody)
                parts.append(part)

                if parts.count > 100 {
                    throw MultipartParseError.tooManyParts
                }
            }

            guard !parts.isEmpty else {
                throw MultipartParseError.malformedBody
            }

            return parts
        }
    }

    /// Creates a `RequestBody` for a part without copying bytes.
    ///
    /// For file-backed sources, returns a file-slice reference. For data-backed
    /// sources, returns a Data slice (which shares storage via copy-on-write).
    private static func makePartBody(
        source: RequestBody,
        bodyData: Data,
        partOffset: Int,
        partLength: Int,
        bodyFileOffset: UInt64
    ) -> RequestBody {
        switch source.storage {
        case .file(let url), .fileSlice(let url, _, _):
            return RequestBody(
                fileURL: url,
                offset: bodyFileOffset + UInt64(partOffset),
                length: partLength,
                owner: source.fileOwner
            )
        case .data:
            let start = bodyData.startIndex + partOffset
            let end = start + partLength
            return RequestBody(data: bodyData[start..<end])
        }
    }

    /// Parses a single part's headers into a `MultipartPart`.
    private static func parsePartHeaders(headerData: Data, body: RequestBody) throws -> MultipartPart {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw MultipartParseError.missingContentDisposition
        }

        let lines = headerString.components(separatedBy: "\r\n")

        var contentDisposition: String?
        var contentType: String?

        for line in lines where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

            switch key.lowercased() {
            case "content-disposition":
                contentDisposition = value
            case "content-type":
                contentType = value
            default:
                break
            }
        }

        guard let disposition = contentDisposition,
              disposition.lowercased().hasPrefix("form-data") else {
            throw MultipartParseError.missingContentDisposition
        }

        guard let name = HeaderValue.extractParameter("name", from: disposition) else {
            throw MultipartParseError.missingNameParameter
        }

        let filename = HeaderValue.extractParameter("filename", from: disposition)

        return MultipartPart(
            name: name,
            filename: filename,
            contentType: contentType ?? "text/plain",
            body: body
        )
    }

}
