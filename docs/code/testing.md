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

Test files live in `e2e/*.spec.js`. Before running for the first time, install the browser binary:

```bash
npx playwright install chromium
```

Run tests:

```bash
make test-e2e
```

Run in interactive UI mode:

```bash
make test-e2e-ui
```

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
