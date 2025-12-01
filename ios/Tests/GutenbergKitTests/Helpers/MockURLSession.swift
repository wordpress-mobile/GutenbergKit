import Foundation
@testable import GutenbergKit

/// Mock implementation of URLSessionProtocol for testing
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private var mockedResponses: [String: (Data, HTTPURLResponse)] = [:]
    private var requestCounts: [String: Int] = [:]
    private let lock = NSLock()

    func mockResponse(for urlString: String, data: Data, statusCode: Int) {
        let url = URL(string: urlString)!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        lock.withLock {
            mockedResponses[urlString] = (data, response)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              let urlString = getCanonicalURLString(for: url) else {
            throw URLError(.badURL)
        }

        lock.withLock {
            requestCounts[urlString, default: 0] += 1
        }

        let result = lock.withLock { mockedResponses[urlString] }
        guard let (data, response) = result else {
            throw URLError(.badURL)
        }
        return (data, response)
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        guard let url = request.url,
              let urlString = getCanonicalURLString(for: url) else {
            throw URLError(.badURL)
        }

        lock.withLock {
            requestCounts[urlString, default: 0] += 1
        }

        let result = lock.withLock { mockedResponses[urlString] }
        guard let (data, response) = result else {
            throw URLError(.badURL)
        }

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)

        return (tempURL, response)
    }

    func requestCount(for urlSubstring: String) -> Int {
        lock.withLock {
            requestCounts
                .filter { $0.key.contains(urlSubstring) }
                .values
                .reduce(0, +)
        }
    }

    private func getCanonicalURLString(for url: URL) -> String? {
        // For URLs with query parameters, construct the canonical form
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Sort query items for consistent lookup
            if var queryItems = components.queryItems {
                queryItems.sort { $0.name < $1.name }
                var canonicalComponents = components
                canonicalComponents.queryItems = queryItems
                return canonicalComponents.url?.absoluteString
            }
        }
        return url.absoluteString
    }
}
