import SwiftUI
import WebKit

struct PatternsView: View {
    let patterns: [Pattern]
    let onPatternSelected: (Pattern) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @StateObject private var memoryCache = HTMLPreviewMemoryCache()
    @State private var contentOpacity: Double = 0

    @Environment(\.dismiss) private var dismiss

    init(patterns: [Pattern], onPatternSelected: @escaping (Pattern) -> Void) {
        self.patterns = patterns
        self.onPatternSelected = onPatternSelected
        self._viewModel = StateObject(wrappedValue: PatternsViewModel(patterns: patterns))
    }

    var body: some View {
        // TODO: CMM-874 l10n
        content
            .opacity(contentOpacity)
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar
            }
            .environment(\.htmlPreviewMemoryCache, memoryCache)
            .onAppear {
                // Small delay to allow cache warmup before showing content
                Task {
                    try await Task.sleep(for: .milliseconds(400))
                    withAnimation(.easeInOut) {
                        contentOpacity = 1.0
                    }
                }
            }
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
                                }
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
    }
}
#endif
