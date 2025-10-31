import SwiftUI

/// A full-screen view showing all patterns in a category
struct PatternListView: View {
    let section: PatternSection
    let onPatternSelected: (Pattern) -> Void
    let viewportWidth: Int?

    @Environment(\.dismiss) private var dismiss

    init(section: PatternSection, onPatternSelected: @escaping (Pattern) -> Void, viewportWidth: Int? = nil) {
        self.section = section
        self.onPatternSelected = onPatternSelected
        self.viewportWidth = viewportWidth
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(section.patterns) { pattern in
                    PatternCardView(
                        pattern: pattern,
                        onSelected: {
                            dismiss()
                            onPatternSelected(pattern)
                        },
                        style: .fullWidth(maxHeight: 400),
                        viewportWidth: viewportWidth
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Material.ultraThin)
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
