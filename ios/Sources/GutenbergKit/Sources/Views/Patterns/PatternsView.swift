import SwiftUI
import WebKit

struct PatternsView: View {
    let patterns: [Pattern]
    let onPatternSelected: (String) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var contentOpacity: Double = 0

    init(patterns: [Pattern], onPatternSelected: @escaping (String) -> Void) {
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
            .onAppear {
                // Small delay to allow cache warmup before showing content
                Task {
                    try await Task.sleep(for: .milliseconds(330))
                    withAnimation(.easeIn(duration: 0.2)) {
                        contentOpacity = 1.0
                    }
                }
            }
            .onDisappear {
                // Clear memory cache when view is closed to free up memory
                // Disk cache is preserved for faster subsequent loads
                HTMLPreviewRenderer.shared.clearMemoryCache()
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
                                    onPatternSelected(pattern.name)
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
            onPatternSelected: { patternName in
                print("pattern selected: \(patternName)")
            }
        )
    }
}
#endif
