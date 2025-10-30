import SwiftUI
import GutenbergKit

struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearCacheAlert = false
    @State private var cacheCleared = false

    var body: some View {
        List {
            Section {
                Button(role: .destructive) {
                    showingClearCacheAlert = true
                } label: {
                    HStack {
                        Text("Clear Preview Cache")
                        Spacer()
                        if cacheCleared {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Cache")
            } footer: {
                Text("Clears all cached preview images. Previews will be re-rendered on next view.")
            }
        }
        .navigationTitle("Debug Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Clear Preview Cache?", isPresented: $showingClearCacheAlert) {
            Button("Clear", role: .destructive) {
                clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached preview images. They will be regenerated when needed.")
        }
    }

    private func clearCache() {
        Task {
            await HTMLPreviewRenderer.shared.clearCache()
            cacheCleared = true

            // Reset the checkmark after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            cacheCleared = false
        }
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
    }
}
