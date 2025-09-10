import Foundation
import WebKit

class CachedAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let cachedURLSchemePrefix = "gbk-cache-"
    nonisolated static let supportedURLSchemes = ["gbk-cache-http", "gbk-cache-https"]

    nonisolated static func originalHTTPURL(from url: URL) -> URL? {
        guard let scheme = url.scheme, supportedURLSchemes.contains(scheme) else { return nil }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        components.scheme = String(scheme.suffix(from: scheme.index(scheme.startIndex, offsetBy: cachedURLSchemePrefix.count)))
        return components.url
    }

    nonisolated static func cachedURL(forWebLink link: String) -> String? {
        if link.starts(with: "http://") || link.starts(with: "https://") {
            return cachedURLSchemePrefix + link
        }
        return nil
    }

    private let worker: Worker

    init(library: EditorAssetsLibrary) {
        self.worker = .init(library: library)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        Task {
            await worker.start(urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        Task {
            await worker.stop(urlSchemeTask)
        }
    }
}

private actor Worker {
     struct TaskInfo {
         var webViewTask: WKURLSchemeTask
         var fetchAssetTask: Task<Void, Never>

         func cancel() {
             fetchAssetTask.cancel()
         }
    }

    let library: EditorAssetsLibrary
    var tasks: [ObjectIdentifier: TaskInfo] = [:]

    init(library: EditorAssetsLibrary) {
        self.library = library
    }

    deinit {
        for (_, task) in tasks {
            task.cancel()
        }
    }

    func start(_ task: WKURLSchemeTask) {
        guard let url = task.request.url, let httpURL = CachedAssetSchemeHandler.originalHTTPURL(from: url) else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let taskKey = ObjectIdentifier(task)

        let fetchAssetTask = Task { [library, weak self] in
            do {
                let (response, content) = try await library.cacheAsset(from: httpURL, webViewURL: url)

                await self?.tasks[taskKey]?.webViewTask.didReceive(response)
                await self?.tasks[taskKey]?.webViewTask.didReceive(content)

                await self?.finish(with: nil, taskKey: taskKey)
            } catch {
                await self?.finish(with: error, taskKey: taskKey)
            }
        }
        tasks[taskKey] = .init(webViewTask: task, fetchAssetTask: fetchAssetTask)
    }

    func stop(_ task: WKURLSchemeTask) {
        let taskKey = ObjectIdentifier(task)
        tasks[taskKey]?.cancel()
        tasks[taskKey] = nil
    }

    private func finish(with error: Error?, taskKey: ObjectIdentifier) {
        guard let task = tasks[taskKey] else { return }

        if let error {
            task.webViewTask.didFailWithError(error)
        } else {
            task.webViewTask.didFinish()
        }
        tasks[taskKey] = nil
    }
}

@available(iOS 26.0, *)
extension CachedAssetSchemeHandler: URLSchemeHandler {
    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, Error> {
        AsyncThrowingStream { [library = worker.library] continuation in
            let task = Task {
                guard let url = request.url,
                      let httpURL = CachedAssetSchemeHandler.originalHTTPURL(from: url) else {
                    continuation.yield(with: .failure(URLError(.badURL)))
                    continuation.finish()
                    return
                }

                do {
                    let (response, content) = try await library.cacheAsset(from: httpURL, webViewURL: url)
                    try Task.checkCancellation()

                    continuation.yield(with: .success(.response(response)))
                    continuation.yield(with: .success(.data(content)))
                } catch {
                    try Task.checkCancellation()
                    continuation.yield(with: .failure(error))
                }
                continuation.finish()
            }

            continuation.onTermination = {
                if case .cancelled = $0 {
                    task.cancel()
                }
            }
        }
    }
}
