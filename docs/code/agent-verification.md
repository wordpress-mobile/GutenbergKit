# Agent Verification

This guide covers how an AI agent, or a developer, can build, launch, drive, and check the demo apps to verify a change. It relies on the tools Xcode and the Android SDK provide; which agent and permissions you use is up to you.

## Choosing a Check

Use the narrowest check that exercises the change:

-   **Web-only logic** in `src/`: run `make test-web-unit` and `make test-web-e2e`, or load the dev server (`make serve-dev`) in a browser.
-   **Native code, the bridge, or WebView behavior**: run a demo app.
-   **The bundled editor**: run `make build` and load it instead of the dev server when the change affects the build output, asset loading, translations, or network requests. On both platforms, the editor's origin differs between the two, so CORS applies differently. Otherwise, the dev server avoids rebuilding the app for web changes.

See [Getting Started](./getting-started.md) for choosing the editor source on each platform.

## Demo App Reference

|                | iOS                                                    | Android                       |
| -------------- | ------------------------------------------------------ | ----------------------------- |
| Project        | `ios/Demo-iOS/Gutenberg.xcodeproj`, scheme `Gutenberg` | `android/`, module `app`      |
| App ID (debug) | `org.wordpress.gutenberg.development`                  | `com.example.gutenbergkit`    |
| Sign in        | `make login-ios-app`                                   | `make login-android-app`      |
| Native logs    | Xcode console; library subsystem `GutenbergKit`        | `adb logcat`                  |
| Editor logs    | Xcode console; subsystem `com.gutenbergkit.demo`       | `adb logcat -s GutenbergView` |
| Web inspector  | Safari Web Inspector (_Develop_ menu)                  | `chrome://inspect`            |

See [Demo App Sign-In](./demo-app-login.md) for the credentials the sign-in targets read.

## iOS

Xcode's MCP tools and its `device-interaction` skill can build, run, and drive the demo app on a simulator.

To load the bundled editor for one run without editing the scheme, pass `{"$(inherited)": "", "GUTENBERG_EDITOR_URL": ""}` as the app's environment variables when running it with Xcode's tools.

Without Xcode's tools, `xcrun simctl` can install, launch, and screenshot the app, but not tap. `simctl launch` passes environment variables only with a `SIMCTL_CHILD_` prefix, e.g., `SIMCTL_CHILD_GUTENBERG_EDITOR_URL`.

Safari Web Inspector covers the editor's WebView for developers. Agents can use [ios_webkit_debug_proxy](https://github.com/google/ios-webkit-debug-proxy), pointed at the simulator's inspector socket; it speaks WebKit's protocol rather than Chrome's.

## Android

Google's Android CLI (`android`) reads the layout and screen of a running app, and `android init` installs its agent skills. Build, install, and launch the demo app with:

```bash
./android/gradlew -p android :app:installDebug
adb shell am start -n com.example.gutenbergkit/.MainActivity
```

### Editor WebView

Debug builds expose the editor's WebView over the Chrome DevTools Protocol. Developers can open `chrome://inspect` in Chrome. Agents can forward the WebView's socket and connect directly:

```bash
# Find the socket, named after the app's process ID
adb shell cat /proc/net/unix | grep webview_devtools_remote

# Forward it, then list the inspectable pages and their WebSocket URLs
adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>
curl http://localhost:9222/json
```

Sending `Runtime.evaluate` to a page's `webSocketDebuggerUrl` evaluates JavaScript in the editor, e.g., to read `location.href` or the editor's state. Remove the forward with `adb forward --remove tcp:9222` when done.
