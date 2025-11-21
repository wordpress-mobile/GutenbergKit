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
│   └── index.js            # Main editor entry point
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

-   **Development notice is displayed** - A warning notice appears to inform developers that they're running in development mode.
-   **Mock GBKit global is provided** - If the native bridge (`window.GBKit`) is not available, a mock object is automatically provided to allow the editor to load without native integration.
-   **React Dev Tools integration** - The editor connects to the React Dev Tools standalone server for component inspection and debugging. See the React Dev Tools section below for setup instructions.

Add the `?dev_mode` query parameter to the editor URL:

```
http://localhost:3000/?dev_mode
```

### React Dev Tools

The [React Developer Tools](https://react.dev/learn/react-developer-tools) allow inspecting React components, view props and state, and debug the component tree during development. GutenbergKit supports the standalone DevTools server for both browser and native WebView debugging.

1. Start the standalone DevTools server:

    ```bash
    make dev-tools
    ```

    This opens a standalone window that will display your React component tree.

2. Start the development server:

    ```bash
    make dev-server
    ```

3. For Android emulators only, set up port forwarding:

    ```bash
    adb reverse tcp:8097 tcp:8097
    ```

4. Load the editor with development mode enabled:

    Browser or iOS simulator:

    ```
    http://localhost:5173/?dev_mode
    ```

    Android emulator:

    ```
    http://10.0.2.2:5173/?dev_mode
    ```

    The editor will automatically connect to the DevTools server, and your component tree will appear in the standalone window.

## Logging Configuration

The logger utility (`src/utils/logger.js`) supports different log levels that can be controlled via URL parameters independently of dev mode:

-   `?log_level=debug` - Show all logs including verbose debug messages
-   `?log_level=info` - Show info, warnings, and errors (default)
-   `?log_level=warn` - Show only warnings and errors
-   `?log_level=error` - Show only errors

## Plugin Support

GutenbergKit bundles `@wordpress` modules locally for offline capability and fast load times. The editor can optionally load plugin-provided blocks and custom editor assets from a remote server when configured.

### How Plugin Loading Works

When the `plugins` configuration option is enabled:

1. Core `@wordpress` packages are loaded from bundled code
2. Plugin scripts and styles are fetched from the site's editor assets endpoint
3. Custom blocks and editor extensions are registered dynamically
4. The editor integrates both core and custom functionality

This approach provides:

-   **Offline-first**: Core editor works without network connectivity
-   **Extensibility**: Supports custom blocks and plugins when connected
-   **Performance**: Core packages load instantly from local bundle

### Configuration

Enable plugins by setting the `plugins` configuration option. The editor will fetch assets from the configured `editorAssetsEndpoint` or fall back to the default Jetpack endpoint. The demo app UI allows adding site-specific editor configurations, which enables the `plugins` configuration option.

## Testing

### JavaScript Testing

-   Framework: Vitest
-   Test files: `*.test.{js,jsx}`
-   Run tests: `make test-js`

### Native Testing

**iOS:**

-   XCTest framework
-   Run: `make test-swift-package`

**Android:**

-   JUnit framework
-   Run: `make test-android`

## Frequently Asked Questions

### Why do I encounter a `GBKit global not available after timeout` error when opening the GutenbergKit editor in a browser?

This error occurs when the editor is unable to communicate with the native bridge. This is expected when opening the editor in a browser, as the native bridge is not available. GutenbergKit is designed to be used in a native host app that provides the native bridge. The GutenbergKit project includes a demo app that can be used to test the editor.

It is possible to circumvent this this error by adding the `?dev_mode` query parameter to the editor URL in your browser. This will bypass the native bridge requirement and allow the editor to load without the native bridge. However, some features may not work as expected when using this mode.
