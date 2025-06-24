# GutenbergKit

An experimental Gutenberg block editor for native iOS and Android apps relying upon web technologies.

<img width="320" alt="GutenbergKit running on an iPhone" src="./docs/gutenberg-kit-preview.png">

## Development

### Preqrequisites

In order to build GutenbergKit, the following tools must be installed on your development machine:

-   [Node.js](https://nodejs.org/en/download/) - Required for building the web app; recommend using [Node Version Manager](https://github.com/nvm-sh/nvm).
-   [Xcode](https://developer.apple.com/xcode/) - Required if building iOS demo app.
-   [Android Studio](https://developer.android.com/studio) - Required if building Android demo app.

### Web App

Install the GutenbergKit dependencies and start the development server by running the following command in your terminal:

```bash
make dev-server
```

Once finished, the web app can now be accessed in your browser by visiting the URL logged in your terminal. However, it is recommended to use a native host app for testing the changes made to the editor for a more realistic experience. A demo app is included in the GutenbergKit package, along with instructions on how to use it below.

### Demo App

This demo app is useful for quickly testing changes made to the editor. By default, the demo app uses a production build of the web app bundled with the GutenbergKit package—i.e., the output of the project's `make build` command. During development, however, it is more useful to run the web app with a server and provide the server URL as an environment variable for the demo app, so that changes are displayed in the app immediately.

#### iOS

1. Start the development server by running `make dev-server`.
1. Launch Xcode and open the `ios/Demo-iOS/Gutenberg.xcodeproj` project.
1. Select the `Gutenberg` target.
1. Navigate to _Product_ → _Scheme_ → _Edit Scheme_.
1. Add an environment variable named `GUTENBERG_EDITOR_URL` with the URL of the development server.
1. Run the app.

<details>
<summary>Example Xcode environment variable</summary>

<img width="725" alt="Example Xcode environment variable" src="./docs/example-xcode-env-variable.png">

</details>

#### Android

1. Start the development server by running `make dev-server`.
1. Launch Android Studio and open the `android` project.
1. Modify the `android/local.properties` file to include an environment variable named `GUTENBERG_EDITOR_URL` with the URL of the development server.
1. Run the app.

<details>
<summary>Example Android local.properties</summary>

```
GUTENBERG_EDITOR_URL=http://<YOUR_LOCAL_IP>:5173/
```

</details>

## Testing

To run the JavaScript tests, run the following command in your terminal:

```bash
make test-js
```

To run the Swift tests, run the following command in your terminal:

```bash
make test-swift
```

To run the Android tests, run the following command in your terminal:

```bash
make test-android
```

## Production

To build GutenbergKit for production run the following command in your terminal:

```bash
make build
```

Once finished, the Swift and Kotlin packages are ready to publish. Consuming iOS or Android host apps can then include the GutenbergKit package as a dependency.

## Remote Editor

Some blocks are only available while using the remote editor. To enable it in development environment:

1. Run `make dev-server-remote`
1. Add `GUTENBERG_EDITOR_REMOTE_URL` (the same way `GUTENBERG_EDITOR_URL` is added for that platform) and use `http://<YOUR_LOCAL_IP>:5173/remote.html` as the value
1. Remote editor will redirect to the local editor if it fails to load. If you need to debug that failure, disable the redirection in [`src/remote.jsx`](https://github.com/wordpress-mobile/GutenbergKit/blob/trunk/src/remote.jsx#L52) & [`src/utils/remote-editor.js`](https://github.com/wordpress-mobile/GutenbergKit/blob/trunk/src/utils/remote-editor.js#L64). Note that the line numbers might have changed.
