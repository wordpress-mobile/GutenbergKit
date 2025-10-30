import SwiftUI
import WebKit

struct PatternsView: View {
    let patterns: [PatternType]
    let onPatternSelected: (String) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @Environment(\.dismiss) private var dismiss

    init(patterns: [PatternType], onPatternSelected: @escaping (String) -> Void) {
        self.patterns = patterns
        self.onPatternSelected = onPatternSelected
        self._viewModel = StateObject(wrappedValue: PatternsViewModel(patterns: patterns))
    }

    var body: some View {
        content
            .background(Material.ultraThin)
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Patterns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbar
            }
            .onDisappear {
                // Clear memory cache when view is closed to free up memory
                // Disk cache is preserved for faster subsequent loads
                Task {
                    await HTMLPreviewRenderer.shared.clearMemoryCache()
                }
            }
    }

    private var content: some View {
        Group {
            if viewModel.sections.isEmpty {
                ContentUnavailableView(
                    "No Patterns Found",
                    systemImage: "square.grid.2x2",
                    description: Text(viewModel.searchText.isEmpty ? "There are no patterns available" : "Try a different search")
                )
            } else {
                List {
                    ForEach(viewModel.sections) { section in
                        Section {
                            PatternGridSection(
                                section: section,
                                onPatternSelected: { pattern in
                                    dismiss()
                                    onPatternSelected(pattern.name)
                                }
                            )
                        } header: {
                            Text(section.name)
                                .font(.headline)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
