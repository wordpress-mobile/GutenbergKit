#!/usr/bin/env bash

# Claude Code PostToolUse hook: lint Swift code with SwiftLint after an edit.
#
# Reads the hook payload (JSON) on stdin. When the edited file is Swift, runs
# `make lint-swift` so the hook uses the exact same SwiftLint binary and
# configuration as the project lint command. On violations, prints them to
# stderr and exits 2 so Claude Code feeds them back to the model for
# self-correction.
#
# The run is not scoped to the edited file. `.swiftlint.yml` already restricts
# linting to this project via `included:`/`excluded:`, so a whole-project run
# needs no path handling of its own: files in sibling working directories and
# the generated sources under `ios/Sources/GutenbergKit/Gutenberg` are both out
# of scope by configuration. It also costs about half a second more than a
# single-file run, since process startup dominates either way.

f=$(jq -r '.tool_input.file_path // empty')
case "$f" in
    *.swift) ;;
    *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# The SwiftPM plugin needs a toolchain. Exit quietly rather than failing the
# edit when this runs somewhere Xcode isn't available.
command -v xcrun >/dev/null 2>&1 || exit 0

out=$(make lint-swift 2>&1)
status=$?

# SwiftLint exits non-zero for `error`-severity violations, but only prints to
# stdout for warnings, so check both. Keep just the `file:line:col:` diagnostics
# so the model sees violations without SwiftPM's wrapper noise (e.g. "Command
# found error violations ... in package").
violations=$(printf '%s\n' "$out" | grep -E '^.+:[0-9]+:[0-9]+: (warning|error):')

if [ -n "$violations" ]; then
    printf '%s\n' "$violations" >&2
    exit 2
fi

# Surface genuine tooling failures (e.g. a broken BuildTools checkout) instead
# of silently passing.
if [ "$status" -ne 0 ]; then
    printf '%s\n' "$out" >&2
    exit 2
fi
