# GutenbergKit Architecture

## Overview

GutenbergKit is a cross-platform Gutenberg block editor implementation that bridges WordPress's web-based editor with native iOS and Android applications. The architecture consists of three main layers:

1. **Web Layer**: React-based editor using WordPress Gutenberg packages
2. **Bridge Layer**: Bidirectional communication between web and native code
3. **Native Layer**: Platform-specific implementations (Swift for iOS, Kotlin for Android)

## Project Structure

```
GutenbergKit/
├── src/                    # Web editor source code
│   ├── components/         # React components
│   │   ├── editor/         # Main editor component
│   │   ├── visual-editor/  # Visual editing interface
│   │   └── text-editor/    # HTML text editing interface
│   ├── utils/              # Utility functions
│   │   └── bridge.js       # Native-to-web communication
│   ├── index.jsx           # Local editor entry point
│   └── remote.jsx          # Remote editor entry point
├── ios/                    # iOS Swift package
│   └── Sources/
│       └── GutenbergKit/
├── android/                # Android Kotlin library
│   └── Gutenberg/
├── docs/                   # Documentation
└── patches/                # Third-party package patches
```

## Communication Architecture

### Web → Native Communication

The web editor communicates with native code through platform-specific APIs:

-   **iOS**: `window.webkit.messageHandlers`
-   **Android**: `window.editorDelegate`

Common message types include:

-   Editor initialization
-   Content updates
-   Media uploads
-   Block operations
-   Error reporting

### Native → Web Communication

Native code executes JavaScript in the WebView to:

-   Initialize the editor with content
-   Update editor settings
-   Handle media selection
-   Process API responses

## Development Mode

Development mode (`?dev_mode` query parameter) enables debugging features and bypasses certain production behaviors to simplify development and testing:

-   **Automatic redirects are disabled** - When errors occur, the editor stays on the current page instead of redirecting to fallback pages, allowing developers to debug errors in place
-   **Mock GBKit global is provided** - If the native bridge (`window.GBKit`) is not available, a mock object is automatically provided to allow the editor to load without native integration
-   **Development notice is displayed** - A warning notice appears to inform developers that they're running without a native bridge

Add the `?dev_mode` query parameter to any editor URL:

```
http://localhost:3000/?dev_mode
http://localhost:3000/remote.html?dev_mode
```

## Logging Configuration

The logger utility (`src/utils/logger.js`) supports different log levels that can be controlled via URL parameters independently of dev mode:

-   `?log_level=debug` - Show all logs including verbose debug messages
-   `?log_level=info` - Show info, warnings, and errors (default)
-   `?log_level=warn` - Show only warnings and errors
-   `?log_level=error` - Show only errors

## Editor Variants

By default, GutenbergKit utilizes local `@wordpress` modules. This approach is similar to most modern web applications, where the `@wordpress` modules are bundled with the application.
To enable support for non-core blocks, GutenbergKit can be configured to use remote `@wordpress` modules, where the `@wordpress` modules and plugin-provided editor assets are fetched from a site's remote server. At this time, this functionality is partially implemented and may not work as expected.

The `make build` command builds both the local and remote editors by default. To load the remote editor, you must enable the `plugins` configuration option within the Demo app.

Additionally, a `make dev-server-remote` command is available for serving the latest remote editor changes through a development server. To load the development server in the Demo app, add an environment variable named `GUTENBERG_EDITOR_REMOTE_URL` with the URL of the development server plus `/remote.html`—i.e., `http://<YOUR_LOCAL_IP>:5173/remote.html`.

> [!TIP]
> The remote editor redirects to the local editor when loading fails. If you need to debug the failure, disable redirects via the `?dev_mode` query parameter..

### Local Editor (`index.html`)

The local editor bundles all WordPress packages and runs entirely within the WebView. This variant:

-   Provides offline capability
-   Has faster initial load times
-   Limited to core blocks only
-   No plugin support

**Entry point:** `src/index.jsx`

### Remote Editor (`remote.html`)

The remote editor loads WordPress packages and plugins from a remote server. This variant:

-   Supports custom blocks and plugins
-   Requires network connectivity
-   Used in production environments with custom implementations

**Entry point:** `src/remote.jsx`

## Testing

### JavaScript Testing

-   Framework: Vitest
-   Test files: `*.test.{js,jsx}`
-   Run tests: `npm run test`

### Native Testing

**iOS:**

-   XCTest framework
-   Run: `make test-swift-package`

**Android:**

-   JUnit framework
-   Run: `make test-android`
