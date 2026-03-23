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
# Usage:
#   bash bin/wp-env-setup.sh           # Create credentials (skips if file exists)
#   RESET=1 bash bin/wp-env-setup.sh   # Recreate credentials from scratch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$PROJECT_ROOT/.wp-env.credentials.json"

# Discover the actual site URL from wp-env (supports auto-port selection).
SITE_URL=$(npx wp-env status --json 2>/dev/null | node -e "
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => {
        try { process.stdout.write(JSON.parse(data).urls.development); }
        catch { process.exit(1); }
    });
") || true

if [ -z "$SITE_URL" ]; then
    echo "Error: Could not determine site URL from wp-env status."
    exit 1
fi

USERNAME="admin"
PASSWORD="password"
APP_NAME="GutenbergKit"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

RESET="${RESET:-}"

if { [ "$RESET" = "true" ] || [ "$RESET" = "1" ]; } && [ -f "$CREDENTIALS_FILE" ]; then
    echo "Removing existing credentials file..."
    rm -f "$CREDENTIALS_FILE"
fi

if [ -f "$CREDENTIALS_FILE" ]; then
    echo "Credentials file already exists at $CREDENTIALS_FILE — skipping setup."
    echo "Use RESET=1 to regenerate credentials."
    exit 0
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
