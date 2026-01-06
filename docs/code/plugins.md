# Plugin Support

GutenbergKit bundles `@wordpress` modules locally for offline capability and fast load times. The editor can optionally load plugin-provided blocks and custom editor assets from a remote server when configured.

## How Plugin Loading Works

When the `plugins` configuration option is enabled:

1. Core `@wordpress` packages are loaded from bundled code
2. Plugin scripts and styles are fetched from the site's editor assets endpoint
3. Custom blocks and editor extensions are registered dynamically
4. The editor integrates both core and custom functionality

This approach provides:

-   **Offline-first**: Core editor works without network connectivity
-   **Extensibility**: Supports custom blocks and plugins when connected
-   **Performance**: Core packages load instantly from local bundle

## Configuration

Enable plugins by setting the `plugins` configuration option. The editor will fetch assets from the configured `editorAssetsEndpoint` or fall back to the default Jetpack endpoint. The demo app UI allows adding site-specific editor configurations, which enables the `plugins` configuration option.
