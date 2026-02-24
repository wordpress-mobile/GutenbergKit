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

There are two ways to run the tests, depending on how the editor JS is served.

#### Dev server (local development)

Uses the Vite dev server for faster iteration — no production build required. Start the dev server in one terminal, then run the tests in another:

```bash
# Terminal 1
make dev-server

# Terminal 2
make test-ios-e2e-dev
```

This sets `TEST_RUNNER_GUTENBERG_EDITOR_URL`, which `xcodebuild` forwards to the test runner process (with the `TEST_RUNNER_` prefix stripped). The test setup then passes `GUTENBERG_EDITOR_URL` to the app under test via `launchEnvironment`, so the WebView loads from `http://localhost:5173` instead of the bundled assets.

#### Production build (CI)

Uses the production JS bundle built by Vite. This is what CI runs and is the default `make test-ios-e2e` target:

```bash
make test-ios-e2e
```

The target depends on `build` and will handle it automatically.

#### Switching between modes

The mode is controlled by the `GUTENBERG_EDITOR_URL` environment variable. When set, `EditorViewController` loads from that URL; otherwise it loads from the bundled `index.html`.

-   `make test-ios-e2e-dev` — sets `TEST_RUNNER_GUTENBERG_EDITOR_URL=http://localhost:5173` and checks that the dev server is running before starting.
-   `make test-ios-e2e` — does not set the variable; runs a production build first.

You can also pass the variable directly if you need a custom URL:

```bash
TEST_RUNNER_GUTENBERG_EDITOR_URL=http://localhost:5173 xcodebuild test \
    -project ./ios/Demo-iOS/Gutenberg.xcodeproj \
    -scheme GutenbergUITests \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 17'
```

> **Note:** The `TEST_RUNNER_` prefix is an `xcodebuild` convention — variables with this prefix are forwarded to test runner processes with the prefix removed.

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
