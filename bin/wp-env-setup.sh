#!/usr/bin/env bash
#
# wp-env-setup.sh — Auto-provision credentials for the local WordPress environment.
#
# Creates an application password for the admin user and writes the credentials
# to .wp-env.credentials.json so the demo apps can connect automatically.
#
# This script uses only REST API calls (no WP-CLI / wp-env run), so it works
# with both the Docker and Playground runtimes.
#
# Existing credentials are reused only when they still authenticate. The
# Playground runtime has no persistent database, so every restart rebuilds
# WordPress from the Blueprint and discards the application password. The
# credentials file is the one artifact that survives that, which makes its
# presence on disk no evidence that it still works.
#
# Usage:
#   bash bin/wp-env-setup.sh   # Reuse working credentials, otherwise recreate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$PROJECT_ROOT/.wp-env.credentials.json"

# Resolve the port from wp-env so a "port" key in .wp-env.json or WP_ENV_PORT is
# honoured here too, rather than provisioning against a site that moved.
PORT=$(cd "$PROJECT_ROOT" && node -e "
    const { loadConfig } = require( '@wordpress/env/lib/config' );
    loadConfig( process.cwd() )
        .then( ( config ) => process.stdout.write( String( config.env.development.port ) ) )
        .catch( () => process.exit( 1 ) );
") || PORT=""

SITE_URL="http://localhost:${PORT:-${WP_ENV_PORT:-8888}}"
USERNAME="admin"
PASSWORD="password"
APP_NAME="GutenbergKit"

# ---------------------------------------------------------------------------
# Reuse existing credentials only if they still authenticate
#
# Anything other than a clean 200 falls through to provisioning: regenerating
# unnecessarily costs a few seconds, whereas keeping credentials that no longer
# work leaves the demo apps unable to connect.
# ---------------------------------------------------------------------------

if [ -f "$CREDENTIALS_FILE" ]; then
    EXISTING_AUTH=$(node -e "
        const fs = require('fs');
        try {
            const c = JSON.parse(fs.readFileSync('$CREDENTIALS_FILE', 'utf8'));
            if (!c.authHeader) process.exit(1);
            process.stdout.write(c.authHeader);
        } catch {
            process.exit(1);
        }
    ") || EXISTING_AUTH=""

    if [ -n "$EXISTING_AUTH" ]; then
        PROBE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
            -H "Authorization: $EXISTING_AUTH" \
            "$SITE_URL/?rest_route=/wp/v2/users/me" 2>/dev/null) || PROBE_STATUS=""

        if [ "$PROBE_STATUS" = "200" ]; then
            echo "Existing credentials are valid — skipping setup."
            exit 0
        fi
    fi

    echo "Existing credentials are no longer valid — regenerating..."
    rm -f "$CREDENTIALS_FILE"
fi

# ---------------------------------------------------------------------------
# Wait for WordPress to be ready
# ---------------------------------------------------------------------------

echo "Waiting for WordPress to be ready..."

MAX_RETRIES=30
RETRY_INTERVAL=2

for i in $(seq 1 $MAX_RETRIES); do
    # Use ?rest_route=/ because pretty permalinks may not be active yet.
    if curl -s -o /dev/null -w "%{http_code}" "$SITE_URL/?rest_route=/" | grep -q "200"; then
        echo "WordPress is ready."
        break
    fi

    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Error: WordPress did not become ready after $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
        exit 1
    fi

    sleep $RETRY_INTERVAL
done

# ---------------------------------------------------------------------------
# Create application password via REST API
#
# Uses cookie-based authentication:
# 1. Log in via wp-login.php to obtain a session cookie.
# 2. Fetch a REST nonce from admin-ajax.php.
# 3. POST to the application-passwords endpoint with the cookie + nonce.
#
# The Playground runtime may still be processing Blueprint steps (installing
# plugins, rewriting wp-config.php) when the server starts accepting requests.
# This means application passwords may not be available yet. We retry the
# entire flow until it succeeds or we exceed the retry limit.
# ---------------------------------------------------------------------------

echo "Creating application password for '$USERNAME'..."

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

APP_PASSWORD=""
CREATE_MAX_RETRIES=15
CREATE_RETRY_INTERVAL=2

for attempt in $(seq 1 $CREATE_MAX_RETRIES); do
    # Reset cookie jar for each attempt.
    # WordPress requires the test cookie to be present in the login request.
    printf "localhost\tFALSE\t/\tFALSE\t0\twordpress_test_cookie\tWP%%20Cookie%%20check\n" > "$COOKIE_JAR"

    # Step 1: Log in to get a session cookie.
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        -d "log=$USERNAME&pwd=$PASSWORD&wp-submit=Log+In&redirect_to=%2Fwp-admin%2F&testcookie=1" \
        "$SITE_URL/wp-login.php")

    if [ "$HTTP_STATUS" != "302" ]; then
        echo "  Attempt $attempt/$CREATE_MAX_RETRIES: Login returned HTTP $HTTP_STATUS (expected 302), retrying..."
        sleep $CREATE_RETRY_INTERVAL
        continue
    fi

    # Step 2: Fetch a REST nonce.
    REST_NONCE=$(curl -s -b "$COOKIE_JAR" "$SITE_URL/wp-admin/admin-ajax.php?action=rest-nonce")

    if [ -z "$REST_NONCE" ] || [ "$REST_NONCE" = "0" ]; then
        echo "  Attempt $attempt/$CREATE_MAX_RETRIES: Failed to obtain REST nonce, retrying..."
        sleep $CREATE_RETRY_INTERVAL
        continue
    fi

    # Step 3: Create the application password.
    # Use ?rest_route= format so this works regardless of permalink structure.
    RESPONSE=$(curl -s \
        -b "$COOKIE_JAR" \
        -H "X-WP-Nonce: $REST_NONCE" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$APP_NAME\"}" \
        "$SITE_URL/?rest_route=/wp/v2/users/me/application-passwords")

    # Extract the password from the JSON response.
    # The password field is only returned at creation time.
    # Use Node.js for JSON parsing since it's guaranteed to be available (wp-env requires it).
    APP_PASSWORD=$(echo "$RESPONSE" | node -e "
        let data = '';
        process.stdin.on('data', chunk => data += chunk);
        process.stdin.on('end', () => {
            try { process.stdout.write(JSON.parse(data).password); }
            catch { process.exit(1); }
        });
    ") || true

    if [ -n "$APP_PASSWORD" ]; then
        break
    fi

    echo "  Attempt $attempt/$CREATE_MAX_RETRIES: Application password not available yet, retrying..."
    sleep $CREATE_RETRY_INTERVAL
done

if [ -z "$APP_PASSWORD" ]; then
    echo "Error: Failed to create application password after $CREATE_MAX_RETRIES attempts."
    echo "Last response: $RESPONSE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Build auth header
# ---------------------------------------------------------------------------

AUTH_HEADER="Basic $(echo -n "$USERNAME:$APP_PASSWORD" | base64)"

# ---------------------------------------------------------------------------
# Write credentials file
# ---------------------------------------------------------------------------

cat > "$CREDENTIALS_FILE" <<EOF
{
  "siteUrl": "$SITE_URL",
  "siteApiRoot": "${SITE_URL}/wp-json/",
  "username": "$USERNAME",
  "appPassword": "$APP_PASSWORD",
  "authHeader": "$AUTH_HEADER"
}
EOF

echo "Credentials written to $CREDENTIALS_FILE"

# ---------------------------------------------------------------------------
# Wait until WordPress is fully provisioned
#
# The Playground runtime keeps installing plugins (Blueprint steps) after it
# starts accepting requests. During those installs WordPress drops a
# `.maintenance` file and serves a 503, and there is a brief race where the
# file is removed mid-request and PHP fatals. Both corrupt the first editor
# REST call, so we gate here until the settings endpoint returns valid JSON.
# ---------------------------------------------------------------------------

echo "Waiting for the editor settings endpoint to be ready..."

SETTINGS_URL="$SITE_URL/?rest_route=/wp-block-editor/v1/settings"
READY_MAX_RETRIES=45
READY_RETRY_INTERVAL=2

for attempt in $(seq 1 $READY_MAX_RETRIES); do
    if curl -s -H "Authorization: $AUTH_HEADER" "$SETTINGS_URL" | node -e "
        let data = '';
        process.stdin.on('data', chunk => data += chunk);
        process.stdin.on('end', () => {
            try { JSON.parse(data); }
            catch { process.exit(1); }
        });
    "; then
        echo "Editor settings endpoint is ready."
        break
    fi

    if [ "$attempt" -eq "$READY_MAX_RETRIES" ]; then
        echo "Error: editor settings endpoint did not return valid JSON after $((READY_MAX_RETRIES * READY_RETRY_INTERVAL)) seconds."
        exit 1
    fi

    sleep $READY_RETRY_INTERVAL
done
