# Testing

This guide covers automated testing and code quality tools in GutenbergKit.

## Automated Tests

Important, high-level test cases are [documented](../test-cases.md) for manual testing guidance. Additionally, automated tests are included in the project to ensure code quality and functionality.

### JavaScript Tests

-   Framework: Vitest
-   Test files: `*.test.{js,jsx}`

To run the JavaScript tests:

```bash
make test-js
```

### Swift Tests

-   Framework: Swift Testing

To run the Swift tests:

```bash
make test-swift
```

### Android Tests

-   Framework: JUnit

To run the Android tests:

```bash
make test-android
```

## Code Quality

Before submitting a pull request, ensure your code passes formatting and linting checks.

### Formatting

Format JavaScript code using Prettier:

```bash
make format
```

### Linting

Lint JavaScript code using ESLint:

```bash
# Auto-fix linting errors
make lint-js-fix

# Verify linting passes
make lint-js
```
