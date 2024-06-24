import Foundation

/// A service that manages the editor backend.
///
/// - note: The service can be instantiated and warmed-up before the editor
/// is presented.
public actor EditorService {
    private let client: EditorNetworkingClient

    // TODO: add type to represent block types
    var blockTypes: [GutenbergBlockType] = []

    private var refreshBlockTypesTask: Task<[GutenbergBlockType], Error>?

    public init(client: EditorNetworkingClient) {
        self.client = client
    }

    /// Prefetches the settings used by the editor.
    public func warmup() async {
        _ = try? await refreshBlockTypes()
    }

    func refreshBlockTypes() async throws -> [GutenbergBlockType] {
        if let task = refreshBlockTypesTask {
            return try await task.value
        }
        let task = Task {
            let blockTypes = try await self.send(EditorNetworkRequest(method: "GET", url: URL(string: "./wp-json/wp/v2/block-types")!), decoding: [GutenbergBlockType].self)
            self.blockTypes = blockTypes
            return blockTypes
        }
        self.refreshBlockTypesTask = task
        return try await task.value
    }

    private func send<T>(_ request: EditorNetworkRequest, decoding: T.Type) async throws -> T where T: Decodable {
        let response = try await client.send(request)
        try validate(response.urlResponse)
        return try await decode(response.data ?? Data())
    }
}

// TODO: move (private OK)?
struct GutenbergBlockType: Decodable {
    let name: String
    let title: String?
    let description: String?
    let category: String?
    let keywords: [String]?
}

// MARK: - Helpers

private func decode<T: Decodable>(_ data: Data, using decoder: JSONDecoder = JSONDecoder()) async throws -> T {
    try await Task.detached {
        try decoder.decode(T.self, from: data)
    }.value
}

private func validate(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse else {
        throw EditorRequestError.invalidResponseType
    }
    guard (200..<300).contains(response.statusCode) else {
        throw EditorRequestError.unacceptableStatusCode(response.statusCode)
    }
}

enum EditorRequestError: Error {
    case invalidResponseType
    case unacceptableStatusCode(Int)
}
