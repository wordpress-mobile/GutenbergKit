# Local WordPress Environment (wp-env)

GutenbergKit includes a local WordPress environment powered by [`@wordpress/env`](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/) (wp-env). This gives developers a zero-config way to run the full editor experience locally, including theme styles, media uploads, and plugin block assets.

## Prerequisites

-   [Docker Desktop](https://www.docker.com/products/docker-desktop/) must be installed and running.
-   Node.js and npm (already required for GutenbergKit development).

## Quick Start

```bash
# Start the local WordPress environment
make wp-env-start
```

This command:

1. Installs npm dependencies (if needed).
2. Starts Docker containers running WordPress at **http://localhost:8888**.
3. Creates an application password for the `admin` user.
4. Writes credentials to `.wp-env.credentials.json` (gitignored).

Once started, the **"Local WordPress"** option in both the iOS and Android demo apps will automatically connect to the local environment.

## Available Commands

| Command                     | Description                                                    |
| --------------------------- | -------------------------------------------------------------- |
| `make wp-env-start`         | Start the environment and provision credentials                |
| `make wp-env-stop`          | Stop the environment (preserves data)                          |
| `make wp-env-clean`         | Destroy the environment and remove all data                    |
| `make wp-env-logs`          | View WordPress debug logs                                      |
| `make wp-env-cli CMD="..."` | Run a WP-CLI command (e.g., `make wp-env-cli CMD="post list"`) |

## How It Works

### wp-env Configuration

The `.wp-env.json` file at the project root configures the environment:

-   **Gutenberg plugin** is installed for `/wpcom/v2/editor-assets` and `/wp-block-editor/v1/settings` endpoints.
-   A **CORS mu-plugin** (`wp-env/mu-plugins/gutenbergkit-cors.php`) adds CORS headers to REST API responses, allowing requests from the Vite dev server, preview server, and native WebViews.
-   **WP_DEBUG** and **WP_DEBUG_LOG** are enabled for development.

### Credential Provisioning

The `bin/wp-env-setup.sh` script runs automatically after `wp-env start`:

1. Waits for WordPress to be ready (health check with retries).
2. Creates an application password for the `admin` user via WP-CLI.
3. Generates a Base64-encoded Basic Auth header.
4. Writes credentials to `.wp-env.credentials.json`.

The script is idempotent — it skips if the credentials file already exists. Use `make wp-env-start RESET=1` (or `make wp-env-clean`) to regenerate.

### Demo App Integration

Both demo apps include a **"Local WordPress"** option that is always visible. When tapped:

-   The app reads credentials from `.wp-env.credentials.json`.
-   If found, it connects to the local WordPress site using the same flow as any configured editor.
-   If the file is missing (wp-env not running), it shows an error with instructions to run `make wp-env-start`.

## Platform Notes

### iOS Simulator

The iOS Simulator shares the host machine's network stack. Requests to `localhost:8888` work directly.

The Xcode scheme includes a `WP_ENV_CREDENTIALS_PATH` environment variable pointing to the credentials file.

### Android Emulator

The Android emulator cannot reach `localhost` on the host machine directly. The credentials loader automatically remaps `localhost` to `10.0.2.2` (the emulator's alias for the host). Credentials are read at build time and baked into `BuildConfig` fields, since the emulator cannot access the host filesystem at runtime.

#### Image URLs in the Android Emulator

WordPress generates image URLs (e.g., for uploaded media) using its configured site URL, which defaults to `http://localhost:8888`. These URLs don't resolve inside the Android emulator because `localhost` points to the emulator itself.

To fix this, update WordPress's site URL constants to use `10.0.2.2` before testing media uploads:

```bash
make wp-env-cli CMD="config set WP_SITEURL http://10.0.2.2:8888"
make wp-env-cli CMD="config set WP_HOME http://10.0.2.2:8888"
```

To revert (for browser access or iOS testing):

```bash
make wp-env-cli CMD="config set WP_SITEURL http://localhost:8888"
make wp-env-cli CMD="config set WP_HOME http://localhost:8888"
```

Note: wp-env defines `WP_SITEURL` and `WP_HOME` as constants in `wp-config.php`, so `wp option update` will not work — use `wp config set` instead. Changing the site URL to `10.0.2.2` will cause the WordPress admin dashboard (`http://localhost:8888/wp-admin/`) to redirect to `10.0.2.2`, which doesn't resolve in a desktop browser.

### Physical Devices

Physical devices cannot reach `localhost`. You'll need to:

1. Find your machine's local IP address (e.g., `192.168.1.100`).
2. Update the CORS mu-plugin to allow your IP.
3. Manually create or edit `.wp-env.credentials.json` with the correct IP-based URLs.

## WordPress Admin

Access the WordPress admin dashboard at **http://localhost:8888/wp-admin/**:

-   **Username:** `admin`
-   **Password:** `password`

## Troubleshooting

### Docker is not running

```
Error: Cannot connect to the Docker daemon
```

Make sure Docker Desktop is running before executing `make wp-env-start`.

### Port 8888 is already in use

```
Error: Port 8888 is already allocated
```

Another service is using port 8888. Stop the conflicting service or change the wp-env port in `.wp-env.json`:

```json
{
	"port": 9999
}
```

### Resetting the environment

To start fresh, destroy the environment and recreate it:

```bash
make wp-env-clean
make wp-env-start
```

### Credentials file not found

If the demo apps show "Local WordPress not available", verify:

1. wp-env is running: `make wp-env-logs`
2. The credentials file exists: `cat .wp-env.credentials.json`
3. For Android, rebuild the app after `make wp-env-start` so credentials are baked into `BuildConfig`.
