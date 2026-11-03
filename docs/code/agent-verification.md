# Agent Verification

This guide covers how an AI agent, or a developer, can build, launch, drive, and check the demo apps to verify a change. It relies on the tools Xcode and the Android SDK provide; which agent and permissions you use is up to you.

## Choosing a Check

Use the narrowest check that exercises the change:

-   **Web-only logic** in `src/`: run `make test-web-unit` and `make test-web-e2e`, or load the dev server (`make serve-dev`) in a browser.
-   **Native code, the bridge, or WebView behavior**: run a demo app.
-   **The bundled editor**: run `make build` and load it instead of the dev server when the change affects the build output, asset loading, or translations. Otherwise, the dev server avoids rebuilding the app for web changes.

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

Xcode 27 provides an MCP server and agent skills for building, running, and driving apps on a simulator or device. Enable Xcode's tools for external agents in Xcode's _Settings_ → _Intelligence_, and keep Xcode running.

Load the tools and skills into an agent with Xcode's packaged plugin:

```bash
# Claude Code; Xcode also packages the `codex` and `gemini` formats
claude --plugin-dir "$(xcrun mcpbridge run-agent plugin path --plugin-format claude)"
```

Alternatively, `xcrun mcpbridge run-agent claude` launches Claude Code with the same configuration, and `xcrun mcpbridge` alone serves the MCP tools to any MCP client.

The plugin's `device-interaction` skill describes the session lifecycle: start a workspace session, install and run the app, then tap, type, and capture screenshots and the UI hierarchy. Follow its instructions to run it in a subagent.

To load the bundled editor for one run without editing the scheme, pass `{"$(inherited)": "", "GUTENBERG_EDITOR_URL": ""}` as the install-and-run tool's environment variables.

Without Xcode's tools, `xcodebuild` builds the app and `xcrun simctl` installs, launches, and captures screenshots of it, but cannot tap. `simctl launch` passes scheme environment variables only with a `SIMCTL_CHILD_` prefix, e.g., `SIMCTL_CHILD_GUTENBERG_EDITOR_URL`.

## Android

Google's Android CLI (`android`, in the SDK's command-line tools) reads the screen and layout of a running app. `android init` installs its agent skills.

```bash
# Build, install, and launch the demo app
./android/gradlew -p android :app:installDebug
adb shell am start -n com.example.gutenbergkit/.MainActivity

# Read the layout, with each element's bounds
android layout --flat

# Capture the screen; --annotate labels the UI elements it detects
android screen capture --output=<file>.png

# Tap and type
adb shell input tap <x> <y>
adb shell input text '<text>'
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
