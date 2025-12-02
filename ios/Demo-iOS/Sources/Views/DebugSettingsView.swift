import SwiftUI
import GutenbergKit

struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearCacheAlert = false
    @State private var cacheCleared = false
    @State private var showingClearEditorDataAlert = false
    @State private var editorDataCleared = false

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

            Section {
                Button(role: .destructive) {
                    showingClearEditorDataAlert = true
                } label: {
                    HStack {
                        Text("Clear Editor Data")
                        Spacer()
                        if editorDataCleared {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Editor Service")
            } footer: {
                Text("Deletes all cached editor settings and assets. The editor will re-download everything on next launch.")
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
        .alert("Clear Editor Data?", isPresented: $showingClearEditorDataAlert) {
            Button("Clear", role: .destructive) {
                clearEditorData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached editor settings and assets. The editor will re-download everything on next launch.")
        }
    }

    private func clearCache() {
        Task {
            await HTMLPreviewManager.clearCache()
            cacheCleared = true

            // Reset the checkmark after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            cacheCleared = false
        }
    }

    private func clearEditorData() {
        Task {
            try? EditorViewController.deleteAllData()
            editorDataCleared = true

            // Reset the checkmark after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            editorDataCleared = false
        }
    }
}

#Preview {
    NavigationStack {
        DebugSettingsView()
    }
}
