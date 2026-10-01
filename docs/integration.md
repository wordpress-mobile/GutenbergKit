# Integration Guide

This guide covers how to integrate GutenbergKit into your iOS or Android app. If you are instead interested in integrating GutenbergKit into the WordPress-iOS or WordPress-Android apps, see the [WordPress App Integration](./wordpress-app-integration.md) guide.

## Requirements

### iOS

-   **Platform**: iOS 17+ / macOS 14+
-   **Dependencies** (automatically resolved via Swift Package Manager):
    -   [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML parsing
    -   [SVGView](https://github.com/exyte/SVGView) - SVG rendering for block icons

### Android

-   **Platform**: minSdk 24 (Android 7.0), targetSdk 34
-   **Dependencies** (managed via Gradle):
    -   `androidx.webkit:webkit` - Enhanced WebView features
    -   `com.google.code.gson:gson` - JSON serialization
    -   `kotlinx-coroutines-android` - Async operations

## iOS Integration

### Adding the Package

Add GutenbergKit as a Swift Package dependency in Xcode:

1. Go to **File → Add Package Dependencies...**
2. Enter the GutenbergKit repository URL
3. Select the `GutenbergKit` library product

Note: The `Package.swift` is at the repository root, not in the `ios/` directory.

### Basic Setup

Create an `EditorViewController` with a configuration:

```swift
import GutenbergKit

let configuration = EditorConfigurationBuilder(
    postType: "post",
    siteURL: URL(string: "https://example.com")!,
    siteApiRoot: URL(string: "https://example.com/wp-json")!
)
    .setTitle("My Post")
    .setContent("<!-- wp:paragraph --><p>Hello world</p><!-- /wp:paragraph -->")
    .setAuthHeader("Bearer your-token")
    .build()

let editorViewController = EditorViewController(configuration: configuration)
editorViewController.delegate = self
```

### Configuration Options

The `EditorConfigurationBuilder` provides many options for customizing the editor. See [`EditorConfiguration.swift`](../ios/Sources/GutenbergKit/Sources/Model/EditorConfiguration.swift) for all available options.

### Implementing the Delegate

Implement `EditorViewControllerDelegate` to handle editor events:

```swift
extension YourViewController: EditorViewControllerDelegate {
    func editorDidLoad(_ viewController: EditorViewController) {
        // Editor finished loading
    }

    func editor(_ viewController: EditorViewController, didUpdateContentWithState state: EditorState) {
        // Content changed - state.isEmpty indicates if editor is empty
    }

    func editor(_ viewController: EditorViewController, didUpdateHistoryState state: EditorState) {
        // Undo/redo state changed - use state.hasUndo and state.hasRedo
    }

    func editor(_ viewController: EditorViewController, didRequestMediaFromSiteMediaLibrary config: OpenMediaLibraryAction) {
        // User requested media picker - present your media library UI
    }

    func editor(_ viewController: EditorViewController, didEncounterCriticalError error: Error) {
        // Handle critical errors
    }
}
```

### Getting and Setting Content

```swift
// Set content
editorViewController.setContent("<!-- wp:paragraph --><p>New content</p><!-- /wp:paragraph -->")

// Get content
let content = try await editorViewController.getContent()

// Get title and content together
let result = try await editorViewController.getTitleAndContent()
print("Title: \(result.title), Content: \(result.content)")
```

### Performance Optimization

Pre-warm the editor for faster first load:

```swift
// Call early in your app lifecycle
EditorViewController.warmup(configuration: configuration)
```

For the fastest loading, pre-fetch dependencies:

```swift
let service = EditorService(configuration: configuration)
let dependencies = try await service.prepare { progress in
    print("Loading: \(progress.fractionCompleted * 100)%")
}

// Pass dependencies for instant loading
let editorViewController = EditorViewController(
    configuration: configuration,
    dependencies: dependencies
)
```

## Android Integration

### Adding the Library

There are two ways to add GutenbergKit to your Android project:

**Option 1: Maven dependency (recommended for production)**

Add the Automattic Maven repository to your `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        maven {
            url = uri("https://a8c-libs.s3.amazonaws.com/android")
        }
    }
}
```

Then add the dependency to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("org.wordpress.gutenbergkit:android:<version>")
}
```

**Option 2: Local module (for development)**

Include the `android/Gutenberg/` module directly in your project.

### Basic Setup

Create a `GutenbergView` and start the editor:

```kotlin
import org.wordpress.gutenberg.GutenbergView
import org.wordpress.gutenberg.EditorConfiguration

val gutenbergView = GutenbergView(context)
gutenbergView.initializeWebView()

val configuration = EditorConfiguration.builder()
    .setTitle("My Post")
    .setContent("<!-- wp:paragraph --><p>Hello world</p><!-- /wp:paragraph -->")
    .setPostType("post")
    .setSiteURL("https://example.com")
    .setSiteApiRoot("https://example.com/wp-json")
    .setAuthHeader("Bearer your-token")
    .build()

gutenbergView.start(configuration)
```

### Configuration Options

The `EditorConfiguration.builder()` provides many options for customizing the editor. See [`EditorConfiguration.kt`](../android/Gutenberg/src/main/java/org/wordpress/gutenberg/EditorConfiguration.kt) for all available options.

### Setting Up Listeners

Register listeners to handle editor events:

```kotlin
gutenbergView.setEditorDidBecomeAvailable { view ->
    // Editor finished loading
}

gutenbergView.setContentChangeListener {
    // Content changed
}

gutenbergView.setHistoryChangeListener { hasUndo, hasRedo ->
    // Undo/redo state changed
}

gutenbergView.setOpenMediaLibraryListener { config ->
    // User requested media picker
    // config.allowedTypes, config.multiple, etc.
}

gutenbergView.setLogJsExceptionListener { exception ->
    // Handle JavaScript exceptions
}
```

### Getting and Setting Content

```kotlin
// Set content
gutenbergView.setContent("<!-- wp:paragraph --><p>New content</p><!-- /wp:paragraph -->")

// Get title and content
gutenbergView.getTitleAndContent(
    originalContent = "",
    callback = object : TitleAndContentCallback {
        override fun onResult(title: CharSequence, content: CharSequence) {
            // Use title and content
        }
    },
    completeComposition = true
)
```

### Performance Optimization

Pre-warm the editor for faster first load:

```kotlin
// Call early in your app lifecycle
GutenbergView.warmup(context, configuration)
```

Enable asset caching for plugin and theme styles:

```kotlin
val configuration = EditorConfiguration.builder()
    .setEnableAssetCaching(true)
    .setCachedAssetHosts(setOf("example.com", "cdn.example.com"))
    .build()
```

## Media Handling

The host can transform media before upload by supplying a `MediaProcessor` at init.
To take over the upload itself, supply a `MediaUploader` instead — a processor only
changes bytes; GutenbergKit still delivers them.

```swift
let editor = EditorViewController(
    configuration: configuration,
    mediaProcessor: ResizingProcessor(maxDimension: 2000)
)
```

### Don't conform the object that owns the editor

GutenbergKit never hands your processor the editor: every value crossing that boundary is a
value type — a file URL, a MIME type, a filename. So a processor can only reach the editor
if you put it there.

That happens when you conform the object that already holds the editor in order to drive
it. The editor holds the processor strongly in return — deliberately, so an in-flight upload
can't lose it mid-request — which closes a retain cycle ARC cannot break. The editor is
never deallocated, and each one strands a bound loopback listener.

```swift
// Leaks: coordinator -> editor -> mediaProcessor -> coordinator
final class PostEditorCoordinator: MediaProcessor {
    var editor: EditorViewController!
    init(blog: Blog, configuration: EditorConfiguration) {
        editor = EditorViewController(configuration: configuration, mediaProcessor: self)
    }
}
```

Use a leaf object instead. Nothing is lost: `processFile` is called off the main actor, so
it could not have touched your coordinator's state regardless — whatever it needs is
already separable:

```swift
final class PostEditorCoordinator {
    private let editor: EditorViewController
    init(blog: Blog, configuration: EditorConfiguration) {
        editor = EditorViewController(
            configuration: configuration,
            mediaProcessor: BlogMediaProcessor(siteID: blog.dotComID, maxDimension: 2000)
        )
    }
}
```

If your design genuinely requires the retaining shape, call `stopMediaHandling()` when you
are finished with the editor. It is terminal — the editor cannot upload or delete media
afterwards — so call it when the editor is going away, not when it is merely covered or
backgrounded.

### Reusing a processor across editor sessions

The editor holds the processor for its lifetime and releases it when it goes, so a processor
built for a single editor needs no reference of its own. To use the same instance for
several editors, keep your own reference — the editor drops only its own. Sharing is also
the safer shape: a processor owned by something longer-lived than any editor is a leaf, so
it cannot form the cycle above and there is nothing to tear down. It may be called
concurrently if more than one editor is live, and it must not hold on to any editor it has
served.

## Common Patterns

### Plugin Support

Load custom blocks and editor assets from your site:

```swift
// iOS
let configuration = EditorConfigurationBuilder(...)
    .setShouldUsePlugins(true)
    .setEditorAssetsEndpoint(URL(string: "https://example.com/editor-assets")!)
    .build()
```

```kotlin
// Android
val configuration = EditorConfiguration.builder()
    .setPlugins(true)
    .setEditorAssetsEndpoint("https://example.com/editor-assets")
    .build()
```

### Theme Styles

Apply your site's theme styles to the editor. This requires valid editor settings (JSON) that provide theme style configuration (colors, typography, etc.) from your WordPress site's block editor settings endpoint (`/wp-block-editor/v1/settings`) or elsewhere.

```swift
// iOS
// Fetch editor settings JSON from your WordPress site
let editorSettingsJSON = try await fetchEditorSettings()

let configuration = EditorConfigurationBuilder(...)
    .setShouldUseThemeStyles(true)
    .setEditorSettings(editorSettingsJSON)
    .build()
```

```kotlin
// Android
// Fetch editor settings JSON from your WordPress site
val editorSettingsJSON = fetchEditorSettings()

val configuration = EditorConfiguration.builder()
    .setThemeStyles(true)
    .setEditorSettings(editorSettingsJSON)
    .build()
```

### AJAX Support

Some Gutenberg blocks and features use WordPress AJAX (`admin-ajax.php`) for functionality like form submissions. GutenbergKit supports AJAX requests when properly configured.

**Requirements:**

1. **Production bundle required**: AJAX requests fail with CORS errors when using the development server because the editor runs on `localhost` while AJAX requests target your WordPress site. You must use a production bundle built with `make build`.

2. **Configure `siteURL`**: The `siteURL` configuration option must be set to your WordPress site URL. This is used to construct the AJAX endpoint (`{siteURL}/wp-admin/admin-ajax.php`). On Android, the editor is served from the site's domain so that AJAX requests are same-origin.

3. **Set authentication header**: The `authHeader` configuration must be set. GutenbergKit injects this header into all AJAX requests since the WebView lacks WordPress authentication cookies.

**Configuration examples:**

```swift
// iOS
let configuration = EditorConfigurationBuilder(
    postType: "post",
    siteURL: URL(string: "https://example.com")!,
    siteApiRoot: URL(string: "https://example.com/wp-json")!
)
    .setAuthHeader("Bearer your-token")
    .build()
```

```kotlin
// Android
val configuration = EditorConfiguration.builder(
    siteURL = "https://example.com",
    siteApiRoot = "https://example.com/wp-json"
)
    .setPostType("post")
    .setAuthHeader("Bearer your-token")
    .build()
```
