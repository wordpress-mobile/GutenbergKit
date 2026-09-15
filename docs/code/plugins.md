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

### One instance per `@wordpress` package

Plugin scripts reach the bundled packages through `window.wp`, populated by `src/utils/wordpress-globals.js`, in the same way WP Admin exposes them. Every exposed package is declared as a direct dependency so the version is explicit, linted, and tracked by Dependabot.

Each package must have a single install in the dependency graph. A second copy nested under another dependency brings its own React contexts, data stores, and private APIs, so plugins would receive a different instance than the editor's own components use, with no error to signal the split. Two safeguards keep this from happening:

-   Dependabot groups `@wordpress/*` updates so they move together, as a Gutenberg release does.
-   `make check-wp-packages` reads `package-lock.json` and fails when any `@wordpress` package is installed more than once, and runs in CI.

Duplicates the project has accepted for the time being are listed in the check's `KNOWN_DUPLICATES` and reported as warnings, so the invariant is enforced going forward rather than satisfied today. `@wordpress/icons` is currently allowed, pending a coordinated bump of the `@wordpress` packages.

## Configuration

Enable plugins by setting the `plugins` configuration option. The editor will fetch assets from the configured `editorAssetsEndpoint` or fall back to the default Jetpack endpoint. The demo app UI allows adding site-specific editor configurations, which enables the `plugins` configuration option.
