import Foundation

/// Fetches an editor's dependencies without holding the editor.
///
/// The editor owns its loader, never the reverse: the loader reaches back only through
/// ``delegate``, which is weak and whose requirements are all synchronous. So a released
/// editor is freed at once rather than when the fetch ends — it never awaits the fetch,
/// and nothing the loader calls on it can suspend. Keep it that way by reading
/// `delegate` where it is used: a copy held across the `await` would retain the editor
/// for the whole fetch.
///
/// The fetch starts on init and is never cancelled, so it keeps the loader alive until it
/// finishes. That is harmless — a loader owns no view, web view, or listener — and a
/// fetch that outlives its editor still warms the cache for the next one.
@MainActor
final class EditorDependencyLoader {
    weak let delegate: (any EditorDependencyLoaderDelegate)?

    init(service: EditorService, delegate: any EditorDependencyLoaderDelegate) {
        self.delegate = delegate
        fetch(from: service)
    }

    /// Kept out of `init`, where the strong `delegate` parameter would shadow the weak
    /// property — so here the task can reach the delegate only through ``delegate``.
    private func fetch(from service: EditorService) {
        Task(priority: .userInitiated) {
            do {
                let dependencies = try await service.prepare { @MainActor progress in
                    self.delegate?.dependencyLoader(self, didUpdate: progress)
                }
                delegate?.dependencyLoader(self, didLoad: dependencies)
            } catch {
                delegate?.dependencyLoader(self, didFailWith: error)
            }
        }
    }
}

/// Receives an ``EditorDependencyLoader``'s results on the main actor.
///
/// Every requirement is synchronous, and that is load-bearing: an `async` requirement
/// would let a call suspend with the delegate retained, which is how the editor used to
/// outlive its own fetch.
@MainActor
protocol EditorDependencyLoaderDelegate: AnyObject {
    func dependencyLoader(_ loader: EditorDependencyLoader, didUpdate progress: EditorProgress)
    func dependencyLoader(_ loader: EditorDependencyLoader, didLoad dependencies: EditorDependencies)
    func dependencyLoader(_ loader: EditorDependencyLoader, didFailWith error: any Error)
}
