# GutenbergKit Architecture

## Overview

GutenbergKit is a cross-platform Gutenberg block editor implementation that bridges WordPress's web-based editor with native iOS and Android applications. The architecture consists of three main layers:

1. **Web Layer**: React-based editor using WordPress Gutenberg packages
2. **Bridge Layer**: Bidirectional communication between web and native code
3. **Native Layer**: Platform-specific implementations (Swift for iOS, Kotlin for Android)

## Project Structure

```
GutenbergKit/
├── src/                    # Web editor source code
│   ├── components/         # React components
│   │   ├── editor/         # Main editor component
│   │   ├── visual-editor/  # Visual editing interface
│   │   └── text-editor/    # HTML text editing interface
│   ├── utils/              # Utility functions
│   │   └── bridge.js       # Native-to-web communication
│   └── index.js            # Main editor entry point
├── ios/                    # iOS Swift package
│   └── Sources/
│       └── GutenbergKit/
├── android/                # Android Kotlin library
│   └── Gutenberg/
├── docs/                   # Documentation
└── patches/                # Third-party package patches
```

## Communication Architecture

### Web → Native Communication

The web editor communicates with native code through platform-specific APIs:

-   **iOS**: `window.webkit.messageHandlers`
-   **Android**: `window.editorDelegate`

Common message types include:

-   Editor initialization
-   Content updates
-   Media uploads
-   Block operations
-   Error reporting

### Native → Web Communication

Native code executes JavaScript in the WebView to:

-   Initialize the editor with content
-   Update editor settings
-   Handle media selection
-   Process API responses
