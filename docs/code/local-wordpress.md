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
2. Starts a WordPress Playground instance at **http://localhost:8888**.
3. Creates an application password for the `admin` user.
4. Writes credentials to `.wp-env.credentials.json` (gitignored).

Once started, the **"Local WordPress"** option in both the iOS and Android demo apps will automatically connect to the local environment.

## Available Commands

| Command                                 | Description                                                   |
| --------------------------------------- | ------------------------------------------------------------- |
| `make wp-env-start`                     | Start the environment and provision credentials               |
| `make wp-env-stop`                      | Stop the environment                                          |
| `make wp-env-clean`                     | Remove downloaded WordPress, plugin, and theme files          |
| `make wp-env-android-urls`              | Report whether WordPress emits emulator-reachable URLs        |
| `make wp-env-android-urls MODE=on\|off` | Emit `10.0.2.2` URLs for the Android emulator, or `localhost` |

The site is rebuilt from scratch on every start, so stopping the environment discards any content you created. Use `make wp-env-clean` when you also want to remove the downloaded WordPress, plugin, and theme files.

## How It Works

### wp-env Configuration

The `.wp-env.json` file at the project root configures the environment:

-   **Gutenberg plugin** is installed for the `/wp-block-editor/v1/settings` editor settings REST API endpoint.
-   **Jetpack plugin** is installed with the blocks module auto-activated via a mu-plugin (`wp-env/mu-plugins/gutenbergkit-jetpack-blocks.php`), providing the `/wpcom/v2/editor-assets` endpoint and additional editor blocks.
-   A **CORS mu-plugin** (`wp-env/mu-plugins/gutenbergkit-cors.php`) adds CORS headers to REST API responses, allowing requests from the Vite dev server, preview server, and native WebViews.
-   **WP_DEBUG** and **WP_DEBUG_LOG** are enabled for development.

### Credential Provisioning

The `bin/wp-env-setup.sh` script runs automatically after `wp-env start`:

1. Waits for WordPress to be ready (health check with retries).
2. Creates an application password for the `admin` user via the REST API.
3. Generates a Base64-encoded Basic Auth header.
4. Writes credentials to `.wp-env.credentials.json`.

The script is idempotent. It reuses existing credentials only when they still authenticate, and regenerates them otherwise — so `make wp-env-start` is safe to run repeatedly.

This matters because the Playground runtime has no persistent database. Every restart rebuilds WordPress from the Blueprint, which recreates the `admin` user and discards the application password. The credentials file survives the restart even though the credentials it holds do not, so the file's presence alone is not evidence that it works.

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

#### Server-Generated URLs in the Android Emulator

The credentials remap above covers the site URL the app connects to. It does not cover the URLs WordPress writes into its responses — uploaded media, block editor assets, theme styles, and REST links — which WordPress generates from its configured site URL of `http://localhost:8888`. The app receives those as content rather than configuration, and they don't resolve inside the emulator because `localhost` points at the emulator itself.

To remap them, enable the URL override:

```bash
make wp-env-android-urls MODE=on
```

This installs a mu-plugin (`gutenbergkit-android-urls.php`) that rewrites `localhost` and `127.0.0.1` to `10.0.2.2` in WordPress's URL output. The mu-plugins directory is mounted into the running server, so the change applies immediately — no restart, and existing credentials keep working.

Rebuild the Android app afterwards. This is needed for the URL change itself, not because credentials rotated: `BuildConfig` is populated at build time.

To revert (for browser access or iOS testing):

```bash
make wp-env-android-urls MODE=off
```

Run it with no `MODE` to report the current setting.

Two things to be aware of while the override is active:

-   The WordPress admin dashboard (`http://localhost:8888/wp-admin/`) redirects to `10.0.2.2`, which doesn't resolve in a desktop browser.
-   The `/wp/v2/settings` endpoint still reports `url` as `localhost`, because that field reads the stored option directly rather than passing through the `site_url` and `home_url` filters. It is not a reliable way to check whether the override is on — use `make wp-env-android-urls` instead.

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

### Port 8888 is already in use

`make wp-env-start` checks the port before starting and reports the process holding it:

```
Error: port 8888 is held by a process this project does not track.

  PID 31041: node .../wp-playground.js server --port 8888 ...
```

It reports the process rather than stopping it. Because each git worktree tracks its own environment while sharing one port, the process may be another worktree's healthy site rather than an orphan — check the command line, then stop it yourself:

```bash
kill <PID>
```

If the port belongs to an unrelated service, change the wp-env port in `.wp-env.json` instead:

```json
{
	"port": 9999
}
```

The make targets read the port from wp-env, so a `port` key here — or the `WP_ENV_PORT` environment variable — applies to the port check and credential provisioning as well as to the server itself.

### Resetting the environment

To start fresh, destroy the environment and recreate it:

```bash
make wp-env-clean
make wp-env-start
```

`make wp-env-clean` also checks the port afterwards. If a server is still holding it — one wp-env lost track of, and so could not stop — it reports the process so the next start does not fail on it.

### Credentials file not found

If the demo apps show "Local WordPress not available", verify:

1. wp-env is running (`make wp-env-start`).
2. The credentials file exists: `cat .wp-env.credentials.json`
3. For Android, rebuild the app after `make wp-env-start` so credentials are baked into `BuildConfig`.
