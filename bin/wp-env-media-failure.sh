#!/usr/bin/env bash
#
# wp-env-media-failure.sh — Read or set the media upload failure simulation mode.
#
# Drives the `gutenbergkit-media-failure` mu-plugin, which fatals during image
# sub-size generation so the editor's post-process retry can be exercised
# locally. See docs/code/local-wordpress.md.
#
# Usage:
#   bash bin/wp-env-media-failure.sh                # Report the current mode
#   MODE=recover bash bin/wp-env-media-failure.sh   # Fail once, then succeed
#   MODE=always  bash bin/wp-env-media-failure.sh   # Fail every attempt
#   MODE=off     bash bin/wp-env-media-failure.sh   # Normal uploads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$PROJECT_ROOT/.wp-env.credentials.json"

# Addressed to localhost rather than the credentials file's siteUrl: after
# `make wp-env-android` that URL points at 10.0.2.2, which only resolves inside
# the emulator. The server is always reachable on localhost from the host.
ENDPOINT="http://localhost:8888/wp-json/gutenbergkit/v1/media-failure"

VALID_MODES="off recover always"
MODE="${MODE:-}"

# ---------------------------------------------------------------------------
# Validate the requested mode before touching the network
# ---------------------------------------------------------------------------

if [ -n "$MODE" ]; then
    case " $VALID_MODES " in
        *" $MODE "*) ;;
        *)
            echo "Error: invalid MODE '$MODE'." >&2
            echo "Valid modes: $VALID_MODES" >&2
            exit 1
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "Error: credentials not found at $CREDENTIALS_FILE" >&2
    echo 'Run "make wp-env-start" to provision the local WordPress environment.' >&2
    exit 1
fi

AUTH_HEADER=$(node -e "
    const fs = require('fs');
    try {
        const c = JSON.parse(fs.readFileSync('$CREDENTIALS_FILE', 'utf8'));
        if (!c.authHeader) process.exit(1);
        process.stdout.write(c.authHeader);
    } catch {
        process.exit(1);
    }
") || {
    echo "Error: could not read authHeader from $CREDENTIALS_FILE" >&2
    echo 'The file may be malformed. Run "make wp-env-start RESET=1" to regenerate it.' >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Request
# ---------------------------------------------------------------------------

if [ -n "$MODE" ]; then
    METHOD="POST"
    URL="$ENDPOINT?mode=$MODE"
else
    METHOD="GET"
    URL="$ENDPOINT"
fi

# Separate the body from the status code so each failure can be reported with
# the fix that actually applies to it.
RESPONSE=$(curl -sS -X "$METHOD" -H "Authorization: $AUTH_HEADER" \
    -w $'\n%{http_code}' "$URL" 2>/dev/null) || {
    echo "Error: could not reach wp-env at $ENDPOINT" >&2
    echo 'Run "make wp-env-start" to start the local WordPress environment.' >&2
    exit 1
}

STATUS="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "$STATUS" in
    200) ;;
    401|403)
        echo "Error: credentials were rejected (HTTP $STATUS)." >&2
        echo 'They are likely stale. Run "make wp-env-start RESET=1" to regenerate them.' >&2
        exit 1
        ;;
    404)
        echo "Error: the media-failure endpoint is not registered (HTTP 404)." >&2
        echo 'Check that wp-env/mu-plugins/gutenbergkit-media-failure.php exists,' >&2
        echo 'then restart with "make wp-env-start".' >&2
        exit 1
        ;;
    *)
        echo "Error: unexpected response (HTTP $STATUS) from $ENDPOINT" >&2
        echo "$BODY" >&2
        exit 1
        ;;
esac

CURRENT=$(echo "$BODY" | node -e "
    let input = '';
    process.stdin.on('data', (chunk) => { input += chunk; });
    process.stdin.on('end', () => {
        try {
            process.stdout.write(JSON.parse(input).mode ?? 'unknown');
        } catch {
            process.stdout.write('unknown');
        }
    });
")

if [ -n "$MODE" ]; then
    echo "Media upload failure mode set to: $CURRENT"
else
    echo "Media upload failure mode: $CURRENT"
fi

case "$CURRENT" in
    recover)
        echo "Uploads fail once per attachment, then succeed on the post-process retry."
        ;;
    always)
        echo "Uploads fail every attempt, exhausting all five retries before the orphan is deleted."
        ;;
esac
