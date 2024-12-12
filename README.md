# GutenbergKit

An experimental Gutenberg block editor for native iOS and Android apps relying upon web technologies.

<img width="320" alt="Screenshot 2024-07-01 at 10 30 11 AM" src="https://github.com/kean/GutenbergKit/assets/1567433/4d9b2fcd-30fa-46ca-895d-07e0848143b1">

## Development

### Preqrequisites

The following tools are must be installed on your development machine to build GutenbergKit:

-   [Node.js](https://nodejs.org/en/download/) - Required for building the web app; recommend using [Node Version Manager](https://github.com/nvm-sh/nvm).
-   [Xcode](https://developer.apple.com/xcode/) - Required if building for iOS demo host app.
-   [Android Studio](https://developer.android.com/studio) - Required if building for Android demo host app.

### Web App

Install the GutenbergKit dependencies and start the development server by running the following command in the terminal:

```bash
make dev-server
```

Once finished, the web app can now be accessed in your browser via the URL logged in the terminal. However, it is recommended to use a native host app for testing the changes made to the editor. A demo host app is included in the GutenbergKit package.

### Demo Host App

This demo host app can be used for testing the quickly changes made to the editor. By default, the demo app uses a production build of the web app bundled with the GutenbergKit package. During development, it is more helpful to run the web app and set the localhost URL as an environment variable for the demo host app so that changes are displayed immediately within the app.

Example Xcode environment variable:

<img width="725" alt="Xcode environment variables" src="https://github.com/kean/GutenbergKit/assets/1567433/cdc8a28a-c621-4b8e-bc7a-31361694434c">

## Production

To build the GutenbergKit for production run:

```
make build
```

Once finished, the Swift and Kotlin packages are ready to publish. Consuming iOS or Android host apps can then include the GutenbergKit package as a dependency.
