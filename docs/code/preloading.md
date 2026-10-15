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

The same policy decides when an `EditorService` checks for new plugin and theme assets; see [Refreshing](#refreshing).

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

`EditorService` automatically cleans up each site's old asset bundles once per day:

**Swift**

```swift
try await onceEvery(
    .seconds(86_400),
    { try await self.cleanup() },
    handle: "asset-bundle-cleanup-\(self.configuration.siteId)"
)
```

A cleanup keeps the site's latest bundle, and any bundle handed out to the app since it launched, because an open editor, or dependencies the host still holds, may be reading it.

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

### Refreshing

An `EditorService`'s cache policy applies to plugin and theme assets as well as API responses. For assets, it decides when to check the site's asset manifest again:

| Policy                  | API responses                   | Asset bundle                                                         |
| ----------------------- | ------------------------------- | -------------------------------------------------------------------- |
| `.always` (default)     | Fetched only when not cached    | Manifest checked only when there's no bundle, or it's missing assets |
| `.maxAge(TimeInterval)` | Fetched once older than the age | Manifest checked once the last check is older than the age           |
| `.ignore`               | Always fetched                  | Manifest always checked, and every asset downloaded again            |

Under `.always` and `.maxAge`, a check downloads only what has changed:

-   If the manifest hasn't changed, the bundle on disk is kept, and its age starts over. Asset URLs carry their version (`?ver=`), so the same manifest means the same assets. Assets the bundle is missing are retried; see [When an asset fails to download](#when-an-asset-fails-to-download).
-   If the manifest has changed, a new bundle is built beside the old one. Each asset with a `?ver=` that a bundle on disk already has is copied from it, and the rest are downloaded. Every service for the site uses the new bundle once it's complete.

This trusts the site's versions. WordPress gives an asset registered without a version `?ver=<WordPress version>`, so that file can change while its URL, and the manifest, stay the same. Only `.ignore` picks up that change.

Under `.ignore`, every asset is downloaded again, whether or not the manifest has changed. Use it to replace an asset that changed without its URL changing, or one that was stored wrong. The assets go into a new bundle beside the old one, which an editor may still be reading. If the manifest hasn't changed and every asset comes back identical, the old bundle is returned and the new one is discarded, so a host can compare dependencies to tell whether a refresh changed anything. A changed `Content-Type` counts as a change: the old bundle is returned with the new type, and isn't equal to the one the host held. Assets that didn't change share disk space with their old copies, so a refresh only takes space for what changed.

An old bundle handed out to the app stays on disk while the app is running, because an open editor, or dependencies the host still holds, may be reading it. `cleanup()` removes it after the next launch.

Which bundle is a site's latest depends on when the site's manifest last matched each one, by the device's clock. If the clock was ahead and has since been set back, a bundle built for a changed manifest sorts behind the earlier bundle, which stays the latest until the clock passes its date. `purge()` fixes this, by removing every bundle.

A bundle stores every HTTP or HTTPS URL in the manifest's `<script src>` and `<link rel="stylesheet">` tags, including ones like `/_static/??a.js,b.js` and `css2?family=Inter`. The editor is served each asset with the `Content-Type` the site sent. Each asset is one file in the bundle's `assets` directory, named after its URL so that a bundle on disk can be read by eye: `example.com_wp-content_plugins_jetpack_blocks_editor.js_ver=15.2.<digest>.js`. Bundles stored by earlier versions of GutenbergKit keep their assets in a different layout, so they're downloaded again once.

#### When an asset fails to download

A download fails when its request fails, or when the site answers with an error or a web page (`text/html`, such as a login page). A failed download never makes a build or `prepare()` fail, under any policy:

-   If a bundle on disk has a copy of the asset, the new bundle uses that copy. Nothing records the failure, so the asset isn't asked for again until it would be anyway: on an `.ignore` refresh, or, for an asset without a `?ver=`, when the manifest changes.
-   Otherwise, the bundle goes without the asset, and the editor loads it from the site. Every prepare then checks the manifest and retries the asset, under any policy, until it downloads. If that check fails, the bundle is still returned without the asset, unless the cache policy requires a check.

A retry goes into a new bundle beside the old one. A retry that changes nothing leaves no new bundle.

#### Pull-to-refresh

To refresh a site's editor data — on pull-to-refresh, for instance — prepare a separate service that ignores the cache, and give its dependencies to the next editor:

**Swift**

```swift
let dependencies = try await EditorService(configuration: configuration, cachePolicy: .ignore).prepare()
```

Nothing is deleted first, so an editor opened during the refresh still loads from disk, and a refresh that fails leaves everything in place. An editor given no dependencies prepares its own with `.always`, so it uses whatever the last refresh left. To check for changes and download only those, use `.maxAge(0)` instead of `.ignore`.

A refresh that fails throws, unless the configuration's `networkFallbackMode` is `.automatic`; see [Network Fallback Mode](#network-fallback-mode).

**Kotlin**

Not yet: Android's `EditorService` still checks the asset manifest only when no bundle is on disk, whatever its cache policy.

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
    siteApiRoot: apiRoot
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

#### Sharing Work Between Services

Every `EditorService` for a site reads and writes the same on-disk caches, so there's no need to hand a service from a
prefetch to the editor — create one for each caller. Don't call `prepare()` on a service while an earlier call on it is
still running: progress is tracked per service, so the later call takes over the progress callback, and whichever
finishes first stops progress for both.

Services for the same site also share work while it's in flight. A request identical to one already in flight joins it
rather than going out again, and a build of an asset bundle joins the one already running. So an editor opened before a
prefetch finishes fetches only its own post and the `editor-assets` manifest, even when the two are for different posts.
Requests are shared only between clients with the same `URLSession` instance, credentials, and timeout, and never from a
client with a delegate, which expects to see every request it makes. A bundle build is shared by every service for the
site whatever its client, just as the bundle it produces is once it's on disk.

The request for the post is never shared, even between two editors on the same post: one already in flight can predate
an edit made since. It opts out through its cache policy — a request that asks to skip the cache
(`.reloadIgnoringLocalCacheData` and its siblings) always goes out on its own — and a host's own requests through
`EditorHTTPClient` can do the same.

Cancelling a caller ends only that caller's wait; shared work stops once no caller is left waiting on it. `purge()`
doesn't stop it, so work that began before a purge can still land after it.

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

The editor displays a progress bar while fetching, then loads once complete. The fetch does not hold the
editor: releasing it mid-fetch frees it immediately, and the fetch finishes in the background, warming the
cache for the next editor.

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
