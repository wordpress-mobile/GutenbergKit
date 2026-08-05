# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

GutenbergKit is a Gutenberg block editor for native iOS and Android apps built with web technologies. It consists of:

-   A React-based web editor using WordPress Gutenberg packages
-   Swift package for iOS integration
-   Kotlin library for Android integration
-   Native-to-web bridge for communication between platforms

For deeper architectural context on specific subsystems, see the docs under `docs/code/` — including `architecture.md`, `plugins.md`, `preloading.md`, and others.

## Common Development Commands

**CRITICAL**: Always use `make` commands over underlying tool commands (`npm`, `swift`, `gradle`, etc.) when they exist. The Makefile provides convenient wrappers that handle dependencies and configuration automatically. However, when you need to pass specific arguments that a `make` target does not support — such as running Prettier on a single file, linting only changed files, or running a single test file — use the underlying tool directly.

To see all available make commands with descriptions, run:

```bash
make help
```

By default, dependencies, translations, and JS build are skipped if output directories already exist. Environment variables be used to force refresh of these steps when needed.

-   `REFRESH_DEPS=1` - Force refresh of dependencies (e.g. re-install npm packages)
-   `REFRESH_L10N=1` - Force refresh of translations (e.g. re-run translation extraction)
-   `REFRESH_JS_BUILD=1` - Force refresh of JavaScript build (e.g. clear Vite cache)

## Local WordPress Environment (wp-env)

A local WordPress environment powered by `@wordpress/env` is available for verifying/testing changes against a full editor experience with theme styles, media uploads, and plugin block assets. Relevant commands are available via `make help`.

See `docs/code/local-wordpress.md` for detailed setup instructions and troubleshooting.

## Code Quality Standards

The project follows WordPress coding standards for JavaScript:

-   **ESLint**: Uses `@wordpress/eslint-plugin/recommended` configuration
-   **Prettier**: Uses `@wordpress/prettier-config` for code formatting

### Function Ordering Convention

Functions in this project are ordered by usage/call order rather than alphabetically:

-   **Main/exported functions first**: The primary exported function appears at the top of the file
-   **Helper functions follow in call order**: Helper functions are ordered based on when they are first called in the main function
-   **Example**: If `mainFunction()` calls `helperA()` then `helperB()`, the file order should be: `mainFunction`, `helperA`, `helperB`

This ordering makes code easier to read top-to-bottom, as you encounter function definitions before needing to understand their implementation details.

### Logging Guidelines

The project uses a custom logger utility (`src/utils/logger.js`) instead of direct `console` methods:

-   **MUST**: Always use the logger utility functions (`error`, `warn`, `info`, `debug`) instead of `console.*` methods
-   **Error Logging**: Use `error()` for actual errors and exceptions
-   **Warning Logging**: Use `warn()` for important warnings that should be addressed
-   **Info Logging**: Use `info()` for general informational messages
-   **Debug Logging**: Use `debug()` for verbose logging that is helpful during development but not critical
-   **Usage**: Import from the logger utility: `import { error, warn, info, debug } from './utils/logger';`

Note: Console logs should be used sparingly. For verbose or development-specific logging, prefer the `debug()` function which can be controlled via log levels.

### Pre-Commit Checklist

**CRITICAL**: Always run these commands after making code changes and before presenting work for review/commit:

```bash
# Auto-fix linting errors & verify linting passes
make lint-js-fix

# When Swift files changed
make lint-swift-fix
```

These commands ensure code quality and prevent lint errors from blocking commits.

### Swift Linting

Swift code is linted with SwiftLint, run via the SwiftPM plugin in the `BuildTools/`
package so the linter stays out of the dependency graph of anyone consuming
GutenbergKit via SwiftPM.

-   `make lint-swift` — report violations
-   `make lint-swift-fix` — auto-correct the violations SwiftLint can fix

The SwiftLint version is pinned in a single place: the `swiftlint_version` key in
`.swiftlint.yml`. `BuildTools/Package.swift` parses that key at manifest-evaluation
time, so for local runs and the editor hook the binary version and the rule set
cannot drift apart. To upgrade, bump `swiftlint_version` and run
`swift package --package-path BuildTools resolve`.

CI is the exception: the `:swift: SwiftLint` step runs on the shared `linter`
agent queue, which invokes that image's own SwiftLint binary rather than the
pinned one. If the image moves far enough ahead of `swiftlint_version`, CI can
fail on a rule that passes locally — bump the pin to resolve it.

Rules are opt-in only (`only_rules:`), mirroring WordPress-iOS so the two codebases
stay consistent for the shared team.

To lint specific files rather than the whole project, set `SWIFT_LINT_PATHS`:

```bash
make lint-swift SWIFT_LINT_PATHS=ios/Sources/GutenbergKit/Sources/EditorService.swift
```

Separate multiple files with **newlines**, not spaces, so that paths containing
spaces stay intact. This makes it easy to lint just the changed files:

```bash
make lint-swift SWIFT_LINT_PATHS="$(git diff --name-only -- '*.swift')"
```

Each value must be a path to an existing **file**. Passing a directory (or a
nonexistent path) silently falls back to linting the whole project rather than
reporting an error.

A Claude Code `PostToolUse` hook (`bin/claude-hooks/swiftlint.sh`, wired up in
`.claude/settings.json`) runs after any Swift edit and reports violations back
for self-correction, so Swift edits are checked as they happen rather than only
at commit time.

The hook lints the whole project rather than the edited file — process startup
dominates the runtime, so scoping the run saves little, and a full run also
catches violations in files the edit did not name. It relies on the
`included:`/`excluded:` keys above for scoping, so it reports only GutenbergKit
violations even when the edited file lives in another working directory.

### Commit and Pull Request Guidelines

Follow the conventions documented in [Developer Workflows](./docs/code/developer-workflows.md), including Conventional Commits prefixes, PR template usage, and label assignment.

### E2E Test Interaction Guidelines

Since GutenbergKit targets touch devices (iOS/Android), E2E tests should prefer interacting with visible UI elements over keyboard shortcuts where possible. This better reflects how real users interact with the editor on mobile.

-   **Use toolbar buttons** for formatting (Bold, Italic) and link insertion — click the button by accessible name via `editor.clickBold()`, `editor.clickItalic()`, or `editor.insertLink(url)`
-   **Use keyboard** for interactions that have no UI equivalent or that simulate the software keyboard:
    -   Text input: `keyboard.type()` (simulates software keyboard key events)
    -   Caret positioning: `Home`, `ArrowRight` (no toolbar equivalent)
    -   Text selection: `Shift+ArrowRight`, `editor.selectAll()` (no toolbar equivalent)
    -   Block split/merge: `Enter` and `Backspace` (structural editing via software keyboard)

## Common Pitfalls

-   **The primary branch is `trunk` (not `main`).** Always ensure you are working on the `trunk` branch for development and pull requests. The `main` branch is not used in this repository.
-   **Do not edit build output directories.** The files under `dist/`, `ios/Sources/GutenbergKit/Gutenberg/`, and `android/Gutenberg/src/main/assets/` are generated by `make build`. Never modify them directly — run `make build` to regenerate them instead.
-   **Patching dependencies: modify `node_modules`, then run `npx patch-package <package-name>`.** Do not edit the `.patch` files under `patches/` by hand. The workflow is: make changes in `node_modules/<package>`, verify they work, then run `npx patch-package <package-name>` to create or update the patch file. Document the patch and its justification in `patches/README.md`. **Important:** patch-package excludes `package.json` from diffs by default. If your patch modifies `package.json` (e.g., adding entries to the `exports` field), you must use `npx patch-package <package-name> --exclude='^$'` to override this behavior and include the `package.json` changes in the patch.
