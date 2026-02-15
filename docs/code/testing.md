# Testing

This guide covers testing and code quality tools in GutenbergKit.

## Manual Tests

Important, high-level test cases are [documented](../test-cases.md) for manual testing on native platforms. These cover scenarios that require the native shell — toolbar state, bridge round-trips, media uploads, WebView lifecycle, and block inserter via native sheet.

## Unit Tests

### JavaScript (Vitest)

Test files follow the `*.test.{js,jsx}` naming convention.

```bash
make test-js
```

### Swift (Swift Testing)

```bash
make test-swift-package
```

### Android (JUnit)

```bash
make test-android
```

## E2E Tests

E2E tests use Playwright to load the editor in a headless Chromium browser and verify Gutenberg editor logic — block operations, text formatting, split/merge, and data store state. They run against the Vite dev server with no native layer involved.

Test files live in `e2e/*.spec.js`.

Run tests:

```bash
make test-e2e
```

Run in interactive UI mode:

```bash
make test-e2e-ui
```

### iOS E2E Tests

-   Framework: XCUITest
-   Test files: `ios/Demo-iOS/GutenbergUITests/`
-   Requires: Xcode and an iOS Simulator

These tests launch the Demo iOS app via `XCUIApplication` and verify native shell behavior — toolbar rendering, menu interactions, WebView lifecycle, and native-to-JS bridge state synchronization.

To run the iOS E2E tests:

```bash
make test-ios-e2e
```

> **Note:** The web editor must be built first (`make build`). The E2E
> target depends on `build` and will handle this automatically.

## Code Quality

Before submitting a pull request, ensure your code passes formatting and linting checks.

Format code using Prettier:

```bash
make format
```

Lint JavaScript code using ESLint:

```bash
# Auto-fix linting errors
make lint-js-fix

# Verify linting passes
make lint-js
```
