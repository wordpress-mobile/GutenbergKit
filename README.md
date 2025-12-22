# GutenbergKit

<img width="250" style="display:block; margin-left:auto; margin-right:auto;" alt="GutenbergKit running on an iPhone" src="./docs/gutenberg-kit-preview.png">

GutenbergKit brings the WordPress block editor to native mobile applications. It bridges WordPress's web-based Gutenberg editor with native iOS and Android apps, enabling a consistent editing experience across platforms.

The architecture consists of three main layers:

-   **Web Layer**: React-based editor using WordPress Gutenberg packages
-   **Bridge Layer**: Bidirectional communication between web and native code
-   **Native Layer**: Platform-specific implementations (Swift for iOS, Kotlin for Android)

## Getting Started

### Using GutenbergKit

To integrate GutenbergKit into your iOS or Android app, include the package as a dependency:

-   **iOS**: Add the Swift package from the `ios/` directory
-   **Android**: Add the Kotlin library from the `android/` directory

See the [Integration Guide](./docs/integration.md) for detailed setup instructions and code examples.

### Contributing

We welcome contributions! See the [Contributing Guide](./CONTRIBUTING.md) for setup instructions, development workflow, and how to submit changes.
