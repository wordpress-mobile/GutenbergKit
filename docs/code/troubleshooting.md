# Troubleshooting

This guide covers common issues and solutions when developing GutenbergKit.

## GBKit global not available after timeout

**Error:** `GBKit global not available after timeout`

This error occurs when the editor is unable to communicate with the native bridge. This is expected when opening the editor in a browser, as the native bridge is not available. GutenbergKit is designed to be used in a native host app that provides the native bridge. The GutenbergKit project includes a demo app that can be used to test the editor.

**Solution:** Add the `?dev_mode` query parameter to the editor URL in your browser. This will bypass the native bridge requirement and allow the editor to load without the native bridge. However, some features may not work as expected when using this mode.

## Importing a module script failed

**Error:** `Importing a module script failed.`

This [generally indicates](https://github.com/vitejs/vite/discussions/17738) that Vite is attempting to load a cached dependency that no longer exists or is corrupted.

Often times this is paired with a following warning in the Vite development server console that looks like this:

```
The file does not exist at "[path]" which is in the optimize deps directory. The dependency might be incompatible with the dep optimizer. Try adding it to `optimizeDeps.exclude`.
```

**Solution:** Clear Vite's cache by either:

-   Stopping the development server and restarting it via the `make dev-server-force` command to force Vite to re-bundle dependencies.
-   Deleting the `node_modules/.vite` directory (or `node_modules` entirely) and restarting the development server via `make dev-server`.

You may also need to clear your browser cache to ensure no stale files are used.

## AJAX requests fail with CORS errors

**Error:** `Access to XMLHttpRequest at 'https://example.com/wp-admin/admin-ajax.php' from origin 'http://localhost:5173' has been blocked by CORS policy`

This error occurs when the editor makes AJAX requests (e.g., from blocks that use `admin-ajax.php`) while running on the development server. The browser blocks these cross-origin requests because the editor runs on `localhost` while AJAX targets your WordPress site.

**Solution:** AJAX functionality requires a production bundle. Build the editor assets with `make build` and test AJAX features using the demo apps without using the `GUTENBERG_EDITOR_URL` environment variable.

For Android, you must also configure `assetLoaderDomain` to a domain allowed by your WordPress site's CORS policy. See the [AJAX Support section](../integration.md#ajax-support) in the Integration Guide for complete configuration details.
