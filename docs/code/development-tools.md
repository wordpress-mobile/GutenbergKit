# Development Tools

This guide covers debugging tools and development features available in GutenbergKit.

## Development Mode

Development mode (`?dev_mode` query parameter) enables debugging features and bypasses certain production behaviors to simplify development and testing:

-   **Development notice is displayed** - A warning notice appears to inform developers that they're running in development mode.
-   **Mock GBKit global is provided** - If the native bridge (`window.GBKit`) is not available, a mock object is automatically provided to allow the editor to load without native integration.
-   **React Dev Tools integration** - The editor connects to the React Dev Tools standalone server for component inspection and debugging. See the React Dev Tools section below for setup instructions.

Add the `?dev_mode` query parameter to the editor URL:

```
http://localhost:3000/?dev_mode
```

## React Dev Tools

The [React Developer Tools](https://react.dev/learn/react-developer-tools) allow inspecting React components, view props and state, and debug the component tree during development. GutenbergKit supports the standalone DevTools server for both browser and native WebView debugging.

1. Start the standalone DevTools server:

    ```bash
    make dev-tools
    ```

    This opens a standalone window that will display your React component tree.

2. Start the development server:

    ```bash
    make dev-server
    ```

3. For Android emulators only, set up port forwarding:

    ```bash
    adb reverse tcp:8097 tcp:8097
    ```

4. Load the editor with development mode enabled:

    Browser or iOS simulator:

    ```
    http://localhost:5173/?dev_mode
    ```

    Android emulator:

    ```
    http://10.0.2.2:5173/?dev_mode
    ```

    The editor will automatically connect to the DevTools server, and your component tree will appear in the standalone window.

## Logging Configuration

The logger utility (`src/utils/logger.js`) supports different log levels that can be controlled via:

-   The `logLevel` editor configuration option, for controlling the client console;
-   And Node.js environment variables (`LOG_LEVEL=<level>`), for project scripts.

The default log level is `info`. The project's demo app defaults to `debug`. Available log levels are:

-   `error`: Logs only error messages
-   `warn`: Logs warnings and errors
-   `info`: Logs informational messages, warnings, and errors
-   `debug`: Logs detailed debugging information, informational messages, warnings, and errors
