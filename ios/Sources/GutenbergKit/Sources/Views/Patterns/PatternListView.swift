import SwiftUI

/// A full-screen view showing all patterns in a category
struct PatternListView: View {
    let section: PatternSection
    let onPatternSelected: (Pattern) -> Void

    @AppStorage("GBKPatternsPreviewMode") private var previewMode: PreviewMode = .desktop
    @Environment(\.dismiss) private var dismiss

    init(section: PatternSection, onPatternSelected: @escaping (Pattern) -> Void) {
        self.section = section
        self.onPatternSelected = onPatternSelected
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
        List {
            ForEach(section.patterns) { pattern in
                VStack(alignment: .leading, spacing: 8) {
                    PatternCardView(
                        pattern: pattern,
                        onSelected: {
                            dismiss()
                            onPatternSelected(pattern)
                        },
                        style: .fullWidth(maxHeight: 400),
                        viewportWidth: viewportWidth
                    )
                    Text(pattern.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .background(Color(.secondarySystemBackground))
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbar
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            PatternsTogglePreviewModeButton()
        }
    }
}
