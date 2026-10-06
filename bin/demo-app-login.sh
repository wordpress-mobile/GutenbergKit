#!/usr/bin/env bash
#
# demo-app-login.sh — Sign a demo app into WordPress sites with credentials stored on this machine.
#
# Launches the iOS demo app on a Simulator (`xcrun simctl launch …`) or the Android demo app on
# an emulator or device (`adb shell am start …`), with the accounts as one launch argument. The
# app stores them at launch, so the sites show up in its list with no login flow and no taps.
#
# Two kinds of site can be signed in:
#
#   - A self-hosted site listed in ~/.config/wp/sites, with its username and application
#     password. The site's REST API root is looked up here and passed along with them.
#   - A WordPress.com site, with a bearer token, so no OAuth application is needed (see
#     docs/code/wpcom-oauth.md). The demo apps keep one account per site, so a token alone
#     isn't enough: the site's ID and address are looked up here and passed along with it.
#
# With no site named, every site in the file is signed in, along with the WordPress.com
# account's primary site when there is a token. They all go to the app in a single launch.
#
# Build and install the app first, e.g. from Xcode or Android Studio.
#
# Usage:
#   bash bin/demo-app-login.sh --help

set -euo pipefail

IOS_BUNDLE_ID="org.wordpress.gutenberg.development"
ANDROID_PACKAGE="com.example.gutenbergkit"
ANDROID_ACTIVITY="$ANDROID_PACKAGE/.MainActivity"
SITES_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/wp/sites"
# Separates the fields of an account while it waits to be turned into JSON. Unlike a tab, a
# unit separator can't appear in a line of the sites file.
FIELD_SEPARATOR=$'\x1f'

usage() {
    cat <<'EOF'
Sign a demo app into WordPress sites with credentials stored on this machine.

Usage:
  bin/demo-app-login.sh [options]

Options:
  -p, --platform <ios|android>  Demo app to sign in (default: ios)
  -s, --site <site>             The one site to add: one listed in ~/.config/wp/sites, or
                                else a WordPress.com site (default: every site in
                                ~/.config/wp/sites, and the WordPress.com account's primary
                                site)
  -d, --device <id>             Target device — a simulator UDID/name, or an adb serial
                                (default: the running one; prompts if several)
  -h, --help                    Show this help

Examples:
  bin/demo-app-login.sh                              # iOS demo app, every site you have credentials for
  bin/demo-app-login.sh --platform android           # Android demo app, connected emulator
  bin/demo-app-login.sh --site example.com           # only this site from ~/.config/wp/sites
  bin/demo-app-login.sh --site example.wordpress.com # only this WordPress.com site

Self-hosted sites are read from ~/.config/wp/sites, one per line:

  <url> <username> <application password>

The password is the rest of the line, so an application password can be pasted with its
spaces. Blank lines and lines starting with # are skipped.

The WordPress.com bearer token is read from (in order):
  1. WPCOM_TOKEN environment variable
  2. ~/.wpcom-token file

Credentials are deliberately NOT accepted as command-line flags: anything passed on the
command line would be saved in your shell history.
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

site_key() {
    # Print a site address in the form used to compare two of them: no scheme, no trailing
    # slash, lowercase.
    local key="${1#*://}"
    printf '%s' "${key%/}" | tr '[:upper:]' '[:lower:]'
}

read_sites() {
    # Add lines of the sites file to the `site_urls`, `site_usernames` and `site_passwords` arrays:
    # the one whose URL matches $1, or every line when $1 is empty.
    [[ -f "$SITES_FILE" ]] || return 0

    local wanted="" url username password
    [[ -z "$1" ]] || wanted="$(site_key "$1")"
    # `read` gives the last variable the rest of the line, which keeps the spaces in a password.
    # The `||` keeps a final line that has no trailing newline.
    while read -r url username password || [[ -n "$url" ]]; do
        [[ -z "$url" || "$url" == \#* ]] && continue
        [[ -z "$wanted" || "$(site_key "$url")" == "$wanted" ]] || continue
        # A site listed without a scheme is assumed to be served over HTTPS.
        [[ "$url" == *://* ]] || url="https://$url"
        site_urls+=("${url%/}")
        site_usernames+=("$username")
        site_passwords+=("$password")
        [[ -z "$wanted" ]] || break
    done < "$SITES_FILE"
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

discover_api_root() {
    # Print the REST API root that the WordPress site at $1 advertises in its `Link` header.
    curl --silent --show-error --location --max-time 30 --dump-header - --output /dev/null "$1" \
        | tr -d '\r' \
        | sed -n 's/^[Ll]ink:.*<\([^>]*\)>; *rel="https:\/\/api\.w\.org\/".*/\1/p' \
        | tail -n 1
}

api_get() {
    # Print fields of a JSON API response, tab-separated. $1 = who is being asked, for error
    # messages, $2 = the URL, $3 = the Authorization header value, the rest = the field names.
    # Reports the API's own message when it returns an error.
    local who="$1" url="$2" authorization="$3"
    shift 3
    # `-H @-` reads the Authorization header from stdin, which keeps the credentials out of the
    # process list. Node.js parses the JSON since it's guaranteed to be available (the web editor
    # requires it).
    curl --silent --show-error --max-time 30 -H @- "$url" <<< "Authorization: $authorization" \
        | node -e '
            const [ who, ...fields ] = process.argv.slice( 1 );
            let data = "";
            process.stdin.on( "data", ( chunk ) => ( data += chunk ) );
            process.stdin.on( "end", () => {
                let json;
                try {
                    json = JSON.parse( data );
                } catch {
                    process.stderr.write( `error: ${ who } sent a response that isn'"'"'t JSON.\n` );
                    process.exit( 1 );
                }
                // WordPress.com names an error in `error`; WordPress itself names it in `code`.
                if ( json.error || json.code ) {
                    process.stderr.write( `error: ${ who } said: ${ json.message || json.error || json.code }\n` );
                    process.exit( 1 );
                }
                process.stdout.write( fields.map( ( field ) => json[ field ] ).join( "\t" ) );
            } );
        ' "$who" "$@"
}

add_self_hosted_account() {
    # Look up the self-hosted site at $1, check that it accepts the username $2 and password $3,
    # and add it to `accounts`. Fails, having said why, when the site can't be signed in to.
    local url="$1" username="$2" password="$3" api_root basic_credentials
    if [[ -z "$username" || -z "$password" ]]; then
        echo "error: the line for $url in $SITES_FILE needs a URL, a username and a password." >&2
        return 1
    fi

    api_root="$(discover_api_root "$url")" || api_root=""
    if [[ -z "$api_root" ]]; then
        echo "error: couldn't find a WordPress REST API at $url." >&2
        return 1
    fi

    # Check the credentials here, where a failure can be reported, rather than leaving the app to
    # find out when the site is opened.
    basic_credentials="$(printf '%s' "$username:$password" | base64 | tr -d '\n')"
    api_get "$url" "${api_root}wp/v2/users/me" "Basic $basic_credentials" id > /dev/null || {
        echo "error: couldn't sign in to $url as '$username'." >&2
        return 1
    }

    accounts+="self-hosted$FIELD_SEPARATOR$url$FIELD_SEPARATOR$username$FIELD_SEPARATOR$password$FIELD_SEPARATOR$api_root"$'\n'
    account_names+=("${url#*://}")
}

add_wpcom_account() {
    # Look up the WordPress.com site $1 — or the account's primary site when $1 is empty — and add
    # it to `accounts`. Fails, having said why, when there is no such site for this token.
    local wanted="$1" site_info site_id site_url site_name
    if [[ -n "$wanted" ]]; then
        # Accept a pasted URL as well as a bare domain.
        wanted="${wanted#*://}"
        wanted="${wanted%/}"
        site_info="$(api_get "WordPress.com" "https://public-api.wordpress.com/rest/v1.1/sites/$wanted?fields=ID,URL" "Bearer $token" ID URL)" || {
            echo "error: couldn't look up '$wanted' on WordPress.com." >&2
            return 1
        }
    else
        site_info="$(api_get "WordPress.com" "https://public-api.wordpress.com/rest/v1.1/me?fields=primary_blog,primary_blog_url" "Bearer $token" primary_blog primary_blog_url)" || {
            echo "error: couldn't look up the account's primary site on WordPress.com." >&2
            return 1
        }
    fi

    IFS=$'\t' read -r site_id site_url <<< "$site_info"
    site_name="${site_url#*://}"
    site_name="${site_name%/}"
    if ! [[ "$site_id" =~ ^[1-9][0-9]*$ ]] || [[ -z "$site_name" ]]; then
        echo "error: WordPress.com didn't return a site for this token. Pass --site <domain>." >&2
        return 1
    fi

    accounts+="wpcom$FIELD_SEPARATOR$token$FIELD_SEPARATOR$site_id$FIELD_SEPARATOR$site_name"$'\n'
    account_names+=("$site_name")
}

accounts_json() {
    # Print `accounts` as the JSON array the demo apps take in their `accounts` launch argument.
    # It goes to Node.js on stdin, which keeps the credentials out of the process list.
    printf '%s' "$accounts" | FIELD_SEPARATOR="$FIELD_SEPARATOR" node -e '
        let data = "";
        process.stdin.on( "data", ( chunk ) => ( data += chunk ) );
        process.stdin.on( "end", () => {
            const entries = data.split( "\n" ).filter( Boolean ).map( ( line ) => {
                const [ kind, ...fields ] = line.split( process.env.FIELD_SEPARATOR );
                if ( kind === "wpcom" ) {
                    const [ wpcomToken, wpcomSiteId, wpcomSiteHost ] = fields;
                    return { wpcomToken, wpcomSiteId: Number( wpcomSiteId ), wpcomSiteHost };
                }
                const [ siteUrl, username, password, siteApiRoot ] = fields;
                return { siteUrl, username, password, siteApiRoot };
            } );
            process.stdout.write( JSON.stringify( entries ) );
        } );
    '
}

shell_quote() {
    # Single-quote $1 for the device's shell: `adb shell` joins its arguments into one command line,
    # and tokens and passwords contain shell metacharacters like `#`, `(`, `$` and spaces.
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
# Find the credentials
#
# Neither kind is a command-line argument, to keep them out of shell history.
# ---------------------------------------------------------------------------

site_urls=()
site_usernames=()
site_passwords=()
# WordPress.com sites to add. An empty entry stands for the account's primary site.
wpcom_sites=()

token="${WPCOM_TOKEN:-}"
token_source="WPCOM_TOKEN"
if [[ -z "$token" && -f "$HOME/.wpcom-token" ]]; then
    token="$(tr -d '[:space:]' < "$HOME/.wpcom-token")"
    token_source="~/.wpcom-token"
fi

read_sites "$site"

if [[ -n "$site" ]]; then
    if [[ ${#site_urls[@]} -eq 0 ]]; then
        if [[ -z "$token" ]]; then
            echo "error: no WordPress.com token found. Set WPCOM_TOKEN, or write one to ~/.wpcom-token." >&2
            echo "       ('$site' isn't listed in $SITES_FILE, so it was taken to be a WordPress.com site.)" >&2
            exit 1
        fi
        wpcom_sites+=("$site")
    fi
elif [[ -n "$token" ]]; then
    wpcom_sites+=("")
fi

if [[ ${#site_urls[@]} -eq 0 && ${#wpcom_sites[@]} -eq 0 ]]; then
    echo "error: nothing to sign in to. List sites in $SITES_FILE, or set WPCOM_TOKEN, or write a" >&2
    echo "       WordPress.com token to ~/.wpcom-token." >&2
    exit 1
fi

if [[ ${#site_urls[@]} -eq 1 ]]; then
    echo "Using the credentials for ${site_urls[0]} from $SITES_FILE"
elif [[ ${#site_urls[@]} -gt 1 ]]; then
    echo "Using the ${#site_urls[@]} sites listed in $SITES_FILE"
fi
if [[ ${#wpcom_sites[@]} -gt 0 ]]; then
    echo "Using the WordPress.com token from $token_source"
fi

# ---------------------------------------------------------------------------
# Pick the device
# ---------------------------------------------------------------------------

if [[ -z "$device" ]]; then
    if [[ "$platform" == ios ]]; then resolve_ios_device; else resolve_android_device; fi
fi

# ---------------------------------------------------------------------------
# Look up the sites
#
# A site that can't be signed in to is reported and left out, so that one dead test site
# doesn't hold up the rest.
# ---------------------------------------------------------------------------

# One account per line, its fields separated by $FIELD_SEPARATOR.
accounts=""
account_names=()
failed=0

for (( i = 0; i < ${#site_urls[@]}; i++ )); do
    add_self_hosted_account "${site_urls[i]}" "${site_usernames[i]}" "${site_passwords[i]}" || failed=$(( failed + 1 ))
done
for (( i = 0; i < ${#wpcom_sites[@]}; i++ )); do
    add_wpcom_account "${wpcom_sites[i]}" || failed=$(( failed + 1 ))
done

if [[ ${#account_names[@]} -eq 0 ]]; then
    exit 1
fi

signed_in="${account_names[0]}"
for (( i = 1; i < ${#account_names[@]}; i++ )); do
    signed_in+=", ${account_names[i]}"
done

# ---------------------------------------------------------------------------
# Launch the app
#
# Every account goes in one `accounts` argument — a launch argument on iOS, a string extra on
# Android — so the app is launched once however many sites there are.
# ---------------------------------------------------------------------------

echo "Signing the $platform demo app into $signed_in on '$device'…"

if [[ "$platform" == ios ]]; then
    # This returns once the app's process exists, a moment before the app has stored the accounts.
    xcrun simctl launch --terminate-running-process "$device" "$IOS_BUNDLE_ID" -accounts "$(accounts_json)"
else
    # `-S` force-stops a running instance first, so the extra is delivered to a fresh `onCreate`.
    adb -s "$device" shell am start -S -W -n "$ANDROID_ACTIVITY" \
        --es accounts "$(shell_quote "$(accounts_json)")" > /dev/null
fi

echo "Done. Signed in to $signed_in."

if [[ "$failed" -gt 0 ]]; then
    echo "error: $failed of $(( failed + ${#account_names[@]} )) sites couldn't be signed in to — see above." >&2
    exit 1
fi
