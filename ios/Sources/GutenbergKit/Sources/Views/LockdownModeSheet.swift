import SwiftUI

#if canImport(UIKit)
import UIKit

/// A sheet that warns users about Lockdown Mode potentially affecting editor functionality.
///
/// Lockdown Mode applies additional security restrictions to WebKit that can
/// impact the performance and functionality of the Gutenberg editor.
struct LockdownModeSheet: View {
    let onDismiss: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)

                    Text(EditorLocalization[.lockdownModeTitle])
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)

                    Text(EditorLocalization[.lockdownModeWarning])
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text(EditorLocalization[.lockdownModeExcludeHint])
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            VStack(spacing: 12) {
                Button {
                    onLearnMore()
                } label: {
                    Text(EditorLocalization[.lockdownModeLearnMore])
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Text(EditorLocalization[.lockdownModeDismiss])
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
}

#Preview {
    NavigationStack {
        VStack {}.navigationTitle("Demo")
    }.sheet(isPresented: .constant(true)) {
        LockdownModeSheet(onDismiss: {}, onLearnMore: {})
            .presentationDetents([.medium])
    }
}

#endif
