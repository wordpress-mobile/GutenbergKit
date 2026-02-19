# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

GutenbergKit is an experimental Gutenberg block editor for native iOS and Android apps built with web technologies. It consists of:

-   A React-based web editor using WordPress Gutenberg packages
-   Swift package for iOS integration
-   Kotlin library for Android integration
-   Native-to-web bridge for communication between platforms

## Common Development Commands

**CRITICAL**: Always use `make` commands over `npm` commands when they exist. The Makefile provides convenient wrappers that handle dependencies and configuration automatically.

To see all available make commands, run:

```bash
make help
# or simply
make
```

This will display a list of all available targets with descriptions.

### Web Development

```bash
# Install dependencies
npm ci

# Start development server (use this for active development)
make dev-server

# Start standalone React DevTools server
make dev-tools

# Preview production build locally
make preview

# Run JavaScript tests (one-time run)
make test-js

# Run JavaScript tests in watch mode (for active development)
make test-js-watch

# Lint JavaScript code
make lint-js

# Lint and auto-fix JavaScript code
make lint-fix-js

# Format JavaScript code
make format
```

### Building

```bash
# Build everything (web, iOS, Android)
make build

# This builds the web app and copies assets to:
# - ios/Sources/GutenbergKit/Gutenberg/
# - android/Gutenberg/src/main/assets/

# By default, the build is skipped if output directories already exist
# Force refresh of dependencies, translations, and JS build
make build REFRESH_DEPS=1 REFRESH_L10N=1 REFRESH_JS_BUILD=1

# Clean build artifacts
make clean
```

### iOS Development

```bash
# Build Swift package
make build-swift-package

# Run Swift tests
make test-swift-package
```

### Android Development

```bash
# Build Android library to local Maven
make local-android-library

# Run Android tests
make test-android
```

> **Note:** Most `make` targets have equivalent `npm` scripts in `package.json`. Build targets accept `REFRESH_DEPS=1`, `REFRESH_L10N=1`, and `REFRESH_JS_BUILD=1` flags to force refresh of dependencies, translations, and JavaScript builds respectively. Run `make help` for full details.

## Architecture

### Web Editor Structure

The web editor is built with React and WordPress packages:

-   **Entry Points**:
    -   `src/index.js` - Main editor entry point (supports plugins via bundled code)
-   **Core Components**:
    -   `src/components/editor/` - Main editor component with host bridge integration
    -   `src/components/visual-editor/` - Visual editing interface
    -   `src/components/text-editor/` - HTML text editing interface
-   **Native Bridge**: `src/utils/bridge.js` - Handles communication between web and native platforms

### Native Integration

#### iOS (Swift)

-   **Main Classes**:
    -   `EditorViewController` - WebView container and bridge
    -   `EditorConfiguration` - Editor settings and capabilities
    -   `EditorService` - API communication layer
    -   `GBWebView` - Custom WebView with editor-specific features

#### Android (Kotlin)

-   **Main Classes**:
    -   `GutenbergView` - WebView container and bridge
    -   `EditorConfiguration` - Editor settings and capabilities
    -   `GutenbergRequestInterceptor` - Handles API routing
    -   `CachedAssetRequestInterceptor` - Asset caching layer

### Communication Pattern

The editor uses a bidirectional bridge pattern:

1. **Web → Native**: JavaScript calls methods on `window.editorDelegate` (Android) or `window.webkit.messageHandlers` (iOS)
2. **Native → Web**: Native code evaluates JavaScript in the WebView
3. **Message Types**: Editor loaded, content changed, media upload, block management, etc.

### Build System

-   **Vite**: Handles web bundling and development server
-   **Translations**: Automated translation preparation from WordPress packages
-   **Asset Distribution**: Built assets are copied to platform-specific directories

> For deeper architectural context on specific subsystems, see the docs under `docs/code/` — including `architecture.md`, `plugins.md`, `preloading.md`, and others.

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
```

These commands ensure code quality and prevent lint errors from blocking commits.

### Pull Request Guidelines

When creating pull requests:

1. **Use the PR template**: Read `.github/PULL_REQUEST_TEMPLATE.md` to get the current template structure and follow it when writing the PR body.
2. **Assign a label**: Use `gh label list` to retrieve available labels and select the most relevant one for the PR.

### E2E Test Interaction Guidelines

Since GutenbergKit targets touch devices (iOS/Android), E2E tests should prefer interacting with visible UI elements over keyboard shortcuts where possible. This better reflects how real users interact with the editor on mobile.

-   **Use toolbar buttons** for formatting (Bold, Italic) and link insertion — click the button by accessible name via `editor.clickBold()`, `editor.clickItalic()`, or `editor.insertLink(url)`
-   **Use keyboard** for interactions that have no UI equivalent or that simulate the software keyboard:
    -   Text input: `keyboard.type()` (simulates software keyboard key events)
    -   Caret positioning: `Home`, `ArrowRight` (no toolbar equivalent)
    -   Text selection: `Shift+ArrowRight`, `editor.selectAll()` (no toolbar equivalent)
    -   Block split/merge: `Enter` and `Backspace` (structural editing via software keyboard)

## Common Pitfalls

-   **Do not edit build output directories.** The files under `ios/Sources/GutenbergKit/Gutenberg/` and `android/Gutenberg/src/main/assets/` are generated by `make build`. Never modify them directly — run `make build` to regenerate them instead.
-   **Do not use `console.*` directly.** Always use the logger utility (`src/utils/logger.js`). See the Logging Guidelines section above.
-   **Always run `make lint-fix-js` before committing.** Lint errors will block commits via pre-commit hooks.
-   **Patching dependencies: modify `node_modules`, then run `npx patch-package <package-name>`.** Do not edit the `.patch` files under `patches/` by hand. The workflow is: make changes in `node_modules/<package>`, verify they work, then run `npx patch-package <package-name>` to create or update the patch file. Document the patch and its justification in `patches/README.md`.
-   **Do not edit the `dist/` directory.** It is a build artifact generated by Vite. Run `make build` or `make dev-server` instead.
