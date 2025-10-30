import SwiftUI
import WebKit

struct PatternsView: View {
    let loadPatterns: () async throws -> [PatternType]
    let onPatternSelected: (String) -> Void

    @StateObject private var viewModel: PatternsViewModel
    @Environment(\.dismiss) private var dismiss

    init(loadPatterns: @escaping () async throws -> [PatternType], onPatternSelected: @escaping (String) -> Void) {
        self.loadPatterns = loadPatterns
        self.onPatternSelected = onPatternSelected
        self._viewModel = StateObject(wrappedValue: PatternsViewModel())
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
            .task {
                await viewModel.loadPatterns(using: loadPatterns)
            }
    }

    private var content: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            } else if viewModel.error != nil {
                ContentUnavailableView(
                    "Failed to Load Patterns",
                    systemImage: "exclamationmark.triangle",
                    description: Text("An error occurred while loading patterns")
                )
            } else if viewModel.sections.isEmpty {
                ContentUnavailableView(
                    "No Patterns Found",
                    systemImage: "square.grid.2x2",
                    description: Text(viewModel.searchText.isEmpty ? "There are no patterns available" : "Try a different search")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.sections) { section in
                            PatternSectionView(
                                section: section,
                                onPatternSelected: { pattern in
                                    dismiss()
                                    onPatternSelected(pattern.name)
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                }
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
            loadPatterns: {
                return []
            },
            onPatternSelected: { patternName in
                print("pattern selected: \(patternName)")
            }
        )
    }
}
#endif
