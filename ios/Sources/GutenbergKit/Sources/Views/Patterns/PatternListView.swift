import SwiftUI

/// A full-screen view showing all patterns in a category
struct PatternListView: View {
    let section: PatternSection
    let onPatternSelected: (Pattern) -> Void

    @Environment(\.dismiss) private var dismiss

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
                        style: .fullWidth(maxHeight: 400)
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
