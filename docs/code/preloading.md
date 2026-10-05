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

A cleanup keeps the site's latest bundle, and any bundle the app has been handed since it launched — an open editor, or dependencies the host still holds, may be reading it.

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

An `EditorService`'s cache policy covers plugin and theme assets as well as API responses. For assets, it decides when to check the site's asset manifest again, and how much to download when it does:

| Policy                  | API responses                   | Asset bundle                                               |
| ----------------------- | ------------------------------- | ---------------------------------------------------------- |
| `.always` (default)     | Fetched only when not cached    | Manifest checked only when no bundle is on disk            |
| `.maxAge(TimeInterval)` | Fetched once older than the age | Manifest checked once the last check is older than the age |
| `.ignore`               | Always fetched                  | Manifest always checked, and every asset downloaded again  |

Under `.always` and `.maxAge`, a check downloads only what the manifest says has changed. If the manifest hasn't changed, the bundle on disk is kept rather than downloaded again — asset URLs carry their version (`?ver=`), so the same manifest means the same assets — and its age starts over. Only an asset that failed to download when the bundle was built is asked for again; see [When an asset fails to download](#when-an-asset-fails-to-download). If the manifest has changed, the new bundle is built beside the old one, and every service for the site uses it once it's complete. An asset whose versioned URL a bundle on disk already has is copied from the latest bundle that has it. An asset whose URL has no `?ver=` is asked for again, because its URL can't say whether it changed. If its server sent an `ETag` or `Last-Modified` with the copy on disk, the request asks only for a newer copy, and the one on disk is kept when the server answers that it has none (a 304).

That trusts the site's versions. WordPress gives an asset registered without a version its own version as `?ver=`, so such a file can change while its URL — and so the manifest — stays the same. Only `.ignore` downloads it again.

Under `.ignore`, nothing on disk is taken to be valid, so every asset is downloaded in full whether or not the manifest has changed. That makes it the way to replace an asset that changed without its URL changing, or one that was stored wrong. The assets go into a new bundle beside any the manifest already has: a bundle on disk is never changed, because an editor may be reading it. If the manifest hasn't changed and its assets all come back the same as the bundle on disk has them, that bundle is returned and the new one is discarded, so a host can tell whether a refresh changed anything, and a refresh that changed nothing takes no more disk space. The bundle that's kept still records what the refresh learned: the headers its assets came back with, and which of them failed to download. An asset that comes back with a different `Content-Type` is a change — the editor is served it with that — so the bundle returned isn't equal to the one a host held before.

The old bundle stays on disk for as long as the app is running, because an open editor — or dependencies the host prepared earlier and still holds — may be reading it. `cleanup()` removes it after the next launch.

A bundle holds every link that a `<script src>` or `<link rel="stylesheet">` tag in the manifest loads over HTTP, however the URL ends — `/_static/??a.js,b.js`, `css2?family=Inter` and `/?custom-css=1` are assets like any other. What comes back is kept whatever its type, with one exception: a web page (`text/html`). A site can answer with one and still report success — a page to log in on, say — and kept, it would be served to every editor in the asset's place for as long as the bundle is. An answer like that counts as a failed download. The `Content-Type` an asset came with is stored with it, and the editor is served the asset with it, so the web view decides what to make of an asset just as it would if the site had served it.

Each asset is one file in the bundle's `assets` directory, named for its URL: `example.com_wp-content_plugins_jetpack_blocks_editor.js_ver=15.2.<digest>.js`. The name spells out the host, the path and the query, so a bundle on disk can be read by eye, and two assets that share a path but differ in their host or their query are stored apart. A bundle stored before assets were named this way kept each one at its URL's path. The first time it's read, its assets are copied under their new names into a new bundle beside it, and the site isn't asked for anything — so an update doesn't cost a site its assets while it can't be reached. The copy is as old as the bundle it was made from, and it records each asset it copied as not refreshed: such a bundle kept whatever its site answered with, so the copies are used until the manifest is next checked, and asked for again then.

#### When an asset fails to download

An asset fails to download when its request fails, or is answered with an error or a web page. It never stops a bundle being built, or `prepare()` returning, and it's handled the same way under every policy:

-   If a bundle on disk has a copy of the asset, the new bundle takes that copy, and records that it did. The bundle has everything an editor loads, so it's used like any other until the cache policy next has the manifest checked. That check asks for the asset again, even if its URL has a `?ver=`. `prepareAvailable()` reports the asset as `.assetsNotRefreshed` whenever a prepare goes to the site for the bundle and comes back without it. It doesn't when the bundle is given from disk as the policy asks: nothing was asked of the site then, so nothing failed.
-   If none does, the bundle goes without it, and the editor loads it from the site. `prepareAvailable()` reports it as `.assetsMissing`. A bundle that's missing an asset isn't settled: every prepare checks the manifest and asks for the asset again, whatever the policy, until it downloads. When the site can't be asked, a bundle the policy still trusts is given as it is, and the prepare doesn't fail: the policy asked for no more than that bundle.

What's asked for again goes into a new bundle beside the old one rather than into it, and a try that changes nothing leaves no second bundle. Under `.always` and `.maxAge`, an asset is asked for only for a newer copy, if its server said how to tell one from another.

To refresh a site's editor data — on pull-to-refresh, for instance — prepare a separate service that ignores the cache, and give its dependencies to the next editor:

**Swift**

```swift
let dependencies = try await EditorService(configuration: configuration, cachePolicy: .ignore).prepare()
```

Nothing is deleted first, so an editor opened during the refresh still loads straight from what's on disk, and a refresh that fails leaves it all in place. An editor given no dependencies prepares its own with `.always`, so it uses whatever the last refresh left. A refresh downloads every asset again; to check for changes and download only those, use `.maxAge(0)` instead.

A refresh that fails throws, unless the configuration's `networkFallbackMode` is `.automatic`. To get what there is to give the next editor whether or not it failed, and to know what failed, use `prepareAvailable()` instead; see [Network Fallback Mode](#network-fallback-mode).

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

What the fallback covers differs by platform for now.

**Swift**

`EditorService.prepare()` doesn't throw when a dependency can't be fetched, whatever the reason: the site can't be reached, it answers with an error, or what it answers can't be read. The editor gets the best there is instead. Each dependency falls back on its own: one that can't be fetched comes from the copy on disk, however old, and is left out only if there is no copy. With nothing on disk at all, that's empty dependencies — the same as offline mode — and the bundled editor loads. The post is never stored, so it's always left out, and the editor opens on the title and content its host provides.

`prepare()` gives the dependencies and nothing else, so it can't say that any of this happened. `prepareAvailable()` gives both:

```swift
let preparation = try await EditorService(configuration: configuration).prepareAvailable()

// Always something to give the editor
let dependencies = preparation.dependencies

for failure in preparation.failures {
    switch failure {
    case .notFetched(let dependency, let error, let usingCopyOnDisk):
        // `dependency` couldn't be fetched because of `error`. The dependencies hold the copy
        // on disk in its place if `usingCopyOnDisk`, and nothing for it otherwise.
    case .assetsMissing(let urls):
        // The asset bundle is missing these assets, which failed to download. They're tried
        // again on the next prepare.
    case .assetsNotRefreshed(let urls):
        // These assets failed to download too, but the asset bundle holds an earlier copy of
        // each. They're asked for again the next time the site's asset manifest is checked.
    }
}
```

`prepareAvailable()` behaves the same whatever the fallback mode, and throws only when it's cancelled. The mode decides what `prepare()` does with a dependency that couldn't be fetched: `.disabled` throws its error once every dependency has been tried — whatever could be fetched is stored by then, so trying again starts from there — and `.automatic` returns the dependencies regardless. An asset that fails to download doesn't make `prepare()` throw under either.

**Kotlin**

When a network error is caught (e.g., `notConnectedToInternet`, `timedOut`, `cannotConnectToHost`), `EditorService.prepare()` returns empty dependencies — the same as offline mode — so the bundled editor loads instead of showing an error. Non-network errors (e.g., decoding failures) still propagate normally. Android doesn't yet fall back to what's on disk, or report what failed.

On the JavaScript side, an `OfflineIndicator` component displays a "Working Offline" status bar at the top of the editor when the device loses connectivity. The indicator automatically appears and disappears based on the browser's `online`/`offline` events.

| Mode                              | Use case                                | Behavior                                                                   |
| --------------------------------- | --------------------------------------- | -------------------------------------------------------------------------- |
| `isOfflineModeEnabled: true`      | No site (demo app, standalone editor)   | Skip all networking, use bundled defaults                                  |
| `networkFallbackMode: .automatic` | Site exists but may be offline          | Try network, fall back to what's on disk (iOS), or else the bundled editor |
| `networkFallbackMode: .disabled`  | Site exists, network required (default) | A dependency that can't be fetched is a fatal error                        |

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
