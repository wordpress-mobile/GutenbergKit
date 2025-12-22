# Integration Guide

This guide covers how to integrate GutenbergKit into your iOS or Android app.

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

Add the GutenbergKit Swift package from the `ios/` directory to your Xcode project.

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

Add the GutenbergKit library from the `android/Gutenberg/` directory to your project.

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
