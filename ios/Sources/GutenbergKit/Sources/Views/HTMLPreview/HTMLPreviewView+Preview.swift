#if DEBUG
import SwiftUI

/// SwiftUI view for previewing HTML content
private struct HTMLPreviewDebugView: View {
    let html: String
    let initialViewportWidth: Int

    @State private var viewportWidth: Double
    @State private var debouncedViewportWidth: Int
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var debounceTask: Task<Void, Never>?

    init(html: String, viewportWidth: Int) {
        self.html = html
        self.initialViewportWidth = viewportWidth
        _viewportWidth = State(initialValue: Double(viewportWidth))
        _debouncedViewportWidth = State(initialValue: viewportWidth)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header with refresh button
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HTML Preview Debug")
                            .font(.headline)
                        Text("Viewport: \(Int(viewportWidth))px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            await clearCacheAndRefresh()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Viewport width slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Viewport Width")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(viewportWidth))px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewportWidth, in: 320...2048, step: 1)
                        .onChange(of: viewportWidth) { _, newValue in
                            debounceViewportChange(newValue: Int(newValue))
                        }
                }
                .padding(.horizontal)

                // Preview Content
                if isLoading {
                    ProgressView("Rendering...")
                        .frame(height: 200)
                } else if let error = error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: 200)
                    .padding()
                } else if let image = image {
                    VStack(spacing: 8) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .border(Color.red, width: 1)
                            .padding(.horizontal)

                        Text("Size: \(Int(image.size.width)) × \(Int(image.size.height)) px")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No preview available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                }
            }
            .padding(.vertical)
        }
        .task(id: debouncedViewportWidth) {
            await renderPreview()
        }
    }

    private func renderPreview() async {
        isLoading = true
        error = nil

        do {
            let renderedImage = try await HTMLPreviewManager.shared.render(
                html: html,
                viewportWidth: debouncedViewportWidth
            )
            image = renderedImage
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func clearCacheAndRefresh() async {
        await HTMLPreviewManager.shared.clearCache()
        debouncedViewportWidth = Int(viewportWidth)
    }

    private func debounceViewportChange(newValue: Int) {
        // Cancel any existing debounce task
        debounceTask?.cancel()

        // Create a new debounce task
        debounceTask = Task {
            // Wait for 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Update the debounced value
            debouncedViewportWidth = newValue
        }
    }
}

#Preview("Complex Pattern") {
    HTMLPreviewDebugView(
        html: """
        <!-- wp:group {"metadata":{"name":"Intro"},"align":"full","style":{"spacing":{"margin":{"top":"0","bottom":"0"}}},"className":"alignfull","layout":{"type":"constrained","justifyContent":"center"}} -->
        <div class="wp-block-group alignfull" style="margin-top:0;margin-bottom:0"><!-- wp:spacer {"height":"var:preset|spacing|20"} -->
        <div style="height:var(--wp--preset--spacing--20)" aria-hidden="true" class="wp-block-spacer"></div>
        <!-- /wp:spacer -->
        <!-- wp:group {"metadata":{"name":"Contents"},"align":"wide","layout":{"type":"default"}} -->
        <div class="wp-block-group alignwide"><!-- wp:columns {"verticalAlignment":"top","align":"wide","style":{"spacing":{"blockGap":{"top":"var:preset|spacing|30"}}}} -->
        <div class="wp-block-columns alignwide are-vertically-aligned-top"><!-- wp:column {"verticalAlignment":"top","width":"","layout":{"type":"constrained","justifyContent":"left","contentSize":"450px"}} -->
        <div class="wp-block-column is-vertically-aligned-top"><!-- wp:heading -->
        <h2 class="wp-block-heading">Uncover a realm of opportunities.</h2>
        <!-- /wp:heading --></div>
        <!-- /wp:column -->
        <!-- wp:column {"verticalAlignment":"top","width":"40%"} -->
        <div class="wp-block-column is-vertically-aligned-top" style="flex-basis:40%"><!-- wp:paragraph -->
        <p>Exploring life's complex tapestry, options reveal routes to the exceptional, requiring innovation, inquisitiveness, and bravery for a deeply satisfying voyage.</p>
        <!-- /wp:paragraph -->
        <!-- wp:buttons -->
        <div class="wp-block-buttons"><!-- wp:button -->
        <div class="wp-block-button"><a class="wp-block-button__link wp-element-button">Get Started</a></div>
        <!-- /wp:button --></div>
        <!-- /wp:buttons --></div>
        <!-- /wp:column --></div>
        <!-- /wp:columns -->
        <!-- wp:spacer {"height":"var:preset|spacing|20"} -->
        <div style="height:var(--wp--preset--spacing--20)" aria-hidden="true" class="wp-block-spacer"></div>
        <!-- /wp:spacer -->
        <!-- wp:image {"aspectRatio":"16/9","scale":"cover","sizeSlug":"large","linkDestination":"none"} -->
        <figure class="wp-block-image size-large"><img src="https://pd.w.org/2023/07/44364b18862589f06.53436652.jpg" alt="" style="aspect-ratio:16/9;object-fit:cover" /></figure>
        <!-- /wp:image --></div>
        <!-- /wp:group -->
        <!-- wp:spacer {"height":"var:preset|spacing|20"} -->
        <div style="height:var(--wp--preset--spacing--20)" aria-hidden="true" class="wp-block-spacer"></div>
        <!-- /wp:spacer --></div>
        <!-- /wp:group -->
        """,
        viewportWidth: 375
    )
}

#Preview("Simple Heading") {
    HTMLPreviewDebugView(
        html: """
        <!-- wp:heading -->
        <h2 class="wp-block-heading">Hello, World!</h2>
        <!-- /wp:heading -->
        """,
        viewportWidth: 375
    )
}

#Preview("Multiple Blocks") {
    HTMLPreviewDebugView(
        html: """
        <!-- wp:heading -->
        <h2 class="wp-block-heading">Welcome</h2>
        <!-- /wp:heading -->

        <!-- wp:paragraph -->
        <p>This is a simple paragraph with some text content.</p>
        <!-- /wp:paragraph -->

        <!-- wp:buttons -->
        <div class="wp-block-buttons"><!-- wp:button -->
        <div class="wp-block-button"><a class="wp-block-button__link wp-element-button">Click Me</a></div>
        <!-- /wp:button --></div>
        <!-- /wp:buttons -->
        """,
        viewportWidth: 375
    )
}

#Preview("Wide Viewport") {
    HTMLPreviewDebugView(
        html: """
        <!-- wp:columns -->
        <div class="wp-block-columns"><!-- wp:column -->
        <div class="wp-block-column"><!-- wp:heading -->
        <h2 class="wp-block-heading">Column 1</h2>
        <!-- /wp:heading -->

        <!-- wp:paragraph -->
        <p>Content in the first column.</p>
        <!-- /wp:paragraph --></div>
        <!-- /wp:column -->

        <!-- wp:column -->
        <div class="wp-block-column"><!-- wp:heading -->
        <h2 class="wp-block-heading">Column 2</h2>
        <!-- /wp:heading -->

        <!-- wp:paragraph -->
        <p>Content in the second column.</p>
        <!-- /wp:paragraph --></div>
        <!-- /wp:column --></div>
        <!-- /wp:columns -->
        """,
        viewportWidth: 768
    )
}
#endif
