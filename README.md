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

## Releases

See the [release documentation](./docs/releases.md) for more information.

## Remote Editor

By default, GutenbergKit utilizes local `@wordpress` modules. This approach is similar to most modern web applications, where the `@wordpress` modules are bundled with the application.
To enable support for non-core blocks, GutenbergKit can be configured to use remote `@wordpress` modules, where the `@wordpress` modules and plugin-provided editor assets are fetched from a site's remote server. At this time, this functionality is partially implemented and may not work as expected.

The `make build` command builds both the local and remote editors by default. To load the remote editor, you must enable the `plugins` configuration option within the Demo app.

Additionally, a `make dev-server-remote` command is available for serving the latest remote editor changes through a development server. To load the development server in the Demo app, add an environment variable named `GUTENBERG_EDITOR_REMOTE_URL` with the URL of the development server plus `/remote.html`—i.e., `http://<YOUR_LOCAL_IP>:5173/remote.html`.

> [!TIP]
> The remote editor redirects to the local editor when loading fails. If you need to debug the failure, temporarily remove the `window.location` redirect in [`src/remote.jsx`](https://github.com/wordpress-mobile/GutenbergKit/blob/a211f6cd0391a8d15ae4570d28c66b12ef020134/src/remote.jsx#L52) and [`src/utils/remote-editor.js`](https://github.com/wordpress-mobile/GutenbergKit/blob/a211f6cd0391a8d15ae4570d28c66b12ef020134/src/utils/remote-editor.js#L64).
