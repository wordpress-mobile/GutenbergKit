# GutenbergKit

<img width="250" alt="GutenbergKit running on an iPhone" src="./docs/gutenberg-kit-preview.png">

GutenbergKit brings the [WordPress](https://wordpress.org/) block editor to native mobile applications. It bridges WordPress's web-based [Gutenberg](https://github.com/WordPress/gutenberg/) editor with native iOS and Android apps, enabling a consistent editing experience across platforms.

The architecture consists of three main layers:

-   **Web Layer**: React-based editor using WordPress Gutenberg packages
-   **Bridge Layer**: Bidirectional communication between web and native code
-   **Native Layer**: Platform-specific implementations (Swift for iOS, Kotlin for Android)

## Getting Started

### Contributing

We welcome contributions! To get started:

-   **[Getting Started](./docs/code/getting-started.md)** - Set up your local development environment
-   **[Contributing Guide](./CONTRIBUTING.md)** - Development workflow, guidelines, and how to submit changes

### Using GutenbergKit

To integrate GutenbergKit into your own iOS or Android app, include the package as a dependency:

-   **iOS**: Add the Swift package from the repository root
-   **Android**: Add the Kotlin library as a Maven dependency or include the `android/Gutenberg/` module

See the [Integration Guide](./docs/integration.md) for detailed setup instructions and code examples for integrating GutenbergKit into your app.

For integrating GutenbergKit into the WordPress mobile apps specifically, see the [WordPress App Integration](./docs/wordpress-app-integration.md) guide.

## Get Involved

Join the conversation in the [#mobile](https://wordpress.slack.com/archives/C02RQC4LY) channel on [WordPress Slack](https://make.wordpress.org/chat/).
