# Local WordPress Environment (wp-env)

GutenbergKit includes a local WordPress environment powered by [`@wordpress/env`](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/) (wp-env). This gives developers a zero-config way to run the full editor experience locally, including theme styles, media uploads, and plugin block assets.

The environment uses the [WordPress Playground](https://wordpress.github.io/wordpress-playground/) runtime, which runs WordPress entirely in WebAssembly — no Docker required.

## Prerequisites

-   Node.js and npm (already required for GutenbergKit development).

## Quick Start

```bash
# Start the local WordPress environment
make wp-env-start
```

This command:

1. Installs npm dependencies (if needed).
2. Starts a WordPress Playground instance (port auto-selected, defaulting to 8888).
3. Creates an application password for the `admin` user.
4. Writes credentials to `.wp-env.credentials.json` (gitignored).

Once started, the **"Local WordPress"** option in both the iOS and Android demo apps will automatically connect to the local environment.

## Available Commands

| Command                     | Description                                             |
| --------------------------- | ------------------------------------------------------- |
| `make wp-env-start`         | Start the environment and provision credentials         |
| `make wp-env-stop`          | Stop the environment (preserves data)                   |
| `make wp-env-clean`         | Destroy the environment and remove all data             |
| `make wp-env-android`       | Restart with site URL remapped for the Android emulator |
| `make wp-env-android-reset` | Restart with the default localhost site URL             |

## How It Works

### wp-env Configuration

The `.wp-env.json` file at the project root configures the environment:

-   **Gutenberg plugin** is installed for the `/wp-block-editor/v1/settings` editor settings REST API endpoint.
-   **Jetpack plugin** is installed with the blocks module auto-activated via a mu-plugin (`wp-env/mu-plugins/gutenbergkit-jetpack-blocks.php`), providing the `/wpcom/v2/editor-assets` endpoint and additional editor blocks.
-   A **CORS mu-plugin** (`wp-env/mu-plugins/gutenbergkit-cors.php`) adds CORS headers to REST API responses, allowing requests from the Vite dev server, preview server, and native WebViews.
-   **WP_DEBUG** and **WP_DEBUG_LOG** are enabled for development.

### Credential Provisioning

The `bin/wp-env-setup.sh` script handles the full startup flow:

1. Checks if wp-env is already running — skips `wp-env start` if so (prevents duplicate instances).
2. Starts the WordPress Playground environment if not already running.
3. Waits for WordPress to be ready (health check with retries).
4. Creates an application password for the `admin` user via the REST API.
5. Generates a Base64-encoded Basic Auth header.
6. Writes credentials to `.wp-env.credentials.json`.

The script is idempotent — it skips starting a second instance if one is already running, and skips credential provisioning if the credentials file already exists. Use `make wp-env-start RESET=1` (or `make wp-env-clean`) to regenerate credentials.

### Demo App Integration

Both demo apps include a **"Local WordPress"** option that is always visible. When tapped:

-   The app reads credentials from `.wp-env.credentials.json`.
-   If found, it connects to the local WordPress site using the same flow as any configured editor.
-   If the file is missing (wp-env not running), it shows an error with instructions to run `make wp-env-start`.

## Platform Notes

### iOS Simulator

The iOS Simulator shares the host machine's network stack. Requests to `localhost` work directly.

The Xcode scheme includes a `WP_ENV_CREDENTIALS_PATH` environment variable pointing to the credentials file.

### Android Emulator

The Android emulator cannot reach `localhost` on the host machine directly. The credentials loader automatically remaps `localhost` to `10.0.2.2` (the emulator's alias for the host). Credentials are read at build time and baked into `BuildConfig` fields, since the emulator cannot access the host filesystem at runtime.

#### Image URLs in the Android Emulator

WordPress generates image URLs (e.g., for uploaded media) using its configured site URL. These URLs don't resolve inside the Android emulator because `localhost` points to the emulator itself.

To fix this, activate a mu-plugin that remaps URLs and restart wp-env:

```bash
make wp-env-android
```

This installs a mu-plugin (`gutenbergkit-android-urls.php`) that rewrites `localhost` and `127.0.0.1` to `10.0.2.2` in WordPress's site URL output, then restarts wp-env and regenerates credentials. After restarting, rebuild the Android app so the new credentials are baked into `BuildConfig`.

To revert (for browser access or iOS testing):

```bash
make wp-env-android-reset
```

Note: While the URL override is active, the WordPress admin dashboard will redirect to `10.0.2.2`, which doesn't resolve in a desktop browser.

### Physical Devices

Physical devices cannot reach `localhost`. You'll need to:

1. Find your machine's local IP address (e.g., `192.168.1.100`).
2. Update the CORS mu-plugin to allow your IP.
3. Manually create or edit `.wp-env.credentials.json` with the correct IP-based URLs.

## WordPress Admin

Access the WordPress admin dashboard at the URL shown in the `make wp-env-start` output, e.g. **http://localhost:8888/wp-admin/**:

-   **Username:** `admin`
-   **Password:** `password`

## Troubleshooting

### Resetting the environment

To start fresh, destroy the environment and recreate it:

```bash
make wp-env-clean
make wp-env-start
```

### Credentials file not found

If the demo apps show "Local WordPress not available", verify:

1. wp-env is running (`make wp-env-start`).
2. The credentials file exists: `cat .wp-env.credentials.json`
3. For Android, rebuild the app after `make wp-env-start` so credentials are baked into `BuildConfig`.
