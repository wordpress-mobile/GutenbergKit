#!/usr/bin/env bash
#
# demo-app-login.sh — Sign a demo app into a WordPress.com site with a bearer token.
#
# Launches the iOS demo app on a Simulator (`xcrun simctl launch -wpcom-token …`) or the
# Android demo app on an emulator or device (`adb shell am start --es wpcom-token …`). The
# app stores the token and the site as an account at launch, so the site shows up in its
# list with no OAuth application (see docs/code/wpcom-oauth.md) and no taps.
#
# The demo apps keep one account per site, so a token alone isn't enough: the site's ID and
# address are looked up from the WordPress.com REST API here and passed along with it.
#
# Build and install the app first, e.g. from Xcode or Android Studio.
#
# Usage:
#   bash bin/demo-app-login.sh --help

set -euo pipefail

IOS_BUNDLE_ID="org.wordpress.gutenberg.development"
ANDROID_PACKAGE="com.example.gutenbergkit"
ANDROID_ACTIVITY="$ANDROID_PACKAGE/.MainActivity"

usage() {
    cat <<'EOF'
Sign a demo app into a WordPress.com site with a bearer token.

Usage:
  bin/demo-app-login.sh [options]

Options:
  -p, --platform <ios|android>  Demo app to sign in (default: ios)
  -s, --site <domain>           WordPress.com site to add (default: the account's primary site)
  -d, --device <id>             Target device — a simulator UDID/name, or an adb serial
                                (default: the running one; prompts if several)
  -h, --help                    Show this help

Examples:
  bin/demo-app-login.sh                              # iOS demo app, booted simulator
  bin/demo-app-login.sh --platform android           # Android demo app, connected emulator
  bin/demo-app-login.sh --site example.wordpress.com # a site other than the primary one

The WordPress.com bearer token is read from (in order):
  1. WPCOM_TOKEN environment variable
  2. ~/.wpcom-token file

It is deliberately NOT accepted as a command-line flag: a token passed on the command line
would be saved in your shell history.
EOF
}

platform="ios"
site=""
device=""

require_value() {
    # $1 = option name, $2 = remaining argument count ($#)
    if [[ "$2" -lt 2 ]]; then
        echo "error: $1 requires a value" >&2
        exit 1
    fi
}

wpcom_get() {
    # Print fields of a WordPress.com REST API response, tab-separated. $1 = the path under
    # /rest/v1.1/, the rest = the field names. Reports the API's own message when it returns an error.
    local path="$1"
    shift
    # `-H @-` reads the Authorization header from stdin, which keeps the token out of the process list.
    # Node.js parses the JSON since it's guaranteed to be available (the web editor requires it).
    curl --silent --show-error --max-time 30 -H @- "https://public-api.wordpress.com/rest/v1.1/$path" \
        <<< "Authorization: Bearer $token" \
        | node -e '
            let data = "";
            process.stdin.on( "data", ( chunk ) => ( data += chunk ) );
            process.stdin.on( "end", () => {
                let json;
                try {
                    json = JSON.parse( data );
                } catch {
                    process.exit( 1 );
                }
                if ( json.error ) {
                    process.stderr.write( `error: WordPress.com said: ${ json.message || json.error }\n` );
                    process.exit( 1 );
                }
                process.stdout.write( process.argv.slice( 1 ).map( ( field ) => json[ field ] ).join( "\t" ) );
            } );
        ' "$@"
}

choose_device() {
    # Set `device` from parallel `ids` / `names` arrays: the only entry if there's just one,
    # otherwise prompt to choose. $1 = a noun for messages, $2 = a hint for when there are none.
    local noun="$1" hint="$2"
    local n=${#ids[@]}
    if [[ "$n" -eq 0 ]]; then
        echo "error: no running $noun. $hint" >&2
        exit 1
    fi
    if [[ "$n" -eq 1 ]]; then
        device="${ids[0]}"
        echo "Using the only running $noun: ${names[0]} (${device})"
        return
    fi

    echo "Multiple ${noun}s are running — choose one:" >&2
    local i
    for (( i = 0; i < n; i++ )); do
        printf "  %2d) %s (%s)\n" "$(( i + 1 ))" "${names[i]}" "${ids[i]}" >&2
    done
    local sel
    while true; do
        printf "Select a %s [1-%d]: " "$noun" "$n" >&2
        if ! read -r sel; then
            echo >&2
            echo "error: no selection made; re-run with --device <id>." >&2
            exit 1
        fi
        if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "$n" ]]; then
            device="${ids[sel - 1]}"
            echo "Using ${names[sel - 1]} (${device})"
            return
        fi
        echo "  not a valid choice: '$sel'" >&2
    done
}

resolve_ios_device() {
    ids=()
    names=()
    local line udid
    while IFS= read -r line; do
        # `|| true` so a UUID-less line doesn't trip `set -e` before the `continue` can skip it.
        udid=$(printf '%s\n' "$line" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)
        [[ -z "$udid" ]] && continue
        ids+=("$udid")
        names+=("$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*\([0-9A-Fa-f-]{36}\).*$//')")
    done < <(xcrun simctl list devices booted | grep -F "(Booted)" || true)

    choose_device "simulator" "Boot one (open Simulator, or 'xcrun simctl boot <udid>'), or pass --device <udid>."
}

resolve_android_device() {
    ids=()
    names=()
    local serial state rest model
    # `adb devices -l` lines look like: `emulator-5554  device product:... model:sdk_gphone64_arm64 ...`
    while read -r serial state rest; do
        [[ "$state" == "device" ]] || continue
        model=$(printf '%s\n' "$rest" | grep -oE 'model:[^ ]+' | cut -d: -f2 || true)
        ids+=("$serial")
        names+=("${model:-$serial}")
    done < <(adb devices -l | tail -n +2)

    choose_device "device" "Start an emulator (or connect a device), or pass --device <serial>."
}

shell_quote() {
    # Single-quote $1 for the device's shell: `adb shell` joins its arguments into one command line,
    # and WordPress.com tokens contain shell metacharacters like `#`, `(`, and `$`.
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform) require_value "$1" "$#"; platform="$2"; shift 2 ;;
        -s|--site) require_value "$1" "$#"; site="$2"; shift 2 ;;
        -d|--device) require_value "$1" "$#"; device="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

case "$platform" in
    ios|android) ;;
    *) echo "error: unknown platform '$platform' (expected 'ios' or 'android')" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Find the token
# ---------------------------------------------------------------------------

# The token is intentionally not a command-line argument, to keep it out of shell history.
token="${WPCOM_TOKEN:-}"
token_source="WPCOM_TOKEN"

if [[ -z "$token" && -f "$HOME/.wpcom-token" ]]; then
    token="$(tr -d '[:space:]' < "$HOME/.wpcom-token")"
    token_source="~/.wpcom-token"
fi

if [[ -z "$token" ]]; then
    echo "error: no WordPress.com token found. Set WPCOM_TOKEN, or write one to ~/.wpcom-token." >&2
    exit 1
fi
echo "Using the WordPress.com token from $token_source"

# ---------------------------------------------------------------------------
# Pick the device
# ---------------------------------------------------------------------------

if [[ -z "$device" ]]; then
    if [[ "$platform" == ios ]]; then resolve_ios_device; else resolve_android_device; fi
fi

# ---------------------------------------------------------------------------
# Look up the site
# ---------------------------------------------------------------------------

if [[ -n "$site" ]]; then
    # Accept a pasted URL as well as a bare domain.
    site="${site#*://}"
    site="${site%/}"
    site_info="$(wpcom_get "sites/$site?fields=ID,URL" ID URL)" || {
        echo "error: couldn't look up '$site' on WordPress.com." >&2
        exit 1
    }
else
    site_info="$(wpcom_get "me?fields=primary_blog,primary_blog_url" primary_blog primary_blog_url)" || {
        echo "error: couldn't look up the account's primary site on WordPress.com." >&2
        exit 1
    }
fi

IFS=$'\t' read -r site_id site_url <<< "$site_info"
site_host="${site_url#*://}"
site_host="${site_host%/}"

if ! [[ "$site_id" =~ ^[1-9][0-9]*$ ]] || [[ -z "$site_host" ]]; then
    echo "error: WordPress.com didn't return a site for this token. Pass --site <domain>." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Launch the app
# ---------------------------------------------------------------------------

echo "Signing the $platform demo app into $site_host on '$device'…"

if [[ "$platform" == ios ]]; then
    xcrun simctl launch --terminate-running-process "$device" "$IOS_BUNDLE_ID" \
        -wpcom-token "$token" -wpcom-site-id "$site_id" -wpcom-site-host "$site_host"
else
    # `-S` force-stops a running instance first, so the extras are delivered to a fresh `onCreate`.
    adb -s "$device" shell am start -S -W -n "$ANDROID_ACTIVITY" \
        --es wpcom-token "$(shell_quote "$token")" \
        --es wpcom-site-id "$site_id" \
        --es wpcom-site-host "$(shell_quote "$site_host")" > /dev/null
fi

echo "Done. $site_host is in the app's list of WordPress sites."
