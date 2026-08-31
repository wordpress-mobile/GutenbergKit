#!/usr/bin/env bash
#
# wp-env-android.sh — Read or set the Android emulator URL remap.
#
# Drives the `gutenbergkit-android-urls` mu-plugin, which rewrites localhost
# and 127.0.0.1 to 10.0.2.2 in WordPress's URL output so media, block assets,
# and REST links resolve inside the Android emulator.
#
# This is separate from the credentials remap in LocalWordPressCredentials.kt,
# which rewrites the site URL the app connects to and applies automatically.
# This plugin covers the URLs WordPress emits in response bodies, which the app
# receives as content rather than configuration.
#
# The mu-plugins directory is mounted into the running server, so toggling
# takes effect without restarting. That also means this is a plain file
# operation which works whether or not the environment is running.
#
# Usage:
#   bash bin/wp-env-android.sh           # Report the current mode
#   MODE=on  bash bin/wp-env-android.sh  # Emit 10.0.2.2 URLs
#   MODE=off bash bin/wp-env-android.sh  # Emit localhost URLs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_PLUGIN="$PROJECT_ROOT/wp-env/android-url-override.php"
ACTIVE_PLUGIN="$PROJECT_ROOT/wp-env/mu-plugins/gutenbergkit-android-urls.php"

VALID_MODES="on off"
MODE="${MODE:-}"

# ---------------------------------------------------------------------------
# Validate the requested mode before touching the filesystem
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
# Apply
# ---------------------------------------------------------------------------

if [ "$MODE" = "on" ]; then
    if [ ! -f "$SOURCE_PLUGIN" ]; then
        echo "Error: $SOURCE_PLUGIN not found." >&2
        exit 1
    fi

    cp "$SOURCE_PLUGIN" "$ACTIVE_PLUGIN"
elif [ "$MODE" = "off" ]; then
    rm -f "$ACTIVE_PLUGIN"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if [ -f "$ACTIVE_PLUGIN" ]; then
    CURRENT="on"
else
    CURRENT="off"
fi

echo "Android emulator URLs: $CURRENT"

if [ "$CURRENT" = "on" ]; then
    echo "WordPress emits 10.0.2.2 instead of localhost for media, block assets,"
    echo "and REST links."
else
    echo "WordPress emits localhost URLs, reachable from a browser and the iOS"
    echo "Simulator."
fi

if [ -n "$MODE" ]; then
    echo "Rebuild the Android app to pick up the change."
else
    if [ "$CURRENT" = "on" ]; then
        OTHER="off"
    else
        OTHER="on"
    fi

    echo
    echo "To change it: make wp-env-android-urls MODE=$OTHER"
fi
