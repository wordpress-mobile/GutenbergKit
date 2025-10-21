# Running GutenbergKit Demo on Physical Devices

Running the GutenbergKit Demo app on physical devices requires additional configuration compared to running on emulators/simulators. This guide provides step-by-step instructions for both iOS and Android platforms.

## Overview

When running the demo app on a physical device, the device needs to access the development server running on your development machine. This requires:

1. Ensuring the physical device can reach your development machine over the network
2. Configuring the app to use your development machine's IP address
3. Platform-specific network security configurations

## Prerequisites

-   Your physical device and development machine must be on the same network
-   The development server must be running (`make dev-server`)
-   You need to know your development machine's IP address

### Finding Your Development Machine's IP Address

**macOS:**

```bash
ipconfig getifaddr en0
```

**Linux:**

```bash
hostname -I | awk '{print $1}'
```

**Windows:**

```bash
ipconfig
```

Look for your local network IP address (typically in the format `192.168.x.x` or `10.x.x.x`).

## iOS Configuration

1. Start the development server by running `make dev-server`.
2. Launch Xcode and open the `ios/Demo-iOS/Gutenberg.xcodeproj` project.
3. Select the `Gutenberg` target.
4. Navigate to _Product_ → _Scheme_ → _Edit Scheme_.
5. Add an environment variable named `GUTENBERG_EDITOR_URL` with your development machine's IP address and port.
    - Example: `http://192.168.1.100:5173/`
6. Connect your iOS device via USB or network.
7. Select your device as the run destination in Xcode.
8. Run the app.

> [!NOTE]
> iOS allows http connections to local network addresses by default through App Transport Security exceptions configured in the demo app's Info.plist.

## Android Configuration

### 1. Configure the Editor URL

1. Start the development server by running `make dev-server`.
2. Launch Android Studio and open the `android` project.
3. Modify the `android/local.properties` file to include an environment variable named `GUTENBERG_EDITOR_URL` with your development machine's IP address and port.
    - Example: `GUTENBERG_EDITOR_URL=http://192.168.1.100:5173/`

### 2. Modify Network Security Configuration

Android requires explicit network security configuration to allow cleartext (http) traffic to non-localhost addresses.

**Temporarily** modify `android/app/src/main/res/xml/network_security_config.xml` to include your development machine's IP address:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">10.0.2.2</domain>
        <!-- Add your development machine's IP address here -->
        <domain includeSubdomains="true">192.168.1.100</domain>
    </domain-config>
</network-security-config>
```

> [!IMPORTANT]
> Remember to revert this change before committing your code. This configuration should only be used for local development and should never be pushed to version control or used in production builds.

### 3. Run the App

1. Connect your Android device via USB.
2. Enable USB debugging on your device.
3. Select your device in Android Studio's device dropdown.
4. Run the app.

## Troubleshooting

### Cannot Connect to Development Server

-   Verify both devices are on the same network
-   Check your firewall settings to ensure port 5173 (or your Vite dev server port) is accessible
-   Confirm the development server is running and accessible from your machine's browser

### Android Network Security Errors

If you see network security or cleartext traffic errors:

-   Verify you've added your IP address to `network_security_config.xml`
-   Confirm the IP address matches your development machine's current IP
-   Clean and rebuild the Android project

### iOS Connection Refused

-   Verify the URL includes the correct protocol (`http://`)
-   Check that your iOS device is on the same network as your development machine
-   Ensure no VPN or network restrictions are blocking the connection
