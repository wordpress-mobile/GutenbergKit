import Foundation

/// A service that manages the editor backend.
///
/// - note: The service can be instantiated and warmed-up before the editor
/// is presented.
@MainActor
public final class EditorService {
    private let client: EditorNetworkingClient

    @Published private(set) var blockTypes: [EditorBlockType] = []
    @Published private(set) var rawBlockTypesResponseData: Data?

    private var refreshBlockTypesTask: Task<[EditorBlockType], Error>?

    public init(client: EditorNetworkingClient) {
        self.client = client
    }

    /// Prefetches the settings used by the editor.
    public func warmup() async {
        _ = try? await refreshBlockTypes()
    }

    func refreshBlockTypes() async throws -> [EditorBlockType] {
        if let task = refreshBlockTypesTask {
            return try await task.value
        }
        let task = Task {
            let request = EditorNetworkRequest(method: "GET", url: URL(string: "./wp-json/wp/v2/block-types")!)
            let response = try await self.client.send(request)
            try validate(response.urlResponse)
            self.blockTypes = try await decode(response.data ?? Data())
            self.rawBlockTypesResponseData = response.data ?? Data()
            return blockTypes
        }
        self.refreshBlockTypesTask = task
        return try await task.value
    }
    
    func getRemoteEditor() async throws -> EditorAssets {
        let request = EditorNetworkRequest(method: "GET", url: URL(string: "./wp-json/__experimental/wp-block-editor/v1/editor-assets")!)
        let response = try await self.client.send(request)
        try validate(response.urlResponse)
        return try await decode(response.data ?? Data())
    }
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
