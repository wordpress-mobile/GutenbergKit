# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

GutenbergKit is an experimental Gutenberg block editor for native iOS and Android apps built with web technologies. It consists of:

-   A React-based web editor using WordPress Gutenberg packages
-   Swift package for iOS integration
-   Kotlin library for Android integration
-   Native-to-web bridge for communication between platforms

## Common Development Commands

### Web Development

```bash
# Install dependencies
npm ci

# Start development server (use this for active development)
make dev-server
# or
npm run dev

# Run JavaScript tests
make test-js
# or
npm run test -- run

# Lint JavaScript code
make lint-js
# or
npm run lint

# Format JavaScript code
make fmt-js
# or
npm run format
```

### Building

```bash
# Build everything (web, iOS, Android)
make build

# This builds the web app and copies assets to:
# - ios/Sources/GutenbergKit/Gutenberg/
# - android/Gutenberg/src/main/assets/
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

### Remote Editor Development

```bash
# Start development server for remote editor
make dev-server-remote
# or
npm run dev:remote
```

## Architecture

### Web Editor Structure

The web editor is built with React and WordPress packages:

-   **Entry Points**:
    -   `src/index.jsx` - Local editor entry
    -   `src/remote.jsx` - Remote editor entry (for plugin support)
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

-   **Vite**: Handles web bundling with separate configs for local and remote editors
-   **Translations**: Automated translation preparation from WordPress packages
-   **Asset Distribution**: Built assets are copied to platform-specific directories

## Code Quality Standards

The project follows WordPress coding standards for JavaScript:

-   **ESLint**: Uses `@wordpress/eslint-plugin/recommended` configuration
-   **Prettier**: Uses `@wordpress/prettier-config` for code formatting

Always run these commands before committing:

```bash
# Lint JavaScript code
npm run lint

# Format JavaScript code
npm run format
```
