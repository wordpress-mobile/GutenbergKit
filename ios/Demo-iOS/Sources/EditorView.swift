import SwiftUI
import GutenbergKit

struct EditorView: View {
    private let configuration: EditorConfiguration

    @Environment(\.dismiss) private var dismiss

    init(configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    var body: some View {
        _EditorView(configuration: configuration)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { dismiss() }, label: {
                        Image(systemName: "xmark")
                    })
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.backward")
                    })
                    Button(action: {}, label: {
                        Image(systemName: "arrow.uturn.forward")
                    }).disabled(true)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {}, label: {
                        Image(systemName: "safari")
                    })

                    moreMenu
                }
            }
            .tint(Color.primary)
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: {}, label: {
                    Label("Code Editor", systemImage: "curlybraces")
                })
                Button(action: {}, label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                })
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Preview", systemImage: "safari")
                })
            }
            Section {
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Revisions (42)", systemImage: "clock.arrow.circlepath")
                })
                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Post Settings", systemImage: "gearshape")
                })

                Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                    Label("Help", systemImage: "questionmark.circle")
                })
            }
            Section {
                Text("Blocks: 4, Words: 8, Characters: 15")
            } header: {

            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Color.primary)
    }
}

private struct _EditorView: UIViewControllerRepresentable {
    private let configuration: EditorConfiguration

    init(editorURL: URL? = nil, configuration: EditorConfiguration) {
        self.configuration = configuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> EditorViewController {
        let viewController = EditorViewController(configuration: configuration)
        viewController.delegate = context.coordinator
        if #available(iOS 16.4, *) {
            viewController.webView.isInspectable = true
        }
        viewController.startEditorSetup()
        return viewController
    }

    func updateUIViewController(_ uiViewController: EditorViewController, context: Context) {
        // Do nothing
    }
    
    class Coordinator: NSObject, EditorViewControllerDelegate {
        func editorDidLoad(_ viewContoller: EditorViewController) {
            print("Editor did load")
        }
        
        func editor(_ viewContoller: EditorViewController, didDisplayInitialContent content: String) {
            print("Editor displayed initial content")
        }
        
        func editor(_ viewContoller: EditorViewController, didEncounterCriticalError error: Error) {
            print("Editor critical error: \(error)")
        }
        
        func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState) {
            // Handle content updates
        }
        
        func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState) {
            // Handle history updates
        }
        
        func editor(_ viewController: EditorViewController, didUpdateFeaturedImage mediaID: Int) {
            print("Featured image updated: \(mediaID)")
        }
        
        func editor(_ viewController: EditorViewController, didLogException error: GutenbergJSException) {
            print("JS Exception: \(error.message)")
        }
        
        func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction) {
            print("Requested site media library")
        }
        
        func getMediaPickerController(for viewController: EditorViewController, parameters: MediaPickerParameters) -> (any MediaPickerController)? {
            MockMediaPickerController()
        }
    }
}

private struct MockMediaPickerController: MediaPickerController {
    var actions: [[MediaPickerAction]] = [[
        MediaPickerAction(
            id: "image-playground",
            title: "Image Playground",
            image: UIImage(systemName: "apple.image.playground")!
        ) { presentingViewController, completion in
            showPickerAlert(for: "Image Playground", in: presentingViewController, completion: completion)
        },
        MediaPickerAction(
            id: "files",
            title: "Files",
            image: UIImage(systemName: "folder")!
        ) { presentingViewController, completion in
            showPickerAlert(for: "Files", in: presentingViewController, completion: completion)
        }
    ], [
        MediaPickerAction(
            id: "free-photos",
            title: "Free Photos Library",
            image: UIImage(systemName: "photo.on.rectangle")!
        ) { presentingViewController, completion in
            showPickerAlert(for: "Free Photos Library", in: presentingViewController, completion: completion)
        },
        MediaPickerAction(
            id: "free-gifs",
            title: "Free GIF Library",
            image: UIImage(systemName: "photo.stack")!
        ) { presentingViewController, completion in
            showPickerAlert(for: "Free GIF Library", in: presentingViewController, completion: completion)
        }
    ]]
}

private func showPickerAlert(for pickerName: String, in viewController: UIViewController, completion: @escaping ([MediaInfo]) -> Void) {
    let alert = UIAlertController(
        title: "Media Picker",
        message: "Picker not implemented: \(pickerName)",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
        completion([])
    })
    viewController.present(alert, animated: true)
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        guard let presentedViewController else {
            return self
        }
        return presentedViewController.topPresentedViewController
    }
}

#Preview {
    NavigationStack {
        EditorView(configuration: .default)
    }
}
