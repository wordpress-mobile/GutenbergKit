# Preloading System

## Overview

The preloading system in GutenbergKit pre-fetches WordPress REST API responses before the editor loads, eliminating network latency during editor initialization. By injecting cached API responses directly into the JavaScript runtime, the Gutenberg editor can almost always initialize instantly without waiting for network requests.

## Architecture

The preloading system consists of several interconnected components:

```
+---------------------------------------------------------------------+
|                         EditorService                               |
|  (Orchestrates dependency fetching and caching)                     |
+----------------------------------+----------------------------------+
                                   |
                +------------------+------------------+
                |                  |                  |
                v                  v                  v
   +--------------------+ +--------------+ +--------------------+
   | RESTAPIRepository  | |EditorPreload | |EditorAssetLibrary  |
   | (API caching)      | |    List      | | (JS/CSS bundles)   |
   +---------+----------+ +------+-------+ +--------------------+
             |                   |
             v                   v
   +--------------------+ +-------------------------------------+
   |  EditorURLCache    | |           GBKitGlobal               |
   | (Disk caching)     | | (Serialized to window.GBKit)        |
   +---------+----------+ +------------------+------------------+
             |                               |
             v                               v
   +--------------------+        +-----------------------------+
   |EditorCachePolicy   |        |   JavaScript Preloading     |
   | (TTL management)   |        |       Middleware            |
   +--------------------+        +-----------------------------+
```

## Key Components

### EditorService

The `EditorService` actor coordinates fetching all editor dependencies concurrently:

**Swift**

```swift
let service = EditorService(configuration: config)
let dependencies = try await service.prepare { progress in
    print("Loading: \(progress.fractionCompleted * 100)%")
}
```

**Kotlin**

```kotlin
// TBD
```

The `prepare` method fetches these resources in parallel:

-   Editor settings (theme styles, block settings)
-   Asset bundles (JavaScript and CSS files)
-   Preload list (API responses for editor initialization)

### EditorPreloadList

The `EditorPreloadList` struct contains pre-fetched API responses that are serialized to JSON and injected into the editor's JavaScript runtime:

| Property              | API Endpoint                               | Description                                 |
| --------------------- | ------------------------------------------ | ------------------------------------------- |
| `postData`            | `/wp/v2/posts/{id}?context=edit`           | The post being edited (existing posts only) |
| `postTypeData`        | `/wp/v2/types/{type}?context=edit`         | Schema for the current post type            |
| `postTypesData`       | `/wp/v2/types?context=view`                | All available post types                    |
| `activeThemeData`     | `/wp/v2/themes?context=edit&status=active` | Active theme information                    |
| `settingsOptionsData` | `OPTIONS /wp/v2/settings`                  | Site settings schema                        |

### EditorURLCache

The `EditorURLCache` provides disk-based caching for API responses, keyed by URL and HTTP method. It supports three cache policies via `EditorCachePolicy`:

| Policy                  | Behavior                                            |
| ----------------------- | --------------------------------------------------- |
| `.ignore`               | Never use cached responses (force fresh data)       |
| `.maxAge(TimeInterval)` | Use cached responses younger than the specified age |
| `.always`               | Always use cached responses regardless of age       |

Example:

**Swift**

```swift
// Cache responses for up to 1 hour
let service = EditorService(
    configuration: config,
    cachePolicy: .maxAge(3600)
)
```

**Kotlin**

```kotlin
// TBD
```

### RESTAPIRepository

The `RESTAPIRepository` handles fetching and caching individual API responses. It follows a read-through caching pattern:

1. Check cache for existing response
2. If cache hit and valid per policy, return cached data
3. If cache miss or expired, fetch from network
4. Store response in cache
5. Return response

## Data Flow

### 1. Preparation Phase (Native)

When `EditorService.prepare()` is called:

```
EditorService.prepare()
    |-- prepareEditorSettings()      -> EditorSettings
    |-- prepareAssetBundle()         -> EditorAssetBundle
    +-- preparePreloadList()
        |-- prepareActiveTheme()     -> EditorURLResponse
        |-- prepareSettingsOptions() -> EditorURLResponse
        |-- preparePost(type:)       -> EditorURLResponse
        |-- preparePostTypes()       -> EditorURLResponse
        +-- preparePost(id:)         -> EditorURLResponse (if editing existing post)
```

### 2. Serialization Phase (Native)

The `EditorPreloadList` is converted to JSON via `build()`:

```json
{
  "/wp/v2/types/post?context=edit": {
    "body": { "slug": "post", "supports": { ... } },
    "headers": { "Link": "<...>; rel=\"https://api.w.org/\"" }
  },
  "/wp/v2/types?context=view": {
    "body": { "post": { ... }, "page": { ... } },
    "headers": {}
  },
  "/wp/v2/themes?context=edit&status=active": {
    "body": [ ... ],
    "headers": {}
  },
  "OPTIONS": {
    "/wp/v2/settings": {
      "body": { ... },
      "headers": {}
    }
  }
}
```

### 3. Injection Phase (Native to Web)

The `GBKitGlobal` struct packages all configuration and preload data, then injects it into the WebView as `window.GBKit`:

```javascript
window.GBKit = {
	siteURL: 'https://example.com',
	siteApiRoot: 'https://example.com/wp-json',
	authHeader: 'Bearer ...',
	preloadData: {
		/* serialized EditorPreloadList */
	},
	editorSettings: {
		/* theme styles, colors, etc. */
	},
	// ... other configuration
};
```

### 4. Consumption Phase (JavaScript)

The `@wordpress/api-fetch` package includes a preloading middleware that intercepts API requests:

```javascript
// In src/utils/api-fetch.js
export function configureApiFetch() {
	const { preloadData } = getGBKit();

	apiFetch.use(
		apiFetch.createPreloadingMiddleware( preloadData ?? defaultPreloadData )
	);
}
```

When Gutenberg makes an API request:

1. The preloading middleware checks if the request path exists in `preloadData`
2. If found, the cached response is returned immediately (no network request)
3. If not found, the request proceeds to the network
4. The preload entry is consumed (one-time use) to ensure fresh data on subsequent requests

## Header Filtering

Only certain headers are preserved in preload responses to match WordPress core's behavior:

-   `Accept` - Content type negotiation
-   `Link` - REST API discovery and pagination

This filtering is performed by `EditorURLResponse.asPreloadResponse()`.

## Cache Management

### Automatic Cleanup

`EditorService` automatically cleans up old asset bundles once per day:

**Swift**

```swift
try await onceEvery(.seconds(86_400)) {
    try await self.cleanup()
}
```

**Kotlin**

```kotlin
//tbd
```

### Manual Cache Control

**Swift**

```swift
// Clear unused resources (keeps most recent)
try await service.cleanup()

// Clear all resources (requires re-download)
try await service.purge()
```

**Kotlin**

```kotlin
//tbd
```

## Offline Mode

When `EditorConfiguration.isOfflineModeEnabled` is `true`, the preloading system returns empty dependencies:

```swift
if self.configuration.isOfflineModeEnabled {
    return EditorDependencies(
        editorSettings: .undefined,
        assetBundle: .empty,
        preloadList: nil
    )
}
```

Offline mode doesn't refer to reguar site that are offline – it's for when you're using GutenbergKit separately from a WordPress
site (for instance, the bundled editor in the demo app, or you just want an editor without the WP integration).

The JavaScript side falls back to `defaultPreloadData` which contains minimal type definitions to allow basic editor functionality.

## Network Fallback Mode

When `EditorConfiguration.networkFallbackMode` is set to `.automatic`, the editor gracefully handles network failures for sites that exist but are temporarily unreachable. Unlike offline mode (which skips networking entirely), network fallback mode attempts to fetch dependencies normally and only falls back to the bundled editor when a network error occurs.

```swift
let config = EditorConfigurationBuilder(
    postType: .post,
    siteURL: siteURL,
    siteApiRoot: apiRoot,
    userCapabilities: UserCapabilities(uploadFiles: true)
)
.setNetworkFallbackMode(.automatic)
.build()
```

When a network error is caught (e.g., `notConnectedToInternet`, `timedOut`, `cannotConnectToHost`), `EditorService.prepare()` returns empty dependencies — the same as offline mode — so the bundled editor loads instead of showing an error. Non-network errors (e.g., decoding failures) still propagate normally.

On the JavaScript side, an `OfflineIndicator` component displays a "Working Offline" status bar at the top of the editor when the device loses connectivity. The indicator automatically appears and disappears based on the browser's `online`/`offline` events.

| Mode                              | Use case                                | Behavior                                                    |
| --------------------------------- | --------------------------------------- | ----------------------------------------------------------- |
| `isOfflineModeEnabled: true`      | No site (demo app, standalone editor)   | Skip all networking, use bundled defaults                   |
| `networkFallbackMode: .automatic` | Site exists but may be offline          | Try network, fall back to bundled editor on network failure |
| `networkFallbackMode: .disabled`  | Site exists, network required (default) | Network failures are fatal errors                           |

## Progress Reporting

The preloading system reports its progress to give the user high-quality feedback about the loading process - if the user loads the
editor without `EditorDependencies` present, the editor will display a loading screen with a progress bar. If the user provides `EditorDependencies`
that contain everything the editor needs, the progress bar will never be displayed.

## EditorDependencies

`EditorDependencies` contains all pre-fetched resources needed to initialize the editor instantly.

| Property         | Type                 | Description                                      |
| ---------------- | -------------------- | ------------------------------------------------ |
| `editorSettings` | `EditorSettings`     | Theme styles, colors, typography, block settings |
| `assetBundle`    | `EditorAssetBundle`  | Cached JavaScript/CSS for plugins/themes         |
| `preloadList`    | `EditorPreloadList?` | Pre-fetched API responses                        |

### Obtaining Dependencies

```swift
let service = EditorService(configuration: configuration)
let dependencies = try await service.prepare { progress in
    loadingView.progress = progress.fractionCompleted
}
```

### EditorViewController Loading Flows

`EditorViewController` supports two loading flows based on whether dependencies are provided:

#### Flow 1: Dependencies Provided (Recommended)

```swift
let editor = EditorViewController(
    configuration: configuration,
    dependencies: dependencies  // Loads immediately
)
```

The editor skips the progress UI and loads the WebView immediately.

#### Flow 2: No Dependencies (Fallback)

```swift
let editor = EditorViewController(
    configuration: configuration
    // No dependencies - fetches automatically
)
```

The editor displays a progress bar while fetching, then loads once complete.

### Best Practice: Prepare Early

Fetch dependencies before the user needs the editor:

```swift
class PostListViewController: UIViewController {
    private var editorDependencies: EditorDependencies?
    private let editorService: EditorService

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            self.editorDependencies = try? await editorService.prepare { _ in }
        }
    }

    func editPost(_ post: Post) {
        let editor = EditorViewController(
            configuration: EditorConfiguration(post: post),
            dependencies: editorDependencies
        )
        navigationController?.pushViewController(editor, animated: true)
    }
}
```
