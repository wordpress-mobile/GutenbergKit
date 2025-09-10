import Foundation
import WebKit

class EditorAssetsProvider: NSObject, WKScriptMessageHandlerWithReply {
    let library: EditorAssetsLibrary

    init(library: EditorAssetsLibrary) {
        self.library = library
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let payload = message.body as? NSDictionary,
              let asset = payload.object(forKey: "asset") as? String,
              asset == "manifest"
        else {
            replyHandler(nil, "Unexpected message")
            return
        }

        Task.detached { [library] in
            do {
                let data = try await library.manifestContentForEditor()
                let dict = try JSONSerialization.jsonObject(with: data)
                await replyHandler(dict, nil)
            } catch {
                await replyHandler(nil, error.localizedDescription)
            }
        }
    }
}
