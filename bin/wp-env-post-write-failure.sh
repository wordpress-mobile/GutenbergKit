#!/usr/bin/env bash
#
# wp-env-post-write-failure.sh — Read or set the post write failure simulation mode.
#
# Drives the `gutenbergkit-post-write-failure` mu-plugin, which fails, delays
# or cuts off REST writes to posts so the editor's save outcome handling can be
# exercised locally (spike S4, CMM-2559).
#
# Usage:
#   bash bin/wp-env-post-write-failure.sh                  # Report the current mode
#   MODE=error500 bash bin/wp-env-post-write-failure.sh    # 500 before writing
#   MODE=slow90s  bash bin/wp-env-post-write-failure.sh    # Write after 90 seconds
#   MODE=drop     bash bin/wp-env-post-write-failure.sh    # Write, then cut the response
#   MODE=conflict POST=12 bash bin/wp-env-post-write-failure.sh  # Bump post 12's modified date and content
#   MODE=conflict POST=12 CONTENT=0 bash ...               # Bump only the modified date
#   MODE=off      bash bin/wp-env-post-write-failure.sh    # Normal writes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_FILE="$PROJECT_ROOT/.wp-env.credentials.json"

# Addressed to localhost rather than the credentials file's siteUrl: after
# `make wp-env-android` that URL points at 10.0.2.2, which only resolves inside
# the emulator. The server is always reachable on localhost from the host.
ENDPOINT="http://localhost:${WP_ENV_PORT:-8888}/wp-json/gutenbergkit/v1/post-write-failure"

VALID_MODES="off error500 slow90s drop conflict"
MODE="${MODE:-}"
POST="${POST:-}"
CONTENT="${CONTENT:-1}"

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

# The path arrives as an argument rather than interpolated into the source: a
# checkout under a path containing a quote or backslash would otherwise produce
# a syntax error instead of the failure message below.
AUTH_HEADER=$(node -e '
    const fs = require("fs");
    try {
        const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        if (!c.authHeader) process.exit(1);
        process.stdout.write(c.authHeader);
    } catch {
        process.exit(1);
    }
' "$CREDENTIALS_FILE") || {
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
    if [ "$MODE" = "conflict" ] && [ -n "$POST" ]; then
        URL="$URL&post=$POST&content=$([ "$CONTENT" = "0" ] && echo false || echo true)"
    fi
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
        echo "Error: the post-write-failure endpoint is not registered (HTTP 404)." >&2
        echo 'Check that wp-env/mu-plugins/gutenbergkit-post-write-failure.php exists,' >&2
        echo 'then restart with "make wp-env-start".' >&2
        exit 1
        ;;
    *)
        echo "Error: unexpected response (HTTP $STATUS) from $ENDPOINT" >&2
        echo "$BODY" >&2
        exit 1
        ;;
esac

echo "$BODY" | node -e "
    let input = '';
    process.stdin.on('data', (chunk) => { input += chunk; });
    process.stdin.on('end', () => {
        let body = {};
        try { body = JSON.parse(input); } catch {}
        const verb = process.argv[1] ? 'set to' : 'is';
        console.log('Post write failure mode ' + verb + ': ' + (body.mode ?? 'unknown'));
        const notes = {
            error500: 'Post writes fail with a 500 before anything is written.',
            slow90s: 'Post writes wait 90 seconds, then apply and answer normally.',
            drop: 'Post writes apply, then the response is cut off mid-body.',
            conflict: 'Post writes pass through; set with POST=<id> to simulate another writer.',
        };
        if (notes[body.mode]) console.log(notes[body.mode]);
        if (body.concurrentEdit) console.log('Concurrent edit: ' + JSON.stringify(body.concurrentEdit));
    });
" "$MODE"
