#!/usr/bin/env bash
#
# wp-env-setup.sh — Auto-provision credentials for the local WordPress environment.
#
# Creates an application password for the admin user and writes the credentials
# to .wp-env.credentials.json so the demo apps can connect automatically.
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
# Ensure pretty permalinks are active so /wp-json/ works
# ---------------------------------------------------------------------------

echo "Flushing rewrite rules..."
npm run --silent wp-env run cli -- wp rewrite structure '/%postname%/' 2>/dev/null

echo "Writing .htaccess for pretty permalinks..."
WP_CONTAINER=$(docker ps -qf "publish=8888" | head -1)
if [ -z "$WP_CONTAINER" ]; then
    echo "Error: Could not find WordPress container on port 8888."
    echo "Running containers:"
    docker ps --format "{{.ID}} {{.Image}} {{.Ports}} {{.Names}}"
    exit 1
fi
echo "Found WordPress container: $WP_CONTAINER"
docker exec -u 0 "$WP_CONTAINER" sh -c 'cat > /var/www/html/.htaccess << "HTACCESS"
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS
'

# ---------------------------------------------------------------------------
# Enable Jetpack blocks module
# ---------------------------------------------------------------------------

echo "Enabling Jetpack blocks module..."
npm run --silent wp-env run cli -- wp jetpack module activate blocks 2>/dev/null

# ---------------------------------------------------------------------------
# Create application password
# ---------------------------------------------------------------------------

echo "Creating application password for '$USERNAME'..."

APP_PASSWORD=$(npm run --silent wp-env run cli -- wp user application-password create "$USERNAME" "$APP_NAME" --porcelain 2>/dev/null)

if [ -z "$APP_PASSWORD" ]; then
    echo "Error: Failed to create application password."
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
