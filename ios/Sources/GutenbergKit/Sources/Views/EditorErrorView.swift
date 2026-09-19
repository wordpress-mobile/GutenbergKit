import SwiftUI

#if canImport(UIKit)

/// An editor error state that moves VoiceOver focus to its title when it appears.
///
/// The error replaces content VoiceOver may have been reading, so focus moves to
/// the title, which VoiceOver reads as a heading.
struct EditorErrorView<Actions: View>: View {
    private let title: String
    private let description: String
    private let actions: Actions

    @AccessibilityFocusState private var isTitleFocused: Bool

    init(title: String, description: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.circle")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
        } description: {
            Text(description)
        } actions: {
            actions
        }
        .onAppear {
            isTitleFocused = true
        }
    }
}

extension EditorErrorView where Actions == EmptyView {
    init(title: String, description: String) {
        self.init(title: title, description: description) { EmptyView() }
    }
}

#endif
