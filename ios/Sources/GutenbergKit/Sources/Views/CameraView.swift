#if canImport(UIKit)
import UIKit
import SwiftUI
import UniformTypeIdentifiers

enum CameraMedia {
    case photo(UIImage)
    case video(URL)
}

struct CameraView: UIViewControllerRepresentable {
    var onMediaCaptured: ((CameraMedia) -> Void)?

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]  // Support both photo and video
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.dismiss()

            if let image = info[.originalImage] as? UIImage {
                parent.onMediaCaptured?(.photo(image))
            } else if let videoURL = info[.mediaURL] as? URL {
                parent.onMediaCaptured?(.video(videoURL))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
