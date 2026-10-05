#!/usr/bin/env bash
#
# wp-env-guard.sh — Preflight check before starting the local WordPress environment.
#
# Starting a second Playground server while one already holds the port fails
# with EADDRINUSE, and wp-env deletes the PID file as it unwinds the failed
# start — including when that file names the healthy server that was already
# running. `wp-env stop` and `wp-env status` both trust the PID file alone, so
# afterwards they report success and "stopped" while the server keeps serving.
#
# Guarding before the start avoids creating that state rather than cleaning up
# after it.
#
# This script only reports. Each git worktree gets its own work directory, and
# so its own PID file, while contending for the same port, so a process holding
# it may be another worktree's healthy environment rather than an orphan.
# Telling them apart needs a person, and stopping the wrong one interrupts work
# elsewhere, so the decision and the command are left to the caller.
#
# Usage:
#   bash bin/wp-env-guard.sh   # Exits non-zero if the start should not proceed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Resolve the port and work directory
#
# Ask wp-env rather than deriving these here. The work directory honours
# WP_ENV_HOME and moves to ~/wp-env on snap systems, and the port comes from
# WP_ENV_PORT or the config's own "port" key. Recomputing either by hand would
# disagree with wp-env as soon as any of those is set, leaving the guard unable
# to recognise our own server.
# ---------------------------------------------------------------------------

CONFIG=$(cd "$PROJECT_ROOT" && node -e "
    const { loadConfig } = require( '@wordpress/env/lib/config' );
    loadConfig( process.cwd() )
        .then( ( config ) => {
            process.stdout.write(
                [ config.env.development.port, config.workDirectoryPath ].join( '\n' )
            );
        } )
        .catch( () => process.exit( 1 ) );
") || CONFIG=""

PORT=$(printf '%s\n' "$CONFIG" | sed -n '1p')
WORK_DIR=$(printf '%s\n' "$CONFIG" | sed -n '2p')

# Degrade to a plain port check rather than skipping the guard entirely when
# the config cannot be read.
PORT="${PORT:-${WP_ENV_PORT:-8888}}"

# ---------------------------------------------------------------------------
# Is anything holding the port?
# ---------------------------------------------------------------------------

PORT_PIDS=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | sort -u) || PORT_PIDS=""

if [ -z "$PORT_PIDS" ]; then
    exit 0
fi

# A server may listen on both IPv4 and IPv6, and the PID file names only one
# process. Treat the set as ours only when every listener is accounted for.
PORT_PID_COUNT=$(printf '%s\n' "$PORT_PIDS" | grep -c .)
PORT_PID=$(printf '%s\n' "$PORT_PIDS" | sed -n '1p')

# ---------------------------------------------------------------------------
# Does it belong to this project's environment?
# ---------------------------------------------------------------------------

TRACKED_PID=""

if [ -n "$WORK_DIR" ] && [ -f "$WORK_DIR/playground.pid" ]; then
    TRACKED_PID=$(tr -d '[:space:]' < "$WORK_DIR/playground.pid" 2>/dev/null) || TRACKED_PID=""
fi

if [ -n "$TRACKED_PID" ] && [ "$TRACKED_PID" = "$PORT_PID" ] && [ "$PORT_PID_COUNT" -eq 1 ]; then
    echo "The local WordPress environment is already running on port $PORT."
    echo "Skipping start; credentials will be verified next."
    echo "To apply .wp-env.json changes, run 'make wp-env-stop' first."
    exit 10
fi

# ---------------------------------------------------------------------------
# Untracked process on the port
# ---------------------------------------------------------------------------

echo "Error: port $PORT is held by a process this project does not track." >&2
echo >&2
for pid in $PORT_PIDS; do
    echo "  PID $pid: $(ps -o command= -p "$pid" 2>/dev/null | cut -c1-160)" >&2
done
echo >&2
echo "This is usually an orphaned Playground server, but it may belong to" >&2
echo "another worktree's environment. Check the command above, then stop it:" >&2
echo >&2
echo "  kill $(printf '%s' "$PORT_PIDS" | tr '\n' ' ')" >&2

exit 1
