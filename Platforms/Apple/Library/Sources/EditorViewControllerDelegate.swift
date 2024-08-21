import Foundation
#if canImport(UIKit)
public protocol EditorViewControllerDelegate: AnyObject {
    /// Gets called when the editor is loaded and the initial content is displayed.
    ///
    /// - parameter content: Content serialized according to the editor's settings.
    func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String)

    /// Editor encounterd a critical error and has to be stopped.
    ///
    /// - warning: Make sure not to update user content if that happens (it shouldn't)
    func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error)

    /// Notifies the client about the new edits.
    ///
    /// - note: To get the latest content, call ``EditorViewController/getContent()``.
    /// Retrieving the content is a relatively expensive operation and should not
    /// be performed too frequently during editing.
    ///
    /// - warning: This is currently also called for the initial render, which
    /// is probably not how it should be in the production design.
    func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState)
}

public struct EditorState {
    /// Set to `true` if the editor has non-empty content.
    public var isEmpty = true
}

#endif
