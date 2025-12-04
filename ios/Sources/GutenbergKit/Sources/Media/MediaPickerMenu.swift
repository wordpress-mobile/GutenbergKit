import SwiftUI

struct MediaPickerMenu: View {
    let picker: MediaPickerController
    let context: MediaPickerPresentationContext
    var parameters = MediaPickerParameters()
    let onMediaSelected: ([MediaInfo]) -> Void

    var body: some View {
        Menu {
            ForEach(picker.getActions(for: parameters)) { group in
                Section {
                    ForEach(group.actions, content: makeButton)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    private func makeButton(for action: MediaPickerAction) -> some View {
        Button {
            Task { @MainActor in
                if let viewController = context.viewController {
                    let selection = await picker.perform(action, parameters: parameters, from: viewController)
                    onMediaSelected(selection)
                }
            }
        } label: {
            Label {
                Text(action.title)
            } icon: {
                Image(platformImage: action.image)
            }
        }
    }
}
