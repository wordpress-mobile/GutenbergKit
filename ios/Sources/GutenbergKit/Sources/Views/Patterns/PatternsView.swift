import SwiftUI
import WebKit

struct PatternsView: View {
    let patterns: [Pattern]
    let onPatternSelected: (Pattern) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @StateObject private var memoryCache = HTMLPreviewMemoryCache()
    @AppStorage("GBKPatternsPreviewMode") private var previewMode: PreviewMode = .desktop

    @Environment(\.dismiss) private var dismiss

    init(patterns: [Pattern], onPatternSelected: @escaping (Pattern) -> Void) {
        self.patterns = patterns
        self.onPatternSelected = onPatternSelected
        self._viewModel = StateObject(wrappedValue: PatternsViewModel(patterns: patterns))
    }

    private var viewportWidth: Int? {
        switch previewMode {
        case .mobile:
            return 375
        case .desktop:
            return nil
        }
    }

    var body: some View {
        // TODO: CMM-874 l10n
        content
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar
            }
            .environment(\.htmlPreviewMemoryCache, memoryCache)
    }

    private var content: some View {
        Group {
            if viewModel.sections.isEmpty {
                // TODO: CMM-874 l10n
                ContentUnavailableView(
                    "No Patterns Found",
                    systemImage: "square.grid.2x2",
                    description: Text(viewModel.searchText.isEmpty ? "There are no patterns available" : "Try a different search")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(viewModel.sections) { section in
                            PatternGridSection(
                                section: section,
                                onPatternSelected: { pattern in
                                    dismiss()
                                    onPatternSelected(pattern)
                                },
                                viewportWidth: viewportWidth
                            )
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .tint(Color.primary)
        }

        ToolbarItem(placement: .primaryAction) {
            PatternsTogglePreviewModeButton()
        }
    }
}

enum PreviewMode: String {
    case mobile
    case desktop

    mutating func toggle() {
        self = self == .mobile ? .desktop : .mobile
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PatternsView(
            patterns: [],
            onPatternSelected: { pattern in
                print("pattern selected: \(pattern.name)")
            }
        )
        .environmentObject(HTMLPreviewManager())
    }
}
#endif
