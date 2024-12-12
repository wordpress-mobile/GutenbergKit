# GutenbergKit

An experimental Gutenberg block editor for native iOS and Android apps relying upon web technologies.

<img width="320" alt="GutenbergKit running on an iPhone" src="./docs/gutenberg-kit-preview.png">

## Development

### Preqrequisites

The following tools are must be installed on your development machine to build GutenbergKit:

-   [Node.js](https://nodejs.org/en/download/) - Required for building the web app; recommend using [Node Version Manager](https://github.com/nvm-sh/nvm).
-   [Xcode](https://developer.apple.com/xcode/) - Required if building for iOS demo app.
-   [Android Studio](https://developer.android.com/studio) - Required if building for Android demo app.

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
1. Launch Xcode and open the `ios/GutenbergKit.xcodeproj` project.
1. Select the `Gutenberg` target.
1. Navigate to _Product_ → _Scheme_ → _Edit Scheme_.
1. Add an environment variable named `GUTENBERG_SERVER_URL` with the URL of the development server.
1. Run the app.

<details>
<summary>Example Xcode environment variable</summary>

<img width="725" alt="Xcode environment variables" src="https://github.com/kean/GutenbergKit/assets/1567433/cdc8a28a-c621-4b8e-bc7a-31361694434c">

</details>

#### Android

1. Start the development server by running `make dev-server`.
1. Launch Android Studio and open the `android` project.
1. Open the `GutenbergView.kt` file.
1. Change the `ASSET_URL` constant to the URL of the development server.
1. Run the app.

<details>
<summary>Example Android code change</summary>

```diff
diff --git a/android/Gutenberg/src/main/java/org/wordpress/gutenberg/GutenbergView.kt b/android/Gutenberg/src/main/java/org/wordpress/gutenberg/GutenbergView.kt
index bda0e51..3014479 100644
--- a/android/Gutenberg/src/main/java/org/wordpress/gutenberg/GutenbergView.kt
+++ b/android/Gutenberg/src/main/java/org/wordpress/gutenberg/GutenbergView.kt
@@ -188,7 +188,7 @@ class GutenbergView : WebView {
         // this value out of the `dist` directory after building GutenbergKit
         //
         // This URL maps to the `assets` directory in this module
-        this.loadUrl(ASSET_URL)
+        this.loadUrl("http://<YOUR_LOCAL_IP>:5173")

         // Dev mode – you can connect the app to a local dev server and have it refresh as
         // changes are made. To start the server, run `make dev-server` in the project root

```

</details>

## Production

To build GutenbergKit for production run the following command in your terminal:

```bash
make build
```

Once finished, the Swift and Kotlin packages are ready to publish. Consuming iOS or Android host apps can then include the GutenbergKit package as a dependency.
