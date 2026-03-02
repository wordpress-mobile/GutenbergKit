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

SITE_URL="http://localhost:8888"
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
# ---------------------------------------------------------------------------

echo "Creating application password for '$USERNAME'..."

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

# Step 1: Log in to get a session cookie.
# WordPress requires the test cookie to be present in the login request.
# Seed the cookie jar with it, then POST the credentials.
printf "localhost\tFALSE\t/\tFALSE\t0\twordpress_test_cookie\tWP%%20Cookie%%20check\n" > "$COOKIE_JAR"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -d "log=$USERNAME&pwd=$PASSWORD&wp-submit=Log+In&redirect_to=%2Fwp-admin%2F&testcookie=1" \
    "$SITE_URL/wp-login.php")

if [ "$HTTP_STATUS" != "302" ]; then
    echo "Error: WordPress login failed (HTTP $HTTP_STATUS)."
    exit 1
fi

# Step 2: Fetch a REST nonce.
REST_NONCE=$(curl -s -b "$COOKIE_JAR" "$SITE_URL/wp-admin/admin-ajax.php?action=rest-nonce")

if [ -z "$REST_NONCE" ] || [ "$REST_NONCE" = "0" ]; then
    echo "Error: Failed to obtain REST nonce."
    exit 1
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
APP_PASSWORD=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])" 2>/dev/null)

if [ -z "$APP_PASSWORD" ]; then
    echo "Error: Failed to create application password."
    echo "Response: $RESPONSE"
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
