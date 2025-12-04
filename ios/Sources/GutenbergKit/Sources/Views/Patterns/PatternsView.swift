#if canImport(UIKit)
import SwiftUI
import WebKit

struct PatternsView: View {
    let patterns: [Pattern]
    let patternCategories: [PatternCategory]
    let onPatternSelected: (Pattern) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @StateObject private var memoryCache = HTMLPreviewMemoryCache()
    @AppStorage("GBKPatternsPreviewMode") private var previewMode: PreviewMode = .desktop

    @Environment(\.dismiss) private var dismiss

    init(patterns: [Pattern], patternCategories: [PatternCategory] = [], onPatternSelected: @escaping (Pattern) -> Void) {
        self.patterns = patterns
        self.patternCategories = patternCategories
        self.onPatternSelected = onPatternSelected
        self._viewModel = StateObject(wrappedValue: PatternsViewModel(patterns: patterns, patternCategories: patternCategories))
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
        content
            .searchable(text: $viewModel.searchText)
            .navigationTitle(EditorLocalization[.patterns])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar
            }
            .environment(\.htmlPreviewMemoryCache, memoryCache)
    }

    private var content: some View {
        Group {
            if viewModel.sections.isEmpty {
                if !viewModel.searchText.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    ContentUnavailableView(EditorLocalization[.noPatternsFound], systemImage: "square.grid.2x2")
                }
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
#endif
